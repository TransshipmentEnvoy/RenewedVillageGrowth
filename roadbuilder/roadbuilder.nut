/*
 * This file is part of SuperLib, which is an AI Library for OpenTTD
 * Copyright (C) 2011  Zuu
 *
 * SuperLib is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 of the License
 *
 * SuperLib is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with SuperLib; If not, see <http://www.gnu.org/licenses/> or
 * write to the Free Software Foundation, Inc., 51 Franklin Street,
 * Fifth Floor, Boston, MA 02110-1301 USA.
 *
 */

/*
 * Warning: The RoadBuilder class is a bit talky on the log.
 * While most SuperLib classes are intended as low-level stuff
 * this class is a more complex higher level thing that assumes
 * that the world is interested in what it does.
 *
 * That is something that follows from CluelessPlus and might
 * change in the future, but not now.
 *
 * Also see the log class on how to disable all SuperLib log
 * messages all together if you don't use the SuperLib log system.
 */

class RoadBuilder {

    pf_loops_used = null;
    build_loops_used = null;

    slow_pf = false;
    slow_build = false;
    estimate_multiplier = null;
    loan_limit = null;

    connect_tile1 = null;
    connect_tile2 = null;
    connect_repair = false;
    connect_max_loops = 4000;
    connect_forbidden_tiles = null;

    path = null;
    pf_error = null;

    constructor() {
        this.pf_loops_used = 0;
        this.build_loops_used = 0;
        this.slow_pf = false;
        this.slow_build = false;
        this.estimate_multiplier = 1;
        this.loan_limit = -1; // no limit

        this.connect_tile1 = null;
        this.connect_tile2 = null;
        this.connect_repair = false;
        this.connect_max_loops = 4000;
        this.connect_forbidden_tiles = [];

        this.path = null;
        this.pf_error = RoadPathFinder.PATH_FIND_NO_ERROR;
    }


    // If repair_existing == true, then it should as much as possible avoid building road next to existing to get a tiny bit less penalty

    static CONNECT_SUCCEEDED = 0;            // Connection established from tile1 to tile2
    static CONNECT_FAILED_OTHER = 1;         // Failed for other reason
    static CONNECT_FAILED_TIME_OUT = 2;      // Pathfinder timeout
    static CONNECT_FAILED_NO_PATH_FOUND = 3; // Pathfinder failed to find path
    static CONNECT_FAILED_OUT_OF_TRIES = 4;  // Road building could not complete even after retrying X times

    //
    // 1) Call Init to tell RoadBuilder which tiles to connect, if it should attempt to repair
    // or build a new connection (repair => higher path-finding cost of building new road)
    //
    // 2) Optionally call DoPathfinding(). It will return true/false depending on if a path was
    // found.
    //
    // 3) Call ConnectTiles(). If DoPathfinding was called in step 2) it will use the path found
    // there, otherwise the pathfinder is used to find a path. ConnectTiles will try up to 4
    // times (if there is an obstacle built after path finding) to connect the tiles given by Init
    // with road.

    //
    // The idea is that in some conditions, you might want to do the initial path finding,
    // get the result of it before starting the work of connecting the tiles
    //

    function Init(tile1, tile2, repair_existing = false, max_loops = 4000, forbidden_tiles = []);

    function DoPathfinding();
    // Returns one of the CONNECT_* constants.
    function ConnectTiles(call_count = 1);


    // Call this function after ConnectTiles have returned to see how many loops that were used.
    // The values are accumulated since the instance was created in case ConnectTiles is called
    // multiple times or has to make recursive calls.
    function GetPFLoopsUsed();
    function GetBuildLoopsUsed();

    // Enable slow path finding + road building for ConnectTiles. This is known from the
    // "slow ai" setting in CluelessPlus.
    function EnableSlowAI(enable = true);

    // Enables slow path finding (but leaves road building speed untouched)
    function EnableSlowPathFinding(enable = true);

    // Enables slow building (but leaves path finding speed untouched)
    function EnableSlowBuilding(enable = true);

    // Pass a value that will be used to multiply the result of _Estimate in the path finder.
    // Passing a float value is supported, but the result after multiplying will be casted to
    // an integer. Recommended values: [1.0, 2.0]. Default: 1 (integer)
    // A higher value usually speeds up the pathfinding, at the cost that the pathfinder will
    // not spend as much time on finding solutions that reuse existing infrastructure.
    function SetEstimateMultiplier(estimate_multiplier);

    // loan_limit = maximum loan to take in order to afford construction. The loan is only
    // increased if a build action fails. A value <= 0 means that there is no limit (other
    // than the maximum loan imposed by OpenTTD).
    function SetLoanLimit(loan_limit);
}


function RoadBuilder::Init(tile1, tile2, repair_existing = false, max_loops = 4000, forbidden_tiles = [])
{
    this.pf_loops_used = 0;

    this.connect_tile1 = tile1;
    this.connect_tile2 = tile2;
    this.connect_repair = repair_existing;
    this.connect_max_loops = max_loops;
    this.connect_forbidden_tiles = forbidden_tiles;

    this.path = null;
}

function RoadBuilder::DoPathfinding()
{
    Helper.SetSign(this.connect_tile1, "from");
    Helper.SetSign(this.connect_tile2, "to");

    local try_tiles = [ {from = [this.connect_tile1], to = [this.connect_tile2] },
          { from = [this.connect_tile2], to = [this.connect_tile1] } ];

    /*
     * Run the pathfinder twice. First one time with very few iterations to see if the path is blocked from that
     * direction. If it is blocked, don't do anything more and return failure. Otherwise, restart from the other
     * direction and path-find from there, now with full max_iterations available.
     */
    this.pf_loops_used = 0;
    this.pf_error = RoadPathFinder.PATH_FIND_NO_ERROR;
    local i = 0;
    for(i = 0; i < 2; ++i)
    {
        local pathfinder = RoadPathFinder();

        pathfinder.InitializePath(try_tiles[i].from, try_tiles[i].to, this.connect_repair, this.connect_forbidden_tiles, this.estimate_multiplier);

        pathfinder.SetStepSize(100);
        local max_iterations = this.connect_max_loops - this.pf_loops_used;
        local num_iterations = i == 0? 100 : max_iterations; // On first try, only do a few iterations to see if we run into a dead end.
        pathfinder.SetMaxIterations(num_iterations);
        this.path = null;
        this.pf_error = RoadPathFinder.PATH_FIND_NO_ERROR;
        while (this.path == null && this.pf_error == RoadPathFinder.PATH_FIND_NO_ERROR) {
            this.path = pathfinder.FindPath();
            this.pf_error = pathfinder.GetFindPathError();
            GSController.Sleep(1);

            if(this.slow_pf)
                GSController.Sleep(5);
        }
        this.pf_loops_used += pathfinder.GetIterationsUsed();

        if(path != null) break; // found path?
        if(i == 0 && this.pf_error != RoadPathFinder.PATH_FIND_FAILED_TIME_OUT)
        {
            // Pathfinder stopped at first try for other reason than time out. => fail
            Log.Info("PF stopped at first try for other reason than timeout => fail", Log.LVL_DEBUG);
            this.pf_error = RoadPathFinder.PATH_FIND_FAILED_NO_PATH;
            return false;
        }
    }

    // For ConnectTiles to work properly, we need to swap connect_tile1 and connect_tile2
    // when path was found backwards.
    if (i == 1) {
        local tmp = this.connect_tile1;
        this.connect_tile1 = this.connect_tile2;
        this.connect_tile2 = tmp;
    }

    Log.Info("PF loops used:" + this.pf_loops_used, Log.LVL_DEBUG);

    return this.path != null;
}

function RoadBuilder::ConnectTiles(call_count = 1)
{
    Log.Info("Connecting tiles - try no: " + call_count, Log.LVL_DEBUG);

    if(this.path == null)
    {
        if(!this.DoPathfinding()) {
            if(this.pf_error == RoadPathFinder.PATH_FIND_FAILED_TIME_OUT) {
                Log.Warning("SuperLib: Timed out to find path. Used " + this.pf_loops_used + " of " + this.connect_max_loops + " loops", Log.LVL_INFO);
                return RoadBuilder.CONNECT_FAILED_TIME_OUT;
            } else {
                Log.Warning("SuperLib: Failed to find path", Log.LVL_INFO);
                return RoadBuilder.CONNECT_FAILED_NO_PATH_FOUND;
            }
        }
    }

    Helper.SetSign(this.connect_tile1, "from" + call_count);
    Helper.SetSign(this.connect_tile2, "to" + call_count);

    Log.Info("Path found, now start building!", Log.LVL_SUB_DECISIONS);

    //GSSign.BuildSign(path.GetTile(), "Start building");

    local pppp = this.path;
    Log.Info("Path : " + this.path, Log.LVL_DEBUG);
    while (this.path != null) {
        local par = this.path.GetParent();
        //Helper.SetSign(this.path.GetTile(), "tile");
        if (par != null) {
            local last_node = this.path.GetTile();
            //Helper.SetSign(par.GetTile(), "par");
            if (GSMap.DistanceManhattan(this.path.GetTile(), par.GetTile()) == 1 ) {
                if (GSRoad.AreRoadTilesConnected(this.path.GetTile(), par.GetTile())) {
                    // there is already a road here, don't do anything
                    //Helper.SetSign(par.GetTile(), "conn");

                    if (GSTile.HasTransportType(par.GetTile(), GSTile.TRANSPORT_RAIL))
                    {
                        // Found a rail track crossing the road, try to bridge it
                        Helper.SetSign(par.GetTile(), "rail!");

                        local bridge_result = SuperLib.Road.ConvertRailCrossingToBridge(par.GetTile(), this.path.GetTile());
                        if (bridge_result.succeeded == true)
                        {
                            // TODO update par/path
                            local new_par = par;
                            while (new_par != null && new_par.GetTile() != bridge_result.bridge_start && new_par.GetTile() != bridge_result.bridge_end)
                            {
                                new_par = new_par.GetParent();
                            }

                            if (new_par == null)
                            {
                                Log.Warning("Tried to convert rail crossing to bridge but somehow got lost from the found path.", Log.LVL_INFO);
                            }
                            par = new_par;
                        }
                        else
                        {
                            Log.Info("Failed to bridge railway crossing", Log.LVL_INFO);
                        }
                    }

                } else {

                    /* Look for longest straight road and build it as one build command */
                    local straight_begin = this.path;
                    local straight_end = par;

                    if(!this.slow_build) // build piece by piece in slow-mode
                    {
                        local prev = straight_end.GetParent();
                        while(prev != null &&
                                SuperLib.Tile.IsStraight(straight_begin.GetTile(), prev.GetTile()) &&
                                GSMap.DistanceManhattan(straight_end.GetTile(), prev.GetTile()) == 1)
                        {
                            straight_end = prev;
                            prev = straight_end.GetParent();
                        }

                        /* update the looping vars. (path is set to par in the end of the main loop) */
                        par = straight_end;
                    }

                    //GSSign.BuildSign(this.path.GetTile(), "path");
                    //GSSign.BuildSign(par.GetTile(), "par");

                    // Build road, and if needed increase the loan
                    local result = SuperLib.Money.ExecuteWithLoan(this.loan_limit, function(from, to) {
                        return GSRoad.BuildRoad(from, to);
                    }, straight_begin.GetTile(), straight_end.GetTile());

                    if (!result) {
                        /* An error occured while building a piece of road. TODO: handle it.
                         * Note that is can also be the case that the road was already build. */

                        Helper.SetSign(straight_begin.GetTile(), "fail from");
                        Helper.SetSign(straight_end.GetTile(), "fail to");
                        Log.Warning("Build straight failed", Log.LVL_SUB_DECISIONS);


                        // Try PF again

                        // Update connect tiles to only connect the part that is missing
                        this.connect_tile2 = this.path.GetTile();
                        this.connect_repair = false; // set repair := false as the road might be broken
                        this.connect_max_loops = Helper.Max(this.connect_max_loops, 4000);
                        this.path = null; // re-do the pathfinding using the updated connect_* values.
                        this.pf_error = RoadPathFinder.PATH_FIND_FAILED_NO_PATH;
                        if (call_count > 4 ||
                                this.ConnectTiles(call_count+1) != RoadBuilder.CONNECT_SUCCEEDED)
                        {
                            Log.Warning("After several tries the road construction could still not be completed", Log.LVL_INFO);
                            return RoadBuilder.CONNECT_FAILED_OUT_OF_TRIES;
                        }
                        else
                        {
                            return RoadBuilder.CONNECT_SUCCEEDED;
                        }
                    }

                    if(this.slow_build)
                        GSController.Sleep(10);
                }
            } else {
                if (GSBridge.IsBridgeTile(this.path.GetTile())) {
                    /* A bridge exists */

                    Helper.SetSign(this.path.GetTile(), "bridge exists", false);

                    // Check if it is a bridge with low speed
                    local bridge_type_id = GSBridge.GetBridgeType(this.path.GetTile())
                    local bridge_max_speed = GSBridge.GetMaxSpeed(bridge_type_id);

                    if(bridge_max_speed < 100) // low speed bridge
                    {
                        Helper.SetSign(this.path.GetTile(), "exists slow", false);

                        local other_end_tile = GSBridge.GetOtherBridgeEnd(this.path.GetTile());
                        local bridge_length = GSMap.DistanceManhattan( this.path.GetTile(), other_end_tile ) + 1;
                        local bridge_list = GSBridgeList_Length(bridge_length);

                        bridge_list.Valuate(GSBridge.GetMaxSpeed);
                        bridge_list.KeepAboveValue(bridge_max_speed);

                        if(!bridge_list.IsEmpty())
                        {
                            Helper.SetSign(this.path.GetTile(), "exists upgrade", false);
                            // There is a faster bridge

                            // Pick a random faster bridge than the current one
                            bridge_list.Valuate(GSBase.RandItem);
                            bridge_list.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);

                            Log.Info("Try to upgrade slow existing bridge", Log.LVL_SUB_DECISIONS);

                            // Upgrade the bridge
                            GSBridge.BuildBridge( GSVehicle.VT_ROAD, bridge_list.Begin(), this.path.GetTile(), other_end_tile );

                            Log.Info("Upgrade err: " + GSError.GetLastErrorString() );
                        }
                    }

                } else if(GSTunnel.IsTunnelTile(this.path.GetTile())) {
                    /* A tunnel exists */

                    // All tunnels have equal speed so nothing to do
                } else {
                    /* Build a bridge or tunnel. */

                    /* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
                    if (GSRoad.IsRoadTile(this.path.GetTile()) &&
                            !GSRoad.IsRoadStationTile(this.path.GetTile()) &&
                            !GSRoad.IsRoadDepotTile(this.path.GetTile())) {
                        GSTile.DemolishTile(this.path.GetTile());
                    }
                    if (GSTunnel.GetOtherTunnelEnd(this.path.GetTile()) == par.GetTile()) {

                        local result = SuperLib.Money.ExecuteWithLoan(this.loan_limit, function(p1, p2) {
                            return GSTunnel.BuildTunnel(p1, p2);
                        }, GSVehicle.VT_ROAD, this.path.GetTile());

                        if (!result) {
                            /* An error occured while building a tunnel. TODO: handle it. */
                            Log.Info("Build tunnel error: " + GSError.GetLastErrorString(), Log.LVL_INFO);
                        }
                    } else {
                        local bridge_list = GSBridgeList_Length(GSMap.DistanceManhattan(this.path.GetTile(), par.GetTile()) +1);
                        bridge_list.Valuate(GSBridge.GetMaxSpeed);

                        local result = SuperLib.Money.ExecuteWithLoan(this.loan_limit, function(p1, p2, p3, p4) {
                            return GSBridge.BuildBridge(p1, p2, p3, p4);
                        }, GSVehicle.VT_ROAD, bridge_list.Begin(), this.path.GetTile(), par.GetTile());

                        if (!result) {
                            /* An error occured while building a bridge. TODO: handle it. */
                            Log.Info("Build bridge error: " + GSError.GetLastErrorString(), Log.LVL_INFO);
                        }
                    }

                    if(this.slow_build)
                        GSController.Sleep(50); // Sleep a bit after tunnels
                }
            }
        }
        this.path = par;
        this.build_loops_used += 1;
    }

    Log.Info("Build loops used:" + this.build_loops_used, Log.LVL_DEBUG);
    //GSSign.BuildSign(tile1, "Done");

    // Remove the from/to signs now that the road was successfully built
    Helper.SetSign(this.connect_tile1, "");
    Helper.SetSign(this.connect_tile2, "");

    return RoadBuilder.CONNECT_SUCCEEDED;
}

function RoadBuilder::GetPFLoopsUsed()
{
    return this.pf_loops_used;
}

function RoadBuilder::GetBuildLoopsUsed()
{
    return this.build_loops_used;
}

function RoadBuilder::EnableSlowAI(enable = true)
{
    this.slow_pf = enable;
    this.slow_build = enable;
}

function RoadBuilder::EnableSlowPathFinding(enable = true)
{
    this.slow_pf = enable;
}

function RoadBuilder::EnableSlowBuilding(enable = true)
{
    this.slow_build = enable;
}

function RoadBuilder::SetEstimateMultiplier(estimate_multiplier)
{
    this.estimate_multiplier = estimate_multiplier;
}

function RoadBuilder::SetLoanLimit(loan_limit)
{
    this.loan_limit = loan_limit;
}
