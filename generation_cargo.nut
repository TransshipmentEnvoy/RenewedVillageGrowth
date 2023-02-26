import("util.superlib", "SuperLib", 40);
Log <- SuperLib.Log;

class GenerationCargo {
    base_1900 = null;
    ind_base_1900 = null;
    time_rates = null;

    // trace current hour
    current_hour = null;
    current_year = null;

    constructor(){
        this.base_1900 = GSController.GetSetting("town_cargo_generation_base");
        this.ind_base_1900 = GSController.GetSetting("industry_cargo_generation_base");
        this.GetPassengerTimeRates();

        this.current_hour = this.GetHourSafe();
        this.current_year = this.GetYear();
    }
}

function GenerationCargo::GetPassengerTimeRates()
{
    local preset_setting = GSController.GetSetting("passenger_preset");
    switch(preset_setting)
    {
        case 1:
            Log.Info("Extended: Preset: Hyper peak", Log.LVL_INFO);
            this.time_rates = [-1.69, -2.80, -5.32, -5.32, -5.32, -2.42, -0.97, 0.00, 1.70, 0.64, 0.15, 0.00, 0.00, 0.00, 0.00, 0.20, 0.68, 1.14, 1.32, 1.14, 0.38, 0.00, -1.00, -1.30];
            break;
        case 2:
            Log.Info("Extended: Preset: Equal peaks", Log.LVL_INFO);
            this.time_rates = [-1.44, -2.58, -5.39, -5.39, -5.39, -2.59, -1.15, 0.79, 1.52, 0.52, 0.07, -0.07, -0.07, -0.07, -0.07, 0.16, 0.37, 0.97, 1.39, 1.21, 0.49, 0.14, -0.75, -1.05];
            break;
        case 3:
            Log.Info("Extended: Preset: Japan", Log.LVL_INFO);
            this.time_rates = [-0.83, -2.07, -5.63, -5.63, -5.63, -2.32, -0.43, 1.13, 1.86, 0.30, -0.31, -0.31, -0.31, -0.31, -0.31, -0.31, 0.07, 0.61, 1.01, 0.87, 0.64, 0.42, 0.15, -0.17];
            break;
        default:
            Log.Error("Extended: Failed to recognise preset");
    }
}

function GenerationCargo::GetHourSafe()
{
    local tick_scale = GSDate.GetCurrentScaledDateTicks();
    local hour = GSDate.GetHour(tick_scale);
    if (hour >= 24) {
        Log.Warning("Extended: GetHour returned "+current_time+". Hours set to 0");
        hour = 0;
    }
    return hour;
}

function GenerationCargo::GetYear()
{
    local date = GSDate.GetCurrentDate();
    return GSDate.GetYear(date);
}

function GenerationCargo::Manage()
{
    local hour = this.GetHourSafe();
    local year = this.GetYear();

    local diff_hour = hour - this.current_hour;
    if (diff_hour != 0) {
        Log.Info("Extended: Starting Hourly Updates...", Log.LVL_DEBUG);

        local base_rate = (year - 1900 - 4) / 5 + this.base_1900;
        local prod_rate = this.time_rates[hour] * 10 + base_rate;

        if (prod_rate > 80) {
            prod_rate = 80;
        }
        if (prod_rate < -120) {
            prod_rate = -120;
        }
        Log.Info("Extended: Town Cargo Prod Rate: " + prod_rate, Log.LVL_DEBUG);
        GSGameSettings.SetValue("economy.town_cargo_scale_factor", prod_rate.tointeger());

        this.current_hour = hour;
    }

    local diff_year = year - this.current_year;
    if (diff_year != 0) {
        Log.Info("Extended: Starting Yearly Updates...", Log.LVL_DEBUG);

        local ind_rate = (year - 1900 - 4) / 5 + this.ind_base_1900;
        if (ind_rate > 40) {
            ind_rate = 40;
        }
        if (ind_rate < -40) {
            ind_rate = -40;
        }
        Log.Info("Extended: Industry Cargo Prod Rate: " + ind_rate, Log.LVL_DEBUG);
        GSGameSettings.SetValue("economy.industry_cargo_scale_factor", ind_rate.tointeger());

        this.current_year = year;
    }
}