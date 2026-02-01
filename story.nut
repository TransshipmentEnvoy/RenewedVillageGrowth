class StoryEditor
{
    supply_impacting_part = null;
    eternal_love = null;
    limit_min_transport = null;
    limiter_delay = null;

    sp_cargo = null;
    sp_custom = null;
    sp_warning = null;

    constructor() {
        this.supply_impacting_part = GSController.GetSetting("supply_impacting_part");
        this.eternal_love = GSController.GetSetting("eternal_love");
        this.limit_min_transport = GSController.GetSetting("limit_min_transport");
        this.limiter_delay = GSController.GetSetting("limiter_delay");
    }
}

/* Checks if any parameters were changed and modifies the story page to reflect the change */
function StoryEditor::CheckParameters(companies)
{
    local supply_impacting_part = GSController.GetSetting("supply_impacting_part");
    local eternal_love = GSController.GetSetting("eternal_love");
    local limit_min_transport = GSController.GetSetting("limit_min_transport");
    local limiter_delay = GSController.GetSetting("limiter_delay");

    if (this.supply_impacting_part != supply_impacting_part
            || this.eternal_love != eternal_love
            || this.limit_min_transport != limit_min_transport
            || this.limiter_delay != limiter_delay) {

        foreach (company in companies) {
            local sp_welcome_elements = GSStoryPageElementList(company.sp_welcome);
            foreach (element, _ in sp_welcome_elements) {
                GSStoryPage.RemoveElement(element);
            }

            this.supply_impacting_part = supply_impacting_part;
            this.eternal_love = eternal_love;
            this.limit_min_transport = limit_min_transport;
            this.limiter_delay = limiter_delay;

            this.WelcomePage(company.sp_welcome);
        }
    }
}

/* Create a page showing information about this GS */
function StoryEditor::WelcomePage(sp_welcome)
{    
    GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_DESC));
    
    if (GSText.STR_SB_CUSTOM_END - GSText.STR_SB_CUSTOM_TITLE > 1) {
        GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_CUSTOM_WELCOME, GSText(GSText.STR_SB_CUSTOM_TITLE)));
    }
    
    GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_CARGO, GSText(GSText.STR_ECONOMY_NONE + ::Economy), ::CargoCatNum, this.supply_impacting_part));
    GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_STATISTICS));

    if (this.limit_min_transport > 0) {
        local limiter_cargos = 0;
        foreach (cargo in ::CargoLimiter) {
            limiter_cargos = limiter_cargos | 1 << cargo;
        }

        local limiter_delay_text = this.limiter_delay > 0 ? GSText(GSText.STR_SB_WELCOME_LIMIT_GROWTH_DELAY, this.limiter_delay) : GSText(GSText.STR_STRING, GSText(GSText.STR_EMPTY));
        GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_LIMIT_GROWTH, limiter_cargos, this.limit_min_transport, limiter_delay_text));
    }

    if (this.eternal_love > 0) {
        GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_ETERNAL_LOVE, GSText(GSText.STR_ETERNAL_LOVE_OUTSTANDING + this.eternal_love - 1)));
    }

    GSStoryPage.NewElement(sp_welcome, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WELCOME_END));
}

/* Create a page showing informations about cargo categories. */
function StoryEditor::CargoInfoPage(sp_cargo)
{
    // Creation of the page
    local rand_type = 0; // 0 = NONE, 1 = FIXED, 2 = RANGE
    local rand_1, rand_2;

    switch (::SettingsTable.randomization) {
        case Randomization.FIXED_1:
        case Randomization.FIXED_2:
        case Randomization.FIXED_3:
            rand_1 = ::SettingsTable.randomization - Randomization.FIXED_1 + 1;
            rand_type = 1;
            break;
        case Randomization.FIXED_5:
            rand_1 = 5;
            rand_type = 1;
            break;
        case Randomization.FIXED_7:
            rand_1 = 7;
            rand_type = 1;
            break;

        case Randomization.RANGE_1_2:
            rand_1 = 1;
            rand_2 = 2;
            rand_type = 2;
            break;
        case Randomization.RANGE_1_3:
            rand_1 = 1;
            rand_2 = 3;
            rand_type = 2;
            break;
        case Randomization.RANGE_2_3:
            rand_1 = 2;
            rand_2 = 3;
            rand_type = 2;
            break;
        case Randomization.RANGE_3_5:
            rand_1 = 3;
            rand_2 = 5;
            rand_type = 2;
            break;
        case Randomization.RANGE_3_7:
            rand_1 = 3;
            rand_2 = 7;
            rand_type = 2;
            break;
    }

    switch (rand_type) {
        case 1: // FIXED
            GSStoryPage.NewElement(sp_cargo, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_EXPLAIN_2, GSText(GSText.STR_SB_EXPLAIN_RANDOM_0, rand_1, GSText(GSText.STR_EMPTY))));
            break;
        case 2: // RANGE
            GSStoryPage.NewElement(sp_cargo, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_EXPLAIN_2, GSText(GSText.STR_SB_EXPLAIN_RANDOM_2, rand_1, rand_2)));
            break;
        default:
            GSStoryPage.NewElement(sp_cargo, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_EXPLAIN_1));
    }

    // Adding elements per categories
    for (local i = 0; i < ::CargoCatNum; i++) {
        local bit_sum = 0;
        if (::SettingsTable.randomization != Randomization.INDUSTRY_DESC
         && ::SettingsTable.randomization != Randomization.INDUSTRY_ASC) {
            for (local j = 0; j < ::CargoCat[i].len(); j++) {
                bit_sum += 1 << ::CargoCat[i][j];
            }
        }

        GSStoryPage.NewElement(sp_cargo, GSStoryPage.SPET_TEXT, 0,
                       GSText(GSText["STR_SB_CARGOCAT_"+i],
                         GSText(GSText.STR_SB_CARGOCAT_CAT), i+1,
                         GSText(GSText["STR_CARGOCAT_LABEL_"+::CargoCatList[i]]),
                         GSText(GSText.STR_SB_CARGOCAT_POP), ::CargoMinPopDemand[i],
                         GSText(GSText.STR_SB_CARGOCAT_DECAY), (::CargoDecay[i]*100).tointeger(),
                         GSText(GSText.STR_SB_CARGOCAT_CARGOT), bit_sum));
    }
}

/* Create a page showing custom information like server rules. */
function StoryEditor::CustomPage(sp_custom)
{
    for (local i = GSText.STR_SB_CUSTOM_TITLE + 1; i < GSText.STR_SB_CUSTOM_END; i++) {
        GSStoryPage.NewElement(sp_custom, GSStoryPage.SPET_TEXT, 0, GSText(i));
    }
}

/* Create the StoryBook if it still doesn't exist. This function is
 * called only when (re)initializing all data, because the existing
 * storybook is stored by OTTD.
 */
function StoryEditor::CreateStoryBook(companies, num_towns, init_error, tech_advance)
{
    // Remove any eventual previous existent storypage
    local sb_list = GSStoryPageList(0);
    foreach (page, _ in sb_list) GSStoryPage.Remove(page);

    if (!init_error) {
        // Create basic cargo informations page
        this.sp_cargo = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_TITLE_1));
        this.CargoInfoPage(this.sp_cargo);

        // Create custom page
        if (GSText.STR_SB_CUSTOM_END - GSText.STR_SB_CUSTOM_TITLE > 1) {
            this.sp_custom = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_CUSTOM_TITLE));
            this.CustomPage(this.sp_custom);
        }

        foreach (company in companies) {
            // Create welcome page
            company.sp_welcome = this.NewStoryPage(company.id, GSText(GSText.STR_SB_WELCOME_TITLE, SELF_MAJORVERSION, SELF_MINORVERSION));
            this.WelcomePage(company.sp_welcome);
            GSStoryPage.Show(company.sp_welcome);
            
            // Create technology tree page (only if tech_advance is enabled)
            if (tech_advance != null) {
                company.sp_tech = this.NewStoryPage(company.id, GSText(GSText.STR_TECH_TREE_TITLE));
            }
        }
    }

    switch (init_error) {
        // Issue a warning if there are more towns on the map than the GS can save
        case InitError.TOWN_NUMBER:
            this.sp_warning = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_WARNING_TITLE));
            GSStoryPage.NewElement(this.sp_warning, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WARNING_1, num_towns, SELF_MAX_TOWNS));
            GSStoryPage.Show(this.sp_warning);
            break;
        // Issue a warning that the cargo list initialization has failed
        case InitError.CARGO_LIST:
            this.sp_warning = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_WARNING_TITLE));
            GSStoryPage.NewElement(this.sp_warning, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WARNING_2));
            GSStoryPage.Show(this.sp_warning);
            break;
        // Issue a warning that the cargo list initialization has failed
        case InitError.INDUSTRY_LIST:
            this.sp_warning = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_WARNING_TITLE));
            GSStoryPage.NewElement(this.sp_warning, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WARNING_3));
            GSStoryPage.Show(this.sp_warning);
            break;
        case InitError.TOWN_GROWTH_RATE:
            this.sp_warning = this.NewStoryPage(GSCompany.COMPANY_INVALID, GSText(GSText.STR_SB_WARNING_TITLE));
            GSStoryPage.NewElement(this.sp_warning, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SB_WARNING_4));
            GSStoryPage.Show(this.sp_warning);
            break;
    }
}

function StoryEditor::CreateNewCompanyStoryBook(company, tech_advance)
{
    // Create welcome page
    company.sp_welcome = this.NewStoryPage(company.id, GSText(GSText.STR_SB_WELCOME_TITLE, SELF_MAJORVERSION, SELF_MINORVERSION));
    this.WelcomePage(company.sp_welcome);
    GSStoryPage.Show(company.sp_welcome);
    
    // Create technology tree page (only if tech_advance is enabled)
    if (tech_advance != null) {
        company.sp_tech = this.NewStoryPage(company.id, GSText(GSText.STR_TECH_TREE_TITLE));
    }
}

/* Create or update technology tree page for a company */
function StoryEditor::CreateTechPage(company, tech_advance)
{
    if (company.sp_tech == null || !GSStoryPage.IsValidStoryPage(company.sp_tech)) {
        company.sp_tech = this.NewStoryPage(company.id, GSText(GSText.STR_TECH_TREE_TITLE));
    }
    
    this.UpdateTechPage(company, tech_advance);
}

function StoryEditor::UpdateTechPage(company, tech_advance)
{
    if (company.sp_tech == null || !GSStoryPage.IsValidStoryPage(company.sp_tech)) return;
    if (tech_advance == null) return;
    
    // Skip for exempt companies
    if (company.is_exempted) {
        // Clear page and show exemption message
        local elements = GSStoryPageElementList(company.sp_tech);
        foreach (element, _ in elements) {
            GSStoryPage.RemoveElement(element);
        }
        GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
            GSText(GSText.STR_TECH_EXEMPT_MESSAGE));
        return;
    }
    
    // Remove all existing elements and clear button mapping
    local elements = GSStoryPageElementList(company.sp_tech);
    foreach (element, _ in elements) {
        // Clear button mapping for this element
        if (tech_advance.button_element_map.rawin(element)) {
            delete tech_advance.button_element_map[element];
        }
        GSStoryPage.RemoveElement(element);
    }
    
    // Add header
    GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
        GSText(GSText.STR_TECH_HEADER, tech_advance.RESEARCH_COST / 1000));
    
    // Get company unlock data
    if (!tech_advance.company_unlocks.rawin(company.id)) return;
    local company_data = tech_advance.company_unlocks[company.id];
    
    // Show research queue status
    if (company_data.research_queue.len() > 0) {
        GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
            GSText(GSText.STR_TECH_RESEARCHING_HEADER));
        
        foreach (item in company_data.research_queue) {
            local engine_info = tech_advance.engine_data[item.engine_id];
            local progress_percent = 100 - ((item.progress * 100) / tech_advance.RESEARCH_DURATION);
            GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
                GSText(GSText.STR_TECH_RESEARCHING_ITEM, engine_info.name, progress_percent));
        }
    }
    
    // Group engines by vehicle type
    local current_date = GSDate.GetCurrentDate();
    local vehicle_type_names = {};
    vehicle_type_names[GSVehicle.VT_RAIL] <- GSText.STR_TECH_TYPE_RAIL;
    vehicle_type_names[GSVehicle.VT_ROAD] <- GSText.STR_TECH_TYPE_ROAD;
    vehicle_type_names[GSVehicle.VT_WATER] <- GSText.STR_TECH_TYPE_WATER;
    vehicle_type_names[GSVehicle.VT_AIR] <- GSText.STR_TECH_TYPE_AIR;
    
    foreach (vtype in [GSVehicle.VT_RAIL, GSVehicle.VT_ROAD, GSVehicle.VT_WATER, GSVehicle.VT_AIR]) {
        local available_engines = [];
        local locked_count = 0;
        local unlocked_count = 0;
        
        // Collect engines of this type that are available for research
        foreach (engine_id, engine_info in tech_advance.engine_data) {
            if (engine_info.vehicle_type != vtype) continue;
            
            // Only show engines that have reached their introduction date
            if (engine_info.intro_date > 0 && engine_info.intro_date > current_date) continue;
            
            // Check if unlocked or in research
            local is_unlocked = company_data.unlocked_engines.rawin(engine_id);
            local in_research = false;
            foreach (item in company_data.research_queue) {
                if (item.engine_id == engine_id) {
                    in_research = true;
                    break;
                }
            }
            
            if (is_unlocked) {
                unlocked_count++;
            } else if (!in_research) {
                available_engines.append(engine_id);
                locked_count++;
            }
        }
        
        // Always show vehicle type section
        GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
            GSText(vehicle_type_names[vtype], unlocked_count, locked_count + unlocked_count));
        
        // Show up to 10 available engines with research buttons (only if there are any)
        if (available_engines.len() > 0) {
            local shown = 0;
            foreach (engine_id in available_engines) {
                if (shown >= 10) {
                    GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
                        GSText(GSText.STR_TECH_MORE_AVAILABLE, available_engines.len() - shown));
                    break;
                }
                
                local engine_info = tech_advance.engine_data[engine_id];
                
                // Add text with engine name
                GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
                    GSText(GSText.STR_TECH_ENGINE_ITEM, engine_info.name));
                
                // Add research button (reference must be 0 for SPET_BUTTON_PUSH)
                local element_id = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, 
                    0, GSText(GSText.STR_TECH_BUTTON_RESEARCH, tech_advance.RESEARCH_COST / 1000));
                
                // Store mapping: element_id -> engine_id for event handling
                tech_advance.button_element_map[element_id] <- engine_id;
                
                shown++;
            }
        }
    }
    
    // Show message if no engines available
    local has_any_available = false;
    foreach (engine_id, engine_info in tech_advance.engine_data) {
        if (engine_info.intro_date > 0 && engine_info.intro_date > current_date) continue;
        if (!company_data.unlocked_engines.rawin(engine_id)) {
            has_any_available = true;
            break;
        }
    }
    
    if (!has_any_available && company_data.research_queue.len() == 0) {
        GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, 
            GSText(GSText.STR_TECH_NO_AVAILABLE));
    }
}

/* Wrapper that creates a new StoryPage but disable date output. */
function StoryEditor::NewStoryPage(company, text)
{
    local value = GSStoryPage.New(company, text);
    if (value != GSStoryPage.STORY_PAGE_INVALID) GSStoryPage.SetDate(value, GSDate.DATE_INVALID);
    return value;
}
