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
        if (company.tech_ui_state == null || !company.tech_ui_state.rawin("mode") || company.tech_ui_state.mode != "exempt") {
            this.ClearTechStoryPage(company, tech_advance);
            local msg_id = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0,
                GSText(GSText.STR_TECH_EXEMPT_MESSAGE));
            company.tech_ui_state = { mode = "exempt", msg_id = msg_id };
        }
        return;
    }

    this.EnsureTechUILayout(company, tech_advance);

    // Header
    local ui = company.tech_ui_state;
    local cost_k = tech_advance.RESEARCH_COST / 1000;
    GSStoryPage.UpdateElement(ui.header_id, 0, GSText(GSText.STR_TECH_HEADER, cost_k));

    // Company data
    if (!tech_advance.company_unlocks.rawin(company.id)) return;
    local company_data = tech_advance.company_unlocks[company.id];

    // Research queue navigation (layout version 3)
    local queue_len = company_data.research_queue.len();

    // Always display header
    GSStoryPage.UpdateElement(ui.queue_nav_header_id, 0, GSText(GSText.STR_TECH_QUEUE_NAV_HEADER));

    if (queue_len == 0) {
        // Empty queue - show all buttons in gray (invalid state)
        GSStoryPage.UpdateElement(ui.queue_nav_first_btn, ui.queue_nav_button_refs.first_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
        GSStoryPage.UpdateElement(ui.queue_nav_last_btn, ui.queue_nav_button_refs.last_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
        GSStoryPage.UpdateElement(ui.queue_nav_prev_btn, ui.queue_nav_button_refs.prev_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_PREV));
        GSStoryPage.UpdateElement(ui.queue_nav_next_btn, ui.queue_nav_button_refs.next_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));
        // Clear item info and show empty message
        GSStoryPage.UpdateElement(ui.queue_nav_item_info, 0, this.EmptyText());
        GSStoryPage.UpdateElement(ui.queue_nav_progress, 0, GSText(GSText.STR_TECH_QUEUE_NAV_EMPTY));
    } else {
        // Ensure index is valid
        if (ui.queue_nav_index >= queue_len) ui.queue_nav_index = queue_len - 1;
        if (ui.queue_nav_index < 0) ui.queue_nav_index = 0;

        // Update button colors based on current position
        local at_first = (ui.queue_nav_index == 0);
        local at_last = (ui.queue_nav_index == queue_len - 1);

        // First/Previous buttons: gray if at first position, green otherwise
        GSStoryPage.UpdateElement(ui.queue_nav_first_btn,
            at_first ? ui.queue_nav_button_refs.first_ivld : ui.queue_nav_button_refs.first_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
        GSStoryPage.UpdateElement(ui.queue_nav_prev_btn,
            at_first ? ui.queue_nav_button_refs.prev_ivld : ui.queue_nav_button_refs.prev_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_PREV));

        // Last/Next buttons: gray if at last position, green otherwise
        GSStoryPage.UpdateElement(ui.queue_nav_last_btn,
            at_last ? ui.queue_nav_button_refs.last_ivld : ui.queue_nav_button_refs.last_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
        GSStoryPage.UpdateElement(ui.queue_nav_next_btn,
            at_last ? ui.queue_nav_button_refs.next_ivld : ui.queue_nav_button_refs.next_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));

        // Display current item information
        local item = company_data.research_queue[ui.queue_nav_index];
        local engine_info = tech_advance.engine_data[item.engine_id];
        local current_num = ui.queue_nav_index + 1;  // 1-based display

        GSStoryPage.UpdateElement(ui.queue_nav_item_info, 0,
            GSText(GSText.STR_TECH_QUEUE_NAV_ITEM, engine_info.name, current_num, queue_len));

        // Display progress
        local progress_percent = 100 - ((item.progress * 100) / tech_advance.RESEARCH_DURATION);
        local months_remaining = item.progress;

        GSStoryPage.UpdateElement(ui.queue_nav_progress, 0,
            GSText(GSText.STR_TECH_QUEUE_NAV_PROGRESS, progress_percent, months_remaining));
    }

    // Update available counts cache
    tech_advance.UpdateAvailableCounts(company.id);

    // Determine filter
    local filter_vtype = ui.filter_vtype;

    // Get filtered available engines from cache
    local available = [];
    if (company_data.available_counts != null) {
        foreach (entry in company_data.available_counts.filtered) {
            if (filter_vtype == -1 || entry.vehicle_type == filter_vtype) {
                available.append(entry);
            }
        }
    }

    local total_available = available.len();

    // Clamp candidate_nav_index to valid range
    if (total_available == 0) {
        ui.candidate_nav_index = 0;
    } else {
        if (ui.candidate_nav_index < 0) ui.candidate_nav_index = 0;
        if (ui.candidate_nav_index >= total_available) ui.candidate_nav_index = total_available - 1;
    }

    // Update vehicle type statistics (always shown)
    local counts = company_data.available_counts;
    local unlocked_rail = 0, unlocked_road = 0, unlocked_water = 0, unlocked_air = 0;
    local total_rail = 0, total_road = 0, total_water = 0, total_air = 0;

    foreach (engine_id, engine_info in tech_advance.engine_data) {
        switch (engine_info.vehicle_type) {
            case GSVehicle.VT_RAIL:
                total_rail++;
                if (company_data.unlocked_engines.rawin(engine_id)) unlocked_rail++;
                break;
            case GSVehicle.VT_ROAD:
                total_road++;
                if (company_data.unlocked_engines.rawin(engine_id)) unlocked_road++;
                break;
            case GSVehicle.VT_WATER:
                total_water++;
                if (company_data.unlocked_engines.rawin(engine_id)) unlocked_water++;
                break;
            case GSVehicle.VT_AIR:
                total_air++;
                if (company_data.unlocked_engines.rawin(engine_id)) unlocked_air++;
                break;
        }
    }

    GSStoryPage.UpdateElement(ui.candidate_type_stats_rail, 0, GSText(GSText.STR_TECH_TYPE_RAIL, unlocked_rail, total_rail));
    GSStoryPage.UpdateElement(ui.candidate_type_stats_road, 0, GSText(GSText.STR_TECH_TYPE_ROAD, unlocked_road, total_road));
    GSStoryPage.UpdateElement(ui.candidate_type_stats_water, 0, GSText(GSText.STR_TECH_TYPE_WATER, unlocked_water, total_water));
    GSStoryPage.UpdateElement(ui.candidate_type_stats_air, 0, GSText(GSText.STR_TECH_TYPE_AIR, unlocked_air, total_air));

    // Update filter button label (keep red color)
    local filter_label = this.GetTechFilterLabel(filter_vtype);
    GSStoryPage.UpdateElement(ui.candidate_filter_btn, ui.candidate_nav_button_refs.filter_red, filter_label);

    // Update research candidate display
    if (total_available == 0) {
        // Empty state - gray button, empty text
        GSStoryPage.UpdateElement(ui.candidate_vehicle_name, 0, GSText(GSText.STR_TECH_CANDIDATE_NAV_EMPTY));
        GSStoryPage.UpdateElement(ui.candidate_details, 0, this.EmptyText());
        GSStoryPage.UpdateElement(ui.candidate_research_btn, ui.candidate_nav_button_refs.research_ivld, this.EmptyText());
        GSStoryPage.UpdateElement(ui.candidate_nav_index_info, 0, GSText(GSText.STR_TECH_CANDIDATE_NAV_INDEX, 0, 0));
        // Disable navigation buttons (gray color)
        GSStoryPage.UpdateElement(ui.candidate_nav_first_btn, ui.candidate_nav_button_refs.first_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
        GSStoryPage.UpdateElement(ui.candidate_nav_last_btn, ui.candidate_nav_button_refs.last_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
        GSStoryPage.UpdateElement(ui.candidate_nav_prev_btn, ui.candidate_nav_button_refs.prev_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_PREV));
        GSStoryPage.UpdateElement(ui.candidate_nav_next_btn, ui.candidate_nav_button_refs.next_ivld, GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));
        // Clear button mapping
        if (tech_advance.button_element_map.rawin(ui.candidate_research_btn)) {
            delete tech_advance.button_element_map[ui.candidate_research_btn];
        }
    } else {
        local current = available[ui.candidate_nav_index];
        local is_first = (ui.candidate_nav_index == 0);
        local is_last = (ui.candidate_nav_index == total_available - 1);

        // Update vehicle name
        GSStoryPage.UpdateElement(ui.candidate_vehicle_name, 0, GSText(GSText.STR_TECH_CANDIDATE_NAV_ITEM, current.name));

        // Fetch vehicle details from GSEngine API
        local vtype_name = "";
        switch (current.vehicle_type) {
            case GSVehicle.VT_RAIL:  vtype_name = "Railway"; break;
            case GSVehicle.VT_ROAD:  vtype_name = "Road Vehicle"; break;
            case GSVehicle.VT_WATER: vtype_name = "Ship"; break;
            case GSVehicle.VT_AIR:   vtype_name = "Aircraft"; break;
        }

        local max_speed = GSEngine.GetMaxSpeed(current.engine_id);
        local capacity = GSEngine.GetCapacity(current.engine_id);
        local price = GSEngine.GetPrice(current.engine_id);
        local running_cost = GSEngine.GetRunningCost(current.engine_id);

        // Update details with comprehensive information
        GSStoryPage.UpdateElement(ui.candidate_details, 0,
            GSText(GSText.STR_TECH_CANDIDATE_DETAILS,
                vtype_name, max_speed, capacity, price, running_cost));

        // Update research button (blue/available)
        GSStoryPage.UpdateElement(ui.candidate_research_btn, ui.candidate_nav_button_refs.research_avai, GSText(GSText.STR_TECH_BUTTON_RESEARCH, cost_k));
        tech_advance.button_element_map[ui.candidate_research_btn] <- { kind = "research", engine_id = current.engine_id };

        // Update index display (e.g., "1 / 5")
        GSStoryPage.UpdateElement(ui.candidate_nav_index_info, 0, GSText(GSText.STR_TECH_CANDIDATE_NAV_INDEX, ui.candidate_nav_index + 1, total_available));

        // Update navigation buttons (gray when at boundary, green when available)
        GSStoryPage.UpdateElement(ui.candidate_nav_first_btn,
            is_first ? ui.candidate_nav_button_refs.first_ivld : ui.candidate_nav_button_refs.first_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
        GSStoryPage.UpdateElement(ui.candidate_nav_last_btn,
            is_last ? ui.candidate_nav_button_refs.last_ivld : ui.candidate_nav_button_refs.last_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
        GSStoryPage.UpdateElement(ui.candidate_nav_prev_btn,
            is_first ? ui.candidate_nav_button_refs.prev_ivld : ui.candidate_nav_button_refs.prev_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_PREV));
        GSStoryPage.UpdateElement(ui.candidate_nav_next_btn,
            is_last ? ui.candidate_nav_button_refs.next_ivld : ui.candidate_nav_button_refs.next_avai,
            GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));
    }

    // Footer
    GSStoryPage.UpdateElement(ui.footer_id, 0, this.EmptyText());
}

function StoryEditor::EmptyText()
{
    return GSText(GSText.STR_STRING, GSText(GSText.STR_EMPTY));
}

function StoryEditor::TruncateString(value, max_len)
{
    if (value == null) return "";
    if (max_len == null || max_len <= 0) return value;
    if (value.len() <= max_len) return value;
    if (max_len <= 3) return value.slice(0, max_len);
    return value.slice(0, max_len - 3) + "...";
}

function StoryEditor::GetTechFilterLabel(filter_vtype)
{
    switch (filter_vtype) {
        case GSVehicle.VT_RAIL:  return GSText(GSText.STR_TECH_FILTER_RAIL);
        case GSVehicle.VT_ROAD:  return GSText(GSText.STR_TECH_FILTER_ROAD);
        case GSVehicle.VT_WATER: return GSText(GSText.STR_TECH_FILTER_WATER);
        case GSVehicle.VT_AIR:   return GSText(GSText.STR_TECH_FILTER_AIR);
        default:                 return GSText(GSText.STR_TECH_FILTER_ALL);
    }
}

function StoryEditor::CycleFilterVType(current_vtype)
{
    switch (current_vtype) {
        case -1: return GSVehicle.VT_RAIL;
        case GSVehicle.VT_RAIL: return GSVehicle.VT_ROAD;
        case GSVehicle.VT_ROAD: return GSVehicle.VT_WATER;
        case GSVehicle.VT_WATER: return GSVehicle.VT_AIR;
        case GSVehicle.VT_AIR: return -1;
        default: return -1;
    }
}

function StoryEditor::ClearTechStoryPage(company, tech_advance)
{
    if (company.sp_tech == null || !GSStoryPage.IsValidStoryPage(company.sp_tech)) return;

    local elements = GSStoryPageElementList(company.sp_tech);
    foreach (element, _ in elements) {
        if (tech_advance != null && tech_advance.button_element_map != null && tech_advance.button_element_map.rawin(element)) {
            delete tech_advance.button_element_map[element];
        }
        GSStoryPage.RemoveElement(element);
    }
}

function StoryEditor::EnsureTechUILayout(company, tech_advance)
{
    if (company.tech_ui_state != null && company.tech_ui_state.rawin("layout_version") && company.tech_ui_state.layout_version == 4) {
        return;
    }

    // Reset existing page content and rebuild a fixed-slot layout
    this.ClearTechStoryPage(company, tech_advance);

    // Create button references with float flags
    local button_colour = GSStoryPage.SPBC_WHITE;
    local button_colour_avai = GSStoryPage.SPBC_GREEN;
    local button_colour_ivld = GSStoryPage.SPBC_WHITE;
    local ref_float_left = GSStoryPage.MakePushButtonReference(button_colour, GSStoryPage.SPBF_FLOAT_LEFT);
    local ref_float_right = GSStoryPage.MakePushButtonReference(button_colour, GSStoryPage.SPBF_FLOAT_RIGHT);
    local ref_float_left_avai = GSStoryPage.MakePushButtonReference(button_colour_avai, GSStoryPage.SPBF_FLOAT_LEFT);
    local ref_float_right_avai = GSStoryPage.MakePushButtonReference(button_colour_avai, GSStoryPage.SPBF_FLOAT_RIGHT);
    local ref_float_left_ivld = GSStoryPage.MakePushButtonReference(button_colour_ivld, GSStoryPage.SPBF_FLOAT_LEFT);
    local ref_float_right_ivld = GSStoryPage.MakePushButtonReference(button_colour_ivld, GSStoryPage.SPBF_FLOAT_RIGHT);
    
    // Create non-floating button references for filter and research buttons
    local ref_red = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_RED, 0);
    local ref_blue = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_DARK_BLUE, 0);
    local ref_white = GSStoryPage.MakePushButtonReference(GSStoryPage.SPBC_WHITE, 0);

    local ui = {
        layout_version = 4,
        mode = "normal",
        filter_vtype = -1,
        candidate_nav_index = 0,
        queue_nav_index = 0,
        engine_slots = []
    };

    // Header
    ui.header_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Check initial queue state to set correct button colors
    local queue_len = 0;
    if (tech_advance.company_unlocks.rawin(company.id)) {
        queue_len = tech_advance.company_unlocks[company.id].research_queue.len();
    }

    // Determine initial button colors based on queue state
    local init_first_ref, init_last_ref, init_prev_ref, init_next_ref;
    if (queue_len == 0) {
        // Empty queue: all buttons gray
        init_first_ref = ref_float_left_ivld;
        init_last_ref = ref_float_right_ivld;
        init_prev_ref = ref_float_left_ivld;
        init_next_ref = ref_float_right_ivld;
    } else if (queue_len == 1) {
        // Single item: all buttons gray (can't navigate)
        init_first_ref = ref_float_left_ivld;
        init_last_ref = ref_float_right_ivld;
        init_prev_ref = ref_float_left_ivld;
        init_next_ref = ref_float_right_ivld;
    } else {
        // Multiple items, index=0: First/Prev gray, Last/Next green
        init_first_ref = ref_float_left_ivld;
        init_last_ref = ref_float_right_avai;
        init_prev_ref = ref_float_left_ivld;
        init_next_ref = ref_float_right_avai;
    }

    // Research queue navigation area (new layout)
    // Row 1: Header + Quick jump buttons
    ui.queue_nav_first_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_first_ref, GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
    ui.queue_nav_last_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_last_ref, GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
    ui.queue_nav_header_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_TECH_QUEUE_NAV_HEADER));

    // Row 2: Navigation buttons + Current item info
    ui.queue_nav_prev_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_prev_ref, GSText(GSText.STR_TECH_QUEUE_NAV_PREV));
    ui.queue_nav_next_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_next_ref, GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));
    ui.queue_nav_item_info <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Row 3: Progress details
    ui.queue_nav_progress <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Store button reference IDs for color switching
    ui.queue_nav_button_refs <- {
        first_avai = ref_float_left_avai,
        first_ivld = ref_float_left_ivld,
        last_avai = ref_float_right_avai,
        last_ivld = ref_float_right_ivld,
        prev_avai = ref_float_left_avai,
        prev_ivld = ref_float_left_ivld,
        next_avai = ref_float_right_avai,
        next_ivld = ref_float_right_ivld
    };

    // Register queue navigation buttons
    tech_advance.button_element_map[ui.queue_nav_first_btn] <- { kind = "queue_nav", action = "first" };
    tech_advance.button_element_map[ui.queue_nav_last_btn] <- { kind = "queue_nav", action = "last" };
    tech_advance.button_element_map[ui.queue_nav_prev_btn] <- { kind = "queue_nav", action = "prev" };
    tech_advance.button_element_map[ui.queue_nav_next_btn] <- { kind = "queue_nav", action = "next" };

    // Research candidate navigation
    ui.candidate_nav_separator <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_SEPARATOR));
    ui.candidate_nav_header <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, GSText(GSText.STR_TECH_CANDIDATE_NAV_HEADER));

    // Vehicle type statistics
    ui.candidate_type_stats_rail <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    ui.candidate_type_stats_road <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    ui.candidate_type_stats_water <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    ui.candidate_type_stats_air <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Filter toggle button (red, non-floating, always enabled)
    ui.candidate_filter_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_red, this.EmptyText());
    tech_advance.button_element_map[ui.candidate_filter_btn] <- { kind = "filter_toggle" };

    // Index info and First/Last buttons
    ui.candidate_nav_first_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_first_ref, GSText(GSText.STR_TECH_QUEUE_NAV_FIRST));
    ui.candidate_nav_last_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_last_ref, GSText(GSText.STR_TECH_QUEUE_NAV_LAST));
    ui.candidate_nav_index_info <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    tech_advance.button_element_map[ui.candidate_nav_first_btn] <- { kind = "candidate_nav", action = "first" };
    tech_advance.button_element_map[ui.candidate_nav_last_btn] <- { kind = "candidate_nav", action = "last" };

    // Vehicle name and Prev/Next buttons
    ui.candidate_nav_prev_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_prev_ref, GSText(GSText.STR_TECH_QUEUE_NAV_PREV));
    ui.candidate_nav_next_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, init_next_ref, GSText(GSText.STR_TECH_QUEUE_NAV_NEXT));
    ui.candidate_vehicle_name <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    tech_advance.button_element_map[ui.candidate_nav_prev_btn] <- { kind = "candidate_nav", action = "prev" };
    tech_advance.button_element_map[ui.candidate_nav_next_btn] <- { kind = "candidate_nav", action = "next" };

    // Vehicle details
    ui.candidate_details <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Research button (white when invalid, blue when available, non-floating)
    ui.candidate_research_btn <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_white, this.EmptyText());
    tech_advance.button_element_map[ui.candidate_research_btn] <- { kind = "research", engine_id = -1 };

    // Store button reference IDs for color switching (candidate navigation)
    ui.candidate_nav_button_refs <- {
        first_avai = ref_float_left_avai,
        first_ivld = ref_float_left_ivld,
        last_avai = ref_float_right_avai,
        last_ivld = ref_float_right_ivld,
        prev_avai = ref_float_left_avai,
        prev_ivld = ref_float_left_ivld,
        next_avai = ref_float_right_avai,
        next_ivld = ref_float_right_ivld,
        research_avai = ref_blue,
        research_ivld = ref_white,
        filter_red = ref_red
    };

    // Footer
    ui.footer_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    company.tech_ui_state = ui;
}

/* Wrapper that creates a new StoryPage but disable date output. */
function StoryEditor::NewStoryPage(company, text)
{
    local value = GSStoryPage.New(company, text);
    if (value != GSStoryPage.STORY_PAGE_INVALID) GSStoryPage.SetDate(value, GSDate.DATE_INVALID);
    return value;
}
