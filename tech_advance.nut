import("util.superlib", "SuperLib", 40);
Log <- SuperLib.Log;

class TechAdvance {
    engine_data = null;           // Table: engine_id -> {name, intro_date, expire_date, vehicle_type}
    name_to_ids = null;           // Table: composite_key (name|vtype|intro_date) -> [engine_id, ...]
    company_unlocks = null;       // Table: company_id -> {unlocked_engines, research_queue}
    game_start_date = null;       // Game start date for auto-unlocking historical vehicles
    last_check_year = null;       // Last year we checked for new available engines
    button_element_map = null;    // Transient table: element_id -> action table (for story page buttons)
    
    // Callback references (set via SetCallbackInfo)
    story_editor = null;          // Reference to StoryEditor for UI updates
    companies = null;             // Reference to companies list
    
    // Time tracking for periodic updates
    current_month = null;         // Current month for monthly updates
    current_year = null;          // Current year for yearly updates
    
    // Research configuration
    static RESEARCH_COST = 100000;           // Fixed cost per engine (£100,000)
    static RESEARCH_DURATION = 6;            // Fixed duration in months
    
    constructor() {
        GSGameSettings.SetValue("vehicle.never_expire_vehicles", 0);
        local game_start_year = GSDate.GetYear(GSDate.GetCurrentDate());
        GSGameSettings.SetValue("vehicle.no_introduce_vehicles_after", game_start_year);
        GSGameSettings.SetValue("vehicle.no_expire_vehicles_after", 0);
        
        this.engine_data = {};
        this.name_to_ids = {};
        this.company_unlocks = {};
        this.button_element_map = {};
        this.game_start_date = GSDate.GetCurrentDate();
        this.last_check_year = GSDate.GetYear(this.game_start_date);
        
        // Initialize time tracking
        this.current_month = GSDate.GetMonth(this.game_start_date);
        this.current_year = GSDate.GetYear(this.game_start_date);

        Log.Info("TechAdvance: Loading all vehicle engines...", Log.LVL_INFO);
        this.LoadEngineData();
        Log.Info("TechAdvance: Loaded " + this.engine_data.len() + " engines", Log.LVL_INFO);
    }
};

function TechAdvance::LoadEngineData() {
    // Iterate through all vehicle types and load engine data
    local vehicle_types = [
        GSVehicle.VT_RAIL,
        GSVehicle.VT_ROAD,
        GSVehicle.VT_WATER,
        GSVehicle.VT_AIR
    ];
    
    foreach (vtype in vehicle_types) {
        local engine_list = GSEngineList(vtype);
        foreach (engine_id, _ in engine_list) {
            if (GSEngine.IsValidEngine(engine_id)) {
                local name = GSEngine.GetName(engine_id);
                local intro_date = GSEngine.GetDesignDate(engine_id);
                local vehicle_type = GSEngine.GetVehicleType(engine_id);
                
                // Store engine metadata
                this.engine_data[engine_id] <- {
                    name = name,
                    intro_date = intro_date,
                    vehicle_type = vehicle_type
                };
                
                // Build name-to-IDs mapping (composite key: "name|vehicle_type|intro_date")
                local composite_key = name + "|" + vehicle_type + "|" + intro_date;
                if (!this.name_to_ids.rawin(composite_key)) {
                    this.name_to_ids[composite_key] <- [];
                }
                this.name_to_ids[composite_key].append(engine_id);
            }
        }
    }
}

function TechAdvance::UpdateCompanyList() {
    // Initialize unlock tracking for all valid companies
    for (local c = GSCompany.COMPANY_FIRST; c <= GSCompany.COMPANY_LAST; c++) {
        if (GSCompany.ResolveCompanyID(c) == GSCompany.COMPANY_INVALID) continue;
        
        if (!this.company_unlocks.rawin(c)) {
            Log.Info("TechAdvance: Initializing unlock tracking for company " + c, Log.LVL_INFO);
            
            // Initialize company unlock data
            this.company_unlocks[c] <- {
                unlocked_engines = {},    // Table: composite_key (name|vtype|intro_date) -> true
                research_queue = [],      // Array of {composite_key, progress}
                available_counts = null   // Cached: {total, rail, road, water, air, filtered[]}
            };
            
            // Check if company is exempted - use date-based unlocking instead
            if (GSToyLib.IsExemptedAI(c)) {
                Log.Info("TechAdvance: Company " + c + " is exempted, using date-based unlock", Log.LVL_INFO);
                this.UnlockEngineByDate(c);
            } else {
                // Auto-unlock historical vehicles (intro_date < game_start or intro_date == 0)
                foreach (engine_id, engine_info in this.engine_data) {
                    if (engine_info.intro_date < this.game_start_date || engine_info.intro_date == 0) {
                        local composite_key = engine_info.name + "|" + engine_info.vehicle_type + "|" + engine_info.intro_date;
                        this.company_unlocks[c].unlocked_engines[composite_key] <- true;
                    }
                }
                
                // Apply engine restrictions for this new company
                this.ApplyEngineRestrictions(c);
            }
        }
    }
    
    // Clean up data for companies that no longer exist
    local companies_to_remove = [];
    foreach (company_id, _ in this.company_unlocks) {
        if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) {
            companies_to_remove.append(company_id);
        }
    }
    foreach (company_id in companies_to_remove) {
        delete this.company_unlocks[company_id];
        Log.Info("TechAdvance: Removed unlock tracking for defunct company " + company_id, Log.LVL_INFO);
    }
}

function TechAdvance::ApplyEngineRestrictions(company_id) {
    // Skip exempt companies (AI that requested exemption)
    // Check if company is exempt via GSToyLib
    if (GSToyLib.IsExemptedAI(company_id)) {
        Log.Info("TechAdvance: Company " + company_id + " is exempt, skipping restrictions", Log.LVL_DEBUG);
        return;
    }
    
    if (!this.company_unlocks.rawin(company_id)) return;
    
    Log.Info("TechAdvance: Applying engine restrictions for company " + company_id, Log.LVL_DEBUG);
    
    // Use AsyncMode for batch operations to avoid blocking script
    local async = GSAsyncMode(true);
    
    local unlocked = this.company_unlocks[company_id].unlocked_engines;
    
    // Iterate through all composite_keys (unique engine name|vtype|intro_date combinations)
    // Enable unlocked engines, disable locked engines
    foreach (composite_key, engine_ids in this.name_to_ids) {
        local is_unlocked = unlocked.rawin(composite_key);
        
        // Apply restriction to all engine variants with this name|vtype|intro_date
        foreach (engine_id in engine_ids) {
            if (is_unlocked) {
                GSEngine.EnableForCompany(engine_id, company_id);
            } else {
                GSEngine.DisableForCompany(engine_id, company_id);
            }
        }
    }
    
    // Destroy async mode instance to restore normal mode
    async = null;
    
    Log.Info("TechAdvance: Applied restrictions for " + this.engine_data.len() + " engines", Log.LVL_DEBUG);
}

function TechAdvance::UnlockEngineByDate(company_id) {
    // Enable engines based on introduction date for exempted companies
    // Called monthly to unlock newly-introduced vehicles
    
    if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) return;
    
    local current_date = GSDate.GetCurrentDate();
    local enabled_count = 0;
    
    // Use AsyncMode for batch operations
    local async = GSAsyncMode(true);
    
    // Iterate through all composite_keys and enable vehicles where intro_date <= current_date
    foreach (composite_key, engine_ids in this.name_to_ids) {
        if (engine_ids.len() == 0) continue;
        
        // Get engine info from first variant
        local representative_id = engine_ids[0];
        if (!this.engine_data.rawin(representative_id)) continue;
        local engine_info = this.engine_data[representative_id];
        
        // Enable if intro_date has passed or is 0 (always available)
        local should_enable = (engine_info.intro_date == 0 || engine_info.intro_date <= current_date);
        
        // Apply to all engine variants with this composite_key
        foreach (engine_id in engine_ids) {
            if (should_enable) {
                GSEngine.EnableForCompany(engine_id, company_id);
                enabled_count++;
            } else {
                GSEngine.DisableForCompany(engine_id, company_id);
            }
        }
    }
    
    // Destroy async mode instance
    async = null;
    
    Log.Info("TechAdvance: UnlockEngineByDate for exempted company " + company_id + 
             ", enabled " + enabled_count + " engine variants", Log.LVL_DEBUG);
}

function TechAdvance::UpdateAvailableCounts(company_id) {
    if (!this.company_unlocks.rawin(company_id)) return;

    local company_data = this.company_unlocks[company_id];
    local current_date = GSDate.GetCurrentDate();

    // Build researching engines set (by composite_key)
    local researching_engines = {};
    foreach (item in company_data.research_queue) {
        researching_engines[item.composite_key] <- true;
    }

    // Count available engines per vehicle type
    local counts = {
        total = 0,
        rail = 0,
        road = 0,
        water = 0,
        air = 0,
        filtered = []  // Array to store unique composite_keys with representative engine_id
    };

    // Iterate through name_to_ids (already organized by composite_key, naturally deduplicated)
    foreach (composite_key, engine_ids in this.name_to_ids) {
        // Use first engine variant as representative
        if (engine_ids.len() == 0) continue;
        local representative_id = engine_ids[0];
        
        if (!this.engine_data.rawin(representative_id)) continue;
        local engine_info = this.engine_data[representative_id];
        
        // Skip if not yet introduced
        if (engine_info.intro_date > 0 && engine_info.intro_date > current_date) continue;
        // Skip if already unlocked (check by composite_key)
        if (company_data.unlocked_engines.rawin(composite_key)) continue;
        // Skip if currently being researched (check by composite_key)
        if (researching_engines.rawin(composite_key)) continue;

        counts.total++;
        counts.filtered.append({ 
            engine_id = representative_id, 
            intro_date = engine_info.intro_date, 
            name = engine_info.name, 
            vehicle_type = engine_info.vehicle_type 
        });

        switch (engine_info.vehicle_type) {
            case GSVehicle.VT_RAIL: counts.rail++; break;
            case GSVehicle.VT_ROAD: counts.road++; break;
            case GSVehicle.VT_WATER: counts.water++; break;
            case GSVehicle.VT_AIR: counts.air++; break;
        }
    }

    // Sort filtered list by intro_date, then name
    counts.filtered.sort(function(a, b) {
        if (a.intro_date < b.intro_date) return -1;
        if (a.intro_date > b.intro_date) return 1;
        if (a.name < b.name) return -1;
        if (a.name > b.name) return 1;
        return 0;
    });

    company_data.available_counts = counts;
}

function TechAdvance::StartResearch(company_id, composite_key) {
    // Validate company and composite_key
    if (GSCompany.ResolveCompanyID(company_id) == GSCompany.COMPANY_INVALID) {
        Log.Warning("TechAdvance: Invalid company " + company_id + " trying to research");
        return false;
    }
    
    if (!this.name_to_ids.rawin(composite_key)) {
        Log.Warning("TechAdvance: Invalid composite_key \"" + composite_key + "\" requested for research");
        return false;
    }
    
    if (!this.company_unlocks.rawin(company_id)) {
        Log.Warning("TechAdvance: Company " + company_id + " not in unlock tracking");
        return false;
    }
    
    local company_data = this.company_unlocks[company_id];
    
    // Check if already unlocked
    if (company_data.unlocked_engines.rawin(composite_key)) {
        Log.Info("TechAdvance: Engine \"" + composite_key + "\" already unlocked for company " + company_id, Log.LVL_DEBUG);
        return false;
    }
    
    // Check if already in research queue
    foreach (item in company_data.research_queue) {
        if (item.composite_key == composite_key) {
            Log.Info("TechAdvance: Engine \"" + composite_key + "\" already in research queue", Log.LVL_DEBUG);
            return false;
        }
    }
    
    // Check if company can afford it
    local balance = GSCompany.GetBankBalance(company_id);
    if (balance < RESEARCH_COST) {
        Log.Info("TechAdvance: Company " + company_id + " cannot afford research (balance: £" + balance + ")", Log.LVL_INFO);
        return false;
    }
    
    // Deduct cost using ChangeBankBalance (GameScript deity mode, NOT in company mode)
    // Use GSMap.TILE_INVALID as location (standard for script-initiated expenses)
    if (!GSCompany.ChangeBankBalance(company_id, -RESEARCH_COST, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID)) {
        Log.Warning("TechAdvance: Failed to deduct research cost from company " + company_id);
        return false;
    }
    
    // Add to research queue
    company_data.research_queue.append({
        composite_key = composite_key,
        progress = RESEARCH_DURATION
    });
    
    // Get engine name for logging (use first variant)
    local engine_ids = this.name_to_ids[composite_key];
    local engine_name = (engine_ids.len() > 0) ? this.engine_data[engine_ids[0]].name : composite_key;
    
    Log.Info("TechAdvance: Company " + company_id + " started researching \"" + engine_name + 
             "\" (" + engine_ids.len() + " variants)", Log.LVL_INFO);
    
    return true;
}

function TechAdvance::ProcessResearch() {
    // Process research queue for all companies
    // Returns: array of company IDs that completed at least one research
    local companies_with_completed = [];
    
    foreach (company_id, company_data in this.company_unlocks) {
        if (company_data.research_queue.len() == 0) continue;
        
        local completed_indices = [];
        
        // Update progress for all items in queue
        for (local i = 0; i < company_data.research_queue.len(); i++) {
            local item = company_data.research_queue[i];
            item.progress--;
            
            // Check if research completed
            if (item.progress <= 0) {
                completed_indices.append(i);
                
                // Unlock the engine (by composite_key)
                company_data.unlocked_engines[item.composite_key] <- true;
                
                // Enable all engine variants with this name|vtype
                if (this.name_to_ids.rawin(item.composite_key)) {
                    foreach (engine_id in this.name_to_ids[item.composite_key]) {
                        GSEngine.EnableForCompany(engine_id, company_id);
                    }
                    
                    // Log completion (use first variant for display)
                    local engine_ids = this.name_to_ids[item.composite_key];
                    if (engine_ids.len() > 0) {
                        local sample_id = engine_ids[0];
                        Log.Info("TechAdvance: Company " + company_id + " completed research: " + 
                                 this.engine_data[sample_id].name + " (" + engine_ids.len() + " variants)", Log.LVL_INFO);
                    }
                } else {
                    Log.Warning("TechAdvance: Completed research for missing engine: " + item.composite_key);
                }
            }
        }
        
        // Remove completed items from queue (in reverse order to maintain indices)
        completed_indices.reverse();
        foreach (index in completed_indices) {
            company_data.research_queue.remove(index);
        }
        
        // Track companies that completed research
        if (completed_indices.len() > 0) {
            companies_with_completed.append(company_id);
        }
    }
    
    return companies_with_completed;
}

function TechAdvance::CheckNewAvailableEngines() {
    // Check if any new engines have reached their introduction date
    local current_date = GSDate.GetCurrentDate();
    local current_year = GSDate.GetYear(current_date);
    
    // Only check once per year
    if (current_year == this.last_check_year) return false;
    
    this.last_check_year = current_year;
    local new_engines_available = false;
    
    Log.Info("TechAdvance: Checking for new available engines (year " + current_year + ")", Log.LVL_INFO);
    
    foreach (engine_id, engine_info in this.engine_data) {
        // Check if engine just became available (intro_date is between last year and now)
        if (engine_info.intro_date > 0 && 
            engine_info.intro_date >= GSDate.GetDate(current_year - 1, 1, 1) &&
            engine_info.intro_date <= current_date) {
            Log.Info("TechAdvance: New engine available: " + engine_info.name + " (ID: " + engine_id + ")", Log.LVL_INFO);
            new_engines_available = true;
        }
    }
    
    return new_engines_available;
}

function TechAdvance::HandleUnlockButton(company_id, element_id) {
    // Handle button click from story page
    // Map element_id back to composite_key (research actions only)
    if (!this.button_element_map.rawin(element_id)) {
        Log.Warning("TechAdvance: Unknown element_id " + element_id + " clicked");
        return false;
    }
    
    local action = this.button_element_map[element_id];
    if (typeof(action) != "table" || !action.rawin("kind")) return false;
    if (action.kind != "research" || !action.rawin("composite_key")) return false;
    return this.StartResearch(company_id, action.composite_key);
}

function TechAdvance::Manage() {
    // Monthly updates
    local date = GSDate.GetCurrentDate();
    local month = GSDate.GetMonth(date);
    if (month != this.current_month) {
        // Process ongoing research (monthly)
        local companies_completed = this.ProcessResearch();
        
        // Update exempted companies with date-based unlocking (monthly)
        if (this.companies != null) {
            foreach (company in this.companies) {
                if (company.is_exempted) {
                    this.UnlockEngineByDate(company.id);
                }
            }
        }
        
        // Update tech pages monthly
        if (this.story_editor != null && this.companies != null) {
            // Build set of companies that need updates
            local companies_to_update = {};
            
            // 1. Update companies with active research (to show progress)
            foreach (company in this.companies) {
                if (!this.company_unlocks.rawin(company.id)) continue;
                if (this.company_unlocks[company.id].research_queue.len() > 0) {
                    companies_to_update[company.id] <- true;
                }
            }
            
            // 2. Also update companies that completed research (to refresh available engines)
            foreach (company_id in companies_completed) {
                companies_to_update[company_id] <- true;
            }
            
            // Perform updates
            foreach (company in this.companies) {
                if (companies_to_update.rawin(company.id)) {
                    this.story_editor.UpdateTechPage(company, this);
                }
            }
        }
        this.current_month = month;
    }
    
    // Yearly updates
    local year = GSDate.GetYear(date);
    if (year != this.current_year) {
        Log.Info("TechAdvance: Yearly check for new engines (year " + year + ")...", Log.LVL_INFO);
        
        // Check for new available engines
        local new_engines = this.CheckNewAvailableEngines();
        
        // Update tech pages if new engines became available
        if (new_engines && this.story_editor != null && this.companies != null) {
            Log.Info("TechAdvance: New engines available, updating tech pages", Log.LVL_INFO);
            foreach (company in this.companies) {
                this.story_editor.UpdateTechPage(company, this);
            }
        }
        
        this.current_year = year;
    }
}

function TechAdvance::SetCallbackInfo(story_editor, companies) {
    this.story_editor = story_editor;
    this.companies = companies;
}

function TechAdvance::Save() {
    // Save all tech advance data
    local save_data = {
        game_start_date = this.game_start_date,
        last_check_year = this.last_check_year,
        company_unlocks = {}
    };
    
    // Save company unlock data
    foreach (company_id, company_data in this.company_unlocks) {
        save_data.company_unlocks[company_id] <- {
            unlocked_engines = [],        // Array of composite_keys
            research_queue = [],
            available_counts = null
        };
        
        // Save unlocked engines as array of composite_keys
        foreach (composite_key, _ in company_data.unlocked_engines) {
            save_data.company_unlocks[company_id].unlocked_engines.append(composite_key);
        }
        
        // Save research queue with composite_keys
        foreach (item in company_data.research_queue) {
            save_data.company_unlocks[company_id].research_queue.append({
                composite_key = item.composite_key,
                progress = item.progress
            });
        }
    }
    
    Log.Info("TechAdvance: Saved data for " + this.company_unlocks.len() + " companies", Log.LVL_INFO);
    return save_data;
}

function TechAdvance::Load(saved_data) {
    // Restore saved data
    if (saved_data == null) {
        Log.Warning("TechAdvance: No saved data to load");
        return false;
    }
    
    this.game_start_date = saved_data.game_start_date;
    this.last_check_year = saved_data.last_check_year;
    
    // Button mapping is transient and rebuilt when pages are (re)drawn
    this.button_element_map = {};
    
    // Restore company unlocks
    foreach (company_id, company_data in saved_data.company_unlocks) {
        this.company_unlocks[company_id] <- {
            unlocked_engines = {},
            research_queue = [],
            available_counts = null
        };
        
        // Restore unlocked engines (validate composite_keys exist in current NewGRF)
        foreach (composite_key in company_data.unlocked_engines) {
            if (this.name_to_ids.rawin(composite_key)) {
                this.company_unlocks[company_id].unlocked_engines[composite_key] <- true;
            } else {
                Log.Warning("TechAdvance: Saved unlocked engine not found in current NewGRF: " + composite_key);
            }
        }
        
        // Restore research queue (validate composite_keys exist in current NewGRF)
        foreach (item in company_data.research_queue) {
            if (this.name_to_ids.rawin(item.composite_key)) {
                this.company_unlocks[company_id].research_queue.append({
                    composite_key = item.composite_key,
                    progress = item.progress
                });
            } else {
                Log.Warning("TechAdvance: Saved research item not found in current NewGRF: " + item.composite_key);
            }
        }
        
        // Reapply engine restrictions after loading (important!)
        // Use date-based unlocking for exempted companies
        if (GSToyLib.IsExemptedAI(company_id)) {
            this.UnlockEngineByDate(company_id);
        } else {
            this.ApplyEngineRestrictions(company_id);
        }
    }
    
    Log.Info("TechAdvance: Loaded data for " + this.company_unlocks.len() + " companies", Log.LVL_INFO);
    return true;
}
