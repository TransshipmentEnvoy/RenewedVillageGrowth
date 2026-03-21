/*
 * highway_toll.nut
 * Optional highway toll feature for Renewed Village Growth Extended.
 *
 * Road vehicles are charged a daily toll based on the ownership of the tile
 * they currently occupy and the cargo they are carrying.
 *
 * Fee formula per vehicle:
 *   fee = (base_fee + cargo_rate * total_cargo_load) / TOLL_PRICE_DIVISOR
 *
 * Two road-ownership tiers:
 *   - Public/unowned/town road  (GSTile.GetOwner returns COMPANY_INVALID for all
 *                                 of these; the GS API cannot distinguish them)
 *   - Another company's road
 *
 * Fees are accumulated per company across all vehicles and settled in a
 * single ChangeBankBalance call per company per day, so each company's
 * account shows one clean daily toll entry.
 */

::TOLL_PRICE_DIVISOR <- 100;

class HighwayToll {
    toy_lib = null;
    last_processed_date = null;
    last_month = null;
    stats = null;   // { company_id: { paid_public_base, paid_public_cargo, paid_to_base: {}, paid_to_cargo: {}, received_from_base: {}, received_from_cargo: {} } }
}

function HighwayToll::constructor(toy_lib)
{
    this.toy_lib = toy_lib;
    local today = GSDate.GetCurrentDate();
    this.last_processed_date = today;
    this.last_month = GSDate.GetMonth(today);
    this.stats = {};
}

/*
 * Sum the current cargo load across all cargo types for a vehicle.
 */
function HighwayToll::GetVehicleTotalCargoLoad(vehicle_id, cargo_list)
{
    local total = 0;
    foreach (cargo_id, _ in cargo_list) {
        local load = GSVehicle.GetCargoLoad(vehicle_id, cargo_id);
        if (load > 0) total += load;
    }
    return total;
}

/*
 * Return a fresh per-company stats entry with base/cargo split.
 */
function HighwayToll::_NewStatsEntry()
{
    return {
        paid_public_base = 0, paid_public_cargo = 0,
        paid_to_base = {}, paid_to_cargo = {},
        received_from_base = {}, received_from_cargo = {}
    };
}

/*
 * Iterate all running road vehicles and accumulate per-company toll charges.
 * Updates this.stats in-place and returns a table { debit_map, credit_map }
 * where each map is company_id -> total amount for that day.
 */
function HighwayToll::GatherStats(fee_public, fee_company, cargo_rate_public, cargo_rate_company)
{
    local debit_map  = {};   // company_id -> total amount to deduct
    local credit_map = {};   // company_id -> total amount to credit

    // Cache the cargo list once for all vehicles
    local cargo_list = GSCargoList();

    local async = GSAsyncMode(true);
    local vehicle_list = GSVehicleList();
    foreach (vehicle_id, _ in vehicle_list) {
        if (GSVehicle.GetVehicleType(vehicle_id) != GSVehicle.VT_ROAD) continue;
        if (GSVehicle.GetState(vehicle_id) != GSVehicle.VS_RUNNING) continue;

        local vehicle_owner = GSVehicle.GetOwner(vehicle_id);
        if (vehicle_owner == GSCompany.COMPANY_INVALID) continue;

        local tile       = GSVehicle.GetLocation(vehicle_id);
        local tile_owner = GSTile.GetOwner(tile);

        local base_fee   = 0;
        local cargo_rate = 0;
        local road_owner = null;

        if (tile_owner == vehicle_owner) {
            // Own road – no toll
            continue;
        } else if (tile_owner == GSCompany.COMPANY_INVALID) {
            // Public / unowned / town road (API cannot distinguish)
            base_fee   = fee_public;
            cargo_rate = cargo_rate_public;
            road_owner = null;
        } else {
            // Another company's road
            base_fee   = fee_company;
            cargo_rate = cargo_rate_company;
            road_owner = tile_owner;
        }

        // Compute cargo surcharge
        local cargo_fee = 0;
        if (cargo_rate > 0) {
            local total_load = this.GetVehicleTotalCargoLoad(vehicle_id, cargo_list);
            cargo_fee = cargo_rate * total_load;
        }

        local fee = base_fee + cargo_fee;
        if (fee <= 0) continue;

        // Accumulate stats for story page display (base/cargo split)
        if (!this.stats.rawin(vehicle_owner)) {
            this.stats[vehicle_owner] <- this._NewStatsEntry();
        }
        local vs = this.stats[vehicle_owner];
        if (road_owner == null) {
            vs.paid_public_base  += base_fee;
            vs.paid_public_cargo += cargo_fee;
        } else {
            if (!vs.paid_to_base.rawin(road_owner))  vs.paid_to_base[road_owner]  <- 0;
            if (!vs.paid_to_cargo.rawin(road_owner)) vs.paid_to_cargo[road_owner] <- 0;
            vs.paid_to_base[road_owner]  += base_fee;
            vs.paid_to_cargo[road_owner] += cargo_fee;

            if (!this.stats.rawin(road_owner)) {
                this.stats[road_owner] <- this._NewStatsEntry();
            }
            local rs = this.stats[road_owner];
            if (!rs.received_from_base.rawin(vehicle_owner))  rs.received_from_base[vehicle_owner]  <- 0;
            if (!rs.received_from_cargo.rawin(vehicle_owner)) rs.received_from_cargo[vehicle_owner] <- 0;
            rs.received_from_base[vehicle_owner]  += base_fee;
            rs.received_from_cargo[vehicle_owner] += cargo_fee;
        }

        if (!debit_map.rawin(vehicle_owner)) debit_map[vehicle_owner] <- 0;
        debit_map[vehicle_owner] += fee;

        if (road_owner != null) {
            if (!credit_map.rawin(road_owner)) credit_map[road_owner] <- 0;
            credit_map[road_owner] += fee;
        }
    }
    async = null;

    return { debit_map = debit_map, credit_map = credit_map };
}

function HighwayToll::Manage(story_editor, companies)
{
    local today = GSDate.GetCurrentDate();
    if (today == this.last_processed_date) return;
    this.last_processed_date = today;

    local fee_public  = GSController.GetSetting("toll_fee_no_owner");
    local fee_company = GSController.GetSetting("toll_fee_company_road");
    local cargo_rate_public  = GSController.GetSetting("toll_cargo_rate_no_owner");
    local cargo_rate_company = GSController.GetSetting("toll_cargo_rate_company_road");

    // Nothing to do if all fees and rates are zero
    if (fee_public == 0 && fee_company == 0 && cargo_rate_public == 0 && cargo_rate_company == 0) return;

    // --- Phase 1: Accumulate ---
    local result = this.GatherStats(fee_public, fee_company, cargo_rate_public, cargo_rate_company);

    // --- Phase 2: Settle (divide by TOLL_PRICE_DIVISOR to convert raw units to £) ---
    foreach (company, amount in result.debit_map) {
        GSCompany.ChangeBankBalance(company, -(amount / ::TOLL_PRICE_DIVISOR), GSCompany.EXPENSES_ROADVEH_RUN, GSMap.TILE_INVALID);
    }
    foreach (company, amount in result.credit_map) {
        GSCompany.ChangeBankBalance(company, amount / ::TOLL_PRICE_DIVISOR, GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID);
    }

    // --- Phase 3: Monthly story page refresh ---
    local month = GSDate.GetMonth(today);
    if (month != this.last_month) {
        this.last_month = month;
        if (story_editor != null && companies != null) {
            foreach (company in companies) {
                story_editor.UpdateTollPage(company, this);
            }
        }
    }
}

function HighwayToll::Save()
{
    return {
        stats               = this.stats,
        last_month          = this.last_month,
        last_processed_date = this.last_processed_date,
    };
}

function HighwayToll::Load(data)
{
    if (data.rawin("stats"))               this.stats               = data.stats;
    if (data.rawin("last_month"))          this.last_month          = data.last_month;
    if (data.rawin("last_processed_date")) this.last_processed_date = data.last_processed_date;

    // Migrate old stats format (paid_public/paid_to/received_from) to new base/cargo split
    foreach (cid, cs in this.stats) {
        if (cs.rawin("paid_public") && !cs.rawin("paid_public_base")) {
            cs.paid_public_base  <- cs.paid_public;
            cs.paid_public_cargo <- 0;
            delete cs.paid_public;

            cs.paid_to_base  <- cs.rawin("paid_to") ? cs.paid_to : {};
            cs.paid_to_cargo <- {};
            if (cs.rawin("paid_to")) delete cs.paid_to;

            cs.received_from_base  <- cs.rawin("received_from") ? cs.received_from : {};
            cs.received_from_cargo <- {};
            if (cs.rawin("received_from")) delete cs.received_from;
        }
    }

    Log.Info("HighwayToll: loaded saved stats (" + this.stats.len() + " companies)", Log.LVL_INFO);
}
