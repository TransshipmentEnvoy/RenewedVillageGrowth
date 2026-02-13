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

    // Research queue
    if (company_data.research_queue.len() > 0) {
        GSStoryPage.UpdateElement(ui.queue_header_id, 0, GSText(GSText.STR_TECH_RESEARCHING_HEADER));
    } else {
        GSStoryPage.UpdateElement(ui.queue_header_id, 0, this.EmptyText());
    }

    local max_queue_lines = ui.queue_item_ids.len();
    for (local i = 0; i < max_queue_lines; i++) {
        if (i < company_data.research_queue.len()) {
            local item = company_data.research_queue[i];
            local engine_info = tech_advance.engine_data[item.engine_id];
            local progress_percent = 100 - ((item.progress * 100) / tech_advance.RESEARCH_DURATION);
            GSStoryPage.UpdateElement(ui.queue_item_ids[i], 0,
                GSText(GSText.STR_TECH_RESEARCHING_ITEM, engine_info.name, progress_percent));
        } else {
            GSStoryPage.UpdateElement(ui.queue_item_ids[i], 0, this.EmptyText());
        }
    }

    if (company_data.research_queue.len() > max_queue_lines) {
        GSStoryPage.UpdateElement(ui.queue_more_id, 0,
            GSText(GSText.STR_TECH_MORE_RESEARCHING, company_data.research_queue.len() - max_queue_lines));
    } else {
        GSStoryPage.UpdateElement(ui.queue_more_id, 0, this.EmptyText());
    }

    // Build a set of engines currently being researched
    local researching_engines = {};
    foreach (item in company_data.research_queue) {
        researching_engines[item.engine_id] <- true;
    }

    // Determine filter
    local filter_vtype = ui.filter_vtype;
    local filter_label = this.GetTechFilterLabel(filter_vtype);

    // Collect available engines for this company & filter
    local current_date = GSDate.GetCurrentDate();
    local available = [];
    foreach (engine_id, engine_info in tech_advance.engine_data) {
        if (filter_vtype != -1 && engine_info.vehicle_type != filter_vtype) continue;
        if (engine_info.intro_date > 0 && engine_info.intro_date > current_date) continue;
        if (company_data.unlocked_engines.rawin(engine_id)) continue;
        if (researching_engines.rawin(engine_id)) continue;
        available.append({ engine_id = engine_id, intro_date = engine_info.intro_date, name = engine_info.name });
    }

    available.sort(function(a, b) {
        if (a.intro_date < b.intro_date) return -1;
        if (a.intro_date > b.intro_date) return 1;
        if (a.name < b.name) return -1;
        if (a.name > b.name) return 1;
        return 0;
    });

    local total_available = available.len();
    local page_size = ui.page_size;
    if (page_size <= 0) page_size = 10;

    // Clamp offset
    if (ui.offset < 0) ui.offset = 0;
    if (total_available == 0) {
        ui.offset = 0;
    } else {
        local max_offset = total_available - page_size;
        if (max_offset < 0) max_offset = 0;
        if (ui.offset > max_offset) ui.offset = max_offset;
    }

    local show_count = 0;
    if (total_available > ui.offset) {
        show_count = total_available - ui.offset;
        if (show_count > page_size) show_count = page_size;
    }

    // Page status
    local range_start = total_available > 0 ? ui.offset + 1 : 0;
    local range_end = total_available > 0 ? ui.offset + show_count : 0;
    GSStoryPage.UpdateElement(ui.status_id, 0,
        GSText(GSText.STR_TECH_PAGE_STATUS, filter_label, range_start, range_end, total_available));

    // Render page slots
    local max_name_len = 48;
    for (local i = 0; i < page_size; i++) {
        local name_id = null;
        local button_id = null;

        if (ui.rawin("engine_slots")) {
            if (i >= ui.engine_slots.len()) break;
            name_id = ui.engine_slots[i].name_id;
            button_id = ui.engine_slots[i].button_id;
        } else {
            // Backward compatibility: layout v1 (should be rare; kept for safety)
            name_id = ui.engine_name_ids[i];
            button_id = ui.engine_button_ids[i];
        }

        if (i < show_count) {
            local entry = available[ui.offset + i];
            local display_name = this.TruncateString(entry.name, max_name_len);
            GSStoryPage.UpdateElement(name_id, 0, GSText(GSText.STR_TECH_ENGINE_ITEM, display_name));
            GSStoryPage.UpdateElement(button_id, 0, GSText(GSText.STR_TECH_BUTTON_RESEARCH, cost_k));
            tech_advance.button_element_map[button_id] <- { kind = "research", engine_id = entry.engine_id };
        } else {
            GSStoryPage.UpdateElement(name_id, 0, this.EmptyText());
            GSStoryPage.UpdateElement(button_id, 0, this.EmptyText());
            if (tech_advance.button_element_map.rawin(button_id)) delete tech_advance.button_element_map[button_id];
        }
    }

    // Footer
    if (total_available == 0) {
        GSStoryPage.UpdateElement(ui.footer_id, 0, GSText(GSText.STR_TECH_NO_AVAILABLE));
    } else if (ui.offset + show_count < total_available) {
        GSStoryPage.UpdateElement(ui.footer_id, 0, GSText(GSText.STR_TECH_MORE_AVAILABLE, total_available - (ui.offset + show_count)));
    } else {
        GSStoryPage.UpdateElement(ui.footer_id, 0, this.EmptyText());
    }
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
    if (company.tech_ui_state != null && company.tech_ui_state.rawin("layout_version") && company.tech_ui_state.layout_version == 2) {
        return;
    }

    // Reset existing page content and rebuild a fixed-slot layout
    this.ClearTechStoryPage(company, tech_advance);

    // Create button references with float flags
    local button_colour = GSStoryPage.SPBC_WHITE;
    local ref_float_left = GSStoryPage.MakePushButtonReference(button_colour, GSStoryPage.SPBF_FLOAT_LEFT);
    local ref_float_right = GSStoryPage.MakePushButtonReference(button_colour, GSStoryPage.SPBF_FLOAT_RIGHT);

    local ui = {
        layout_version = 2,
        mode = "normal",
        filter_vtype = -1,
        offset = 0,
        page_size = 10,
        queue_item_ids = [],
        engine_slots = []
    };

    // Header
    ui.header_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Research queue area
    ui.queue_header_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
    for (local i = 0; i < 4; i++) {
        ui.queue_item_ids.append(GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText()));
    }
    ui.queue_more_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Controls row: filter + nav + status
    // Filter buttons (float left)
    local btn_all = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_left, GSText(GSText.STR_TECH_FILTER_ALL));
    local btn_rail = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_left, GSText(GSText.STR_TECH_FILTER_RAIL));
    local btn_road = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_left, GSText(GSText.STR_TECH_FILTER_ROAD));
    local btn_water = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_left, GSText(GSText.STR_TECH_FILTER_WATER));
    local btn_air = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_left, GSText(GSText.STR_TECH_FILTER_AIR));

    tech_advance.button_element_map[btn_all] <- { kind = "filter", vtype = -1 };
    tech_advance.button_element_map[btn_rail] <- { kind = "filter", vtype = GSVehicle.VT_RAIL };
    tech_advance.button_element_map[btn_road] <- { kind = "filter", vtype = GSVehicle.VT_ROAD };
    tech_advance.button_element_map[btn_water] <- { kind = "filter", vtype = GSVehicle.VT_WATER };
    tech_advance.button_element_map[btn_air] <- { kind = "filter", vtype = GSVehicle.VT_AIR };

    // Navigation buttons (float right)
    ui.nav_prev_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_right, GSText(GSText.STR_TECH_BUTTON_PREV));
    ui.nav_next_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_right, GSText(GSText.STR_TECH_BUTTON_NEXT));
    tech_advance.button_element_map[ui.nav_prev_id] <- { kind = "nav", delta = -1 };
    tech_advance.button_element_map[ui.nav_next_id] <- { kind = "nav", delta = 1 };

    // Status (anchor paragraph for floated controls)
    ui.status_id <- GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());

    // Engine list slots (fixed)
    for (local i = 0; i < ui.page_size; i++) {
        // Button floats right relative to the following paragraph (engine name)
        local button_id = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_BUTTON_PUSH, ref_float_right, this.EmptyText());
        local name_id = GSStoryPage.NewElement(company.sp_tech, GSStoryPage.SPET_TEXT, 0, this.EmptyText());
        ui.engine_slots.append({ name_id = name_id, button_id = button_id });
    }

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
