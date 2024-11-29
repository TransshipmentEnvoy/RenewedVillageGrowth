import("util.superlib", "SuperLib", 40);
Log <- SuperLib.Log;

class TechAdvance {
    
    constructor(){
        GSGameSettings.SetValue("vehicle.never_expire_vehicles", 1);
        GSGameSettings.SetValue("vehicle.no_introduce_vehicles_after", 0);

        // load info of all vehicles
    }
};

function TechAdvance::UpdateCompanyList() {

}

function TechAdvance::Manage() {

}
