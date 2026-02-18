/*
 * Road Network Local - Automatic road construction from town centers to local industries
 * Part of Renewed Village Growth Extended
 */

/* ========== Constants ========== */

LOCAL_PATHFIND_STEP_SIZE <- 1000;
LOCAL_PATHFIND_MAX_ITERATIONS <- 200000;
LOCAL_BUILD_SEGMENTS_PER_TICK <- 10;
LOCAL_OPS_SUSPEND_THRESHOLD <- 100;
LOCAL_EDGE_MAX_RETRY_COUNT <- 5;

/* ========== Enums ========== */

enum LocalNetworkState {
    INIT = 0,
    BUILDING = 1,
    MONITORING = 2
}

enum LocalEdgeStatus {
    PENDING = 0,
    BUILT = 1,
    FAILED = 2
}

enum LocalTownTaskStatus {
    PENDING = 0,
    COMPLETE = 1
}

enum LocalEdgeBuildState {
    PENDING = 0,
    PATHFINDING = 1,
    BUILDING = 2,
    COMPLETE = 3,
    FAILED = 4
}

enum LocalPathfindResult {
    CONTINUE = 0,
    FOUND = 1,
    FAILED = 2
}

enum LocalBuildResult {
    CONTINUE = 0,
    COMPLETE = 1,
    FAILED = 2
}

/* ========== RoadNetworkLocal Class ========== */

class RoadNetworkLocal {
    state = null;

    // References
    towns = null;
    shared_network = null;

    // Data
    town_industries = null;
    town_tasks = null;
    edge_key_set = null;

    // Queue progress
    current_task_index = null;
    active_task_index = null;

    // Road type
    current_road_type = null;

    // Settings
    towns_per_month = null;

    // Statistics
    stats = null;
    next_progress_log_at = null;

    // Monthly town quota
    towns_processed_this_month = null;
    last_build_month = null;

    // Async build state
    build_pathfinder = null;
    build_edge = null;
    build_path = null;
    build_path_index = null;
    build_pathfind_iterations = null;

    constructor(towns_array, shared_road_network = null, initial_road_type = null) {
        this.towns = towns_array;
        this.shared_network = shared_road_network;
        this.state = LocalNetworkState.INIT;

        this.town_industries = {};
        this.town_tasks = [];
        this.edge_key_set = {};

        this.current_task_index = 0;
        this.active_task_index = null;

        this.towns_per_month = GSController.GetSetting("local_road_build_rate");

        this.stats = {
            towns_planned = 0,
            towns_completed = 0,
            edges_planned = 0,
            edges_built = 0,
            edges_failed = 0,
            towns_failed = 0
        };
        this.next_progress_log_at = 10;

        this.towns_processed_this_month = 0;
        this.last_build_month = GSDate.GetMonth(GSDate.GetCurrentDate());

        this.build_pathfinder = null;
        this.build_edge = null;
        this.build_path = null;
        this.build_path_index = 0;
        this.build_pathfind_iterations = 0;

        if (initial_road_type != null) {
            this.current_road_type = initial_road_type;
        } else {
            this.current_road_type = this.FindBestRoadType();
        }

        Log.Info("RoadNetworkLocal initialized", Log.LVL_INFO);
    }
}

/* ========== Helpers ========== */

/**
 * Check if an industry is built on water (Oil Rig, Fishing Grounds, etc.)
 * These industries cannot be reached by road.
 * 
 * @param industry_id The industry to check
 * @return true if industry is on water
 */
function RoadNetworkLocal::IsWaterIndustry(industry_id) {
    if (!GSIndustry.IsValidIndustry(industry_id)) return false;
    local industry_type = GSIndustry.GetIndustryType(industry_id);
    return GSIndustryType.IsBuiltOnWater(industry_type);
}

/**
 * Get valid goal tiles for pathfinding to an industry.
 * GSIndustry.GetLocation() returns a tile INSIDE the industry building,
 * which is not buildable. We need tiles ADJACENT to the industry that
 * are either buildable or already have roads.
 * 
 * Uses test mode to verify tiles are actually buildable, making the detection
 * more tolerant of edge cases.
 * 
 * @param industry_id The industry to find goal tiles for
 * @return Array of valid goal tiles, or empty array if none found
 */
function RoadNetworkLocal::GetIndustryGoalTiles(industry_id) {
    if (!GSIndustry.IsValidIndustry(industry_id)) return [];
    
    // Water industries (Oil Rig, Fishing Grounds) cannot be reached by road
    if (this.IsWaterIndustry(industry_id)) return [];
    
    local goal_tiles = [];
    local industry_tile = GSIndustry.GetLocation(industry_id);
    
    // Get all tiles occupied by the industry using a search around the location
    // Industry footprints are typically small (up to ~10x10 for largest)
    local industry_tiles = {};
    local offsets = [
        GSMap.GetTileIndex(0, 1), GSMap.GetTileIndex(0, -1),
        GSMap.GetTileIndex(1, 0), GSMap.GetTileIndex(-1, 0)
    ];
    
    // BFS to find all industry tiles
    local queue = [industry_tile];
    local visited = {};
    visited[industry_tile] <- true;
    // GSSign.BuildSign(industry_tile, "x");
    
    while (queue.len() > 0) {
        local tile = queue.remove(0);
        
        // Check if this tile belongs to the industry
        if (GSIndustry.GetIndustryID(tile) == industry_id) {
            industry_tiles[tile] <- true;
            
            // Add adjacent tiles to queue
            foreach (offset in offsets) {
                local adjacent = tile + offset;
                if (!GSMap.IsValidTile(adjacent)) continue;
                if (visited.rawin(adjacent)) continue;
                visited[adjacent] <- true;
                // GSSign.BuildSign(adjacent, "x");
                queue.append(adjacent);
            }
        }
    }
    
    // If industry_tile itself is not part of the industry footprint
    // (GSIndustry.GetLocation() can return an empty/buildable tile adjacent to the industry),
    // check if it qualifies as a goal tile directly.
    if (!industry_tiles.rawin(industry_tile) && GSMap.IsValidTile(industry_tile)) {
        if (!GSTile.IsWaterTile(industry_tile) &&
            GSTile.GetOwner(industry_tile) == GSCompany.COMPANY_INVALID) {
            if (GSRoad.IsRoadTile(industry_tile)) {
                goal_tiles.append(industry_tile);
                // GSSign.BuildSign(industry_tile, "g");
            } else if (GSTile.IsBuildable(industry_tile)) {
                local test_mode = GSTestMode();
                local can_build = false;
                if (this.current_road_type != null) {
                    GSRoad.SetCurrentRoadType(this.current_road_type);
                }
                foreach (test_offset in offsets) {
                    local test_adjacent = industry_tile + test_offset;
                    if (!GSMap.IsValidTile(test_adjacent)) continue;
                    if (GSRoad.BuildRoad(industry_tile, test_adjacent)) {
                        can_build = true;
                        break;
                    }
                }
                if (can_build) {
                    goal_tiles.append(industry_tile);
                    // GSSign.BuildSign(industry_tile, "g");
                }
            }
        }
    }

    // Now find tiles adjacent to industry that are valid road destinations
    foreach (ind_tile, _ in industry_tiles) {
        foreach (offset in offsets) {
            local adjacent = ind_tile + offset;
            if (!GSMap.IsValidTile(adjacent)) continue;
            
            // Skip if this is also an industry tile
            if (industry_tiles.rawin(adjacent)) continue;
            
            // Skip water tiles
            if (GSTile.IsWaterTile(adjacent)) continue;
            
            // Check if already added
            local already_added = false;
            foreach (existing in goal_tiles) {
                if (existing == adjacent) {
                    already_added = true;
                    break;
                }
            }
            if (already_added) continue;
            
            // Check tile owner - GameScript builds roads owned by town
            // Only accept tiles owned by town (COMPANY_INVALID) or unowned
            local tile_owner = GSTile.GetOwner(adjacent);
            if (tile_owner != GSCompany.COMPANY_INVALID) {
                // Tile is owned by a company, skip it
                continue;
            }
            
            // Accept tiles that already have roads
            if (GSRoad.IsRoadTile(adjacent)) {
                goal_tiles.append(adjacent);
                // GSSign.BuildSign(adjacent, "g");
                continue;
            }
            
            // For buildable tiles, use test mode to verify we can actually build a road there
            // This makes detection more tolerant of edge cases like slopes, ownership, etc.
            if (GSTile.IsBuildable(adjacent)) {
                local test_mode = GSTestMode();
                local can_build = false;
                
                // Set road type for testing
                if (this.current_road_type != null) {
                    GSRoad.SetCurrentRoadType(this.current_road_type);
                }
                
                // Test if we can build roads in different directions at this tile
                // Try building towards each adjacent tile to verify it's accessible
                foreach (test_offset in offsets) {
                    local test_adjacent = adjacent + test_offset;
                    if (!GSMap.IsValidTile(test_adjacent)) continue;
                    
                    // Test building a road piece to verify the tile is accessible
                    if (GSRoad.BuildRoad(adjacent, test_adjacent)) {
                        can_build = true;
                        break;
                    }
                }
                
                if (can_build) {
                    goal_tiles.append(adjacent);
                    // GSSign.BuildSign(adjacent, "g");
                }
            }
        }
    }
    
    return goal_tiles;
}

function RoadNetworkLocal::FindBestRoadType() {
    local best_type = null;
    local best_speed = 0;

    local has_town_buildable_check = "IsTownBuildableRoadType" in GSRoad;

    local road_types = GSRoadTypeList(GSRoad.ROADTRAMTYPES_ROAD);
    foreach (road_type, _ in road_types) {
        if (!GSRoad.IsRoadTypeAvailable(road_type)) continue;

        if (has_town_buildable_check && !GSRoad.IsTownBuildableRoadType(road_type)) {
            continue;
        }

        local speed = GSRoad.GetMaxSpeed(road_type);
        if (speed == 0) speed = 65535;

        if (speed > best_speed) {
            best_speed = speed;
            best_type = road_type;
        }
    }

    if (best_type == null) {
        Log.Warning("RoadNetworkLocal: No suitable road type found", Log.LVL_INFO);
    }

    return best_type;
}

function RoadNetworkLocal::SyncRoadTypeFromShared() {
    if (this.shared_network == null) return;
    if (this.shared_network.current_road_type == null) return;
    this.current_road_type = this.shared_network.current_road_type;
}

function RoadNetworkLocal::GetEdgeKey(town_id, industry_id) {
    return town_id + "|" + industry_id;
}

function RoadNetworkLocal::CreateLocalEdge(town_id, industry_id) {
    if (!GSTown.IsValidTown(town_id)) return null;
    if (!GSIndustry.IsValidIndustry(industry_id)) return null;

    // Skip water industries (Oil Rig, Fishing Grounds) - they need ships, not roads
    if (this.IsWaterIndustry(industry_id)) return null;

    local industry_tile = GSIndustry.GetLocation(industry_id);
    if (GSTile.IsWaterTile(industry_tile)) return null;

    local edge_key = this.GetEdgeKey(town_id, industry_id);
    if (this.edge_key_set.rawin(edge_key)) return null;

    local edge = {
        town_id = town_id,
        industry_id = industry_id,
        from_tile = GSTown.GetLocation(town_id),
        to_tile = industry_tile,
        status = LocalEdgeStatus.PENDING,
        build_state = LocalEdgeBuildState.PENDING,
        retry_count = 0
    };

    this.edge_key_set[edge_key] <- true;
    return edge;
}

function RoadNetworkLocal::CreateTownTask(town_id, industry_ids) {
    local task = {
        town_id = town_id,
        edges = [],
        edge_index = 0,
        status = LocalTownTaskStatus.PENDING
    };

    foreach (industry_id in industry_ids) {
        local edge = this.CreateLocalEdge(town_id, industry_id);
        if (edge != null) {
            task.edges.append(edge);
        }
    }

    return task.edges.len() > 0 ? task : null;
}

function RoadNetworkLocal::HasPendingTasks() {
    for (local i = this.current_task_index; i < this.town_tasks.len(); i++) {
        if (this.town_tasks[i].status == LocalTownTaskStatus.PENDING) return true;
    }
    return false;
}

function RoadNetworkLocal::FindPendingTaskForTown(town_id) {
    foreach (index, task in this.town_tasks) {
        if (task.town_id == town_id && task.status == LocalTownTaskStatus.PENDING) {
            return index;
        }
    }
    return null;
}

function RoadNetworkLocal::GetNextPendingTaskIndex() {
    while (this.current_task_index < this.town_tasks.len()) {
        if (this.town_tasks[this.current_task_index].status == LocalTownTaskStatus.PENDING) {
            return this.current_task_index;
        }
        this.current_task_index++;
    }
    return null;
}

/* ========== Init ========== */

function RoadNetworkLocal::InitLocalEdges() {
    this.town_industries = GetNearbyIndustriesToTowns();
    this.town_tasks = [];
    this.edge_key_set = {};
    this.current_task_index = 0;
    this.active_task_index = null;

    local total_edges = 0;
    foreach (town in this.towns) {
        local town_id = town.id;
        if (!this.town_industries.rawin(town_id)) continue;

        local task = this.CreateTownTask(town_id, this.town_industries[town_id]);
        if (task != null) {
            total_edges += task.edges.len();
            this.town_tasks.append(task);
        }
    }

    this.stats.towns_planned = this.town_tasks.len();
    this.stats.edges_planned = total_edges;
    this.next_progress_log_at = 10;

    Log.Info("RoadNetworkLocal: queued " + this.town_tasks.len() + " towns, " + total_edges + " edges", Log.LVL_INFO);
}

/* ========== Async Pathfinding ========== */

function RoadNetworkLocal::StartBuildPathfinding(edge) {
    if (this.current_road_type != null) {
        GSRoad.SetCurrentRoadType(this.current_road_type);
    }

    // Get valid goal tiles adjacent to the industry (not inside it)
    // GSIndustry.GetLocation() returns a tile INSIDE the industry which is not buildable
    local goal_tiles = this.GetIndustryGoalTiles(edge.industry_id);
    if (goal_tiles.len() == 0) {
        // This can happen for cliff-side industries or industries surrounded by other buildings
        // Water industries are already filtered in CreateLocalEdge
        local town_name = GSTown.GetName(edge.town_id);
        local industry_name = GSIndustry.GetName(edge.industry_id);
        Log.Info("RoadNetworkLocal: No road-accessible tiles - Town: " + town_name + 
            " (ID " + edge.town_id + ")" + 
            " -> Industry: " + industry_name + " (ID " + edge.industry_id + ")", Log.LVL_DEBUG);
        edge.build_state = LocalEdgeBuildState.FAILED;
        return;
    }

    local pf = RoadPathFinder();
    pf.InitializePath([edge.from_tile], goal_tiles, false);
    pf.SetMaxIterations(LOCAL_PATHFIND_MAX_ITERATIONS);
    pf.SetStepSize(LOCAL_PATHFIND_STEP_SIZE);

    this.build_pathfinder = pf;
    this.build_edge = edge;
    this.build_path = null;
    this.build_path_index = 0;
    this.build_pathfind_iterations = 0;

    edge.build_state = LocalEdgeBuildState.PATHFINDING;
    Log.Info("RoadNetworkLocal: Start pathfinding town " + GSTown.GetName(edge.town_id) + "(" + edge.town_id + ") -> industry " + GSIndustry.GetName(edge.industry_id) + "(" + edge.industry_id + ") " +
        "(" + goal_tiles.len() + " goal tiles)", Log.LVL_DEBUG);
}

function RoadNetworkLocal::ContinueBuildPathfinding() {
    if (this.build_pathfinder == null || this.build_edge == null) {
        return LocalPathfindResult.FAILED;
    }

    local path = this.build_pathfinder.FindPath();
    this.build_pathfind_iterations += LOCAL_PATHFIND_STEP_SIZE;

    local error = this.build_pathfinder.GetFindPathError();

    if (path != null) {
        this.build_path = path;
        Log.Info("RoadNetworkLocal: Path found town " + GSTown.GetName(this.build_edge.town_id) + "(" + this.build_edge.town_id + ") -> industry " + GSIndustry.GetName(this.build_edge.industry_id) + "(" + this.build_edge.industry_id + ") " +
            "(" + this.build_pathfind_iterations + " iterations)", Log.LVL_DEBUG);
        return LocalPathfindResult.FOUND;
    }

    if (error == RoadPathFinder.PATH_FIND_FAILED_NO_PATH ||
        error == RoadPathFinder.PATH_FIND_FAILED_TIME_OUT) {
        local next_retry = ("retry_count" in this.build_edge) ? (this.build_edge.retry_count + 1) : 1;
        Log.Info("RoadNetworkLocal: Path failed town " + GSTown.GetName(this.build_edge.town_id) + "(" + this.build_edge.town_id + ") -> industry " + GSIndustry.GetName(this.build_edge.industry_id) + "(" + this.build_edge.industry_id + ") " +
            "(retry " + next_retry + "/" + LOCAL_EDGE_MAX_RETRY_COUNT + ")", Log.LVL_DEBUG);
        return LocalPathfindResult.FAILED;
    }

    return LocalPathfindResult.CONTINUE;
}

function RoadNetworkLocal::BuildRoadSegments() {
    if (this.build_path == null || this.build_edge == null) {
        return LocalBuildResult.FAILED;
    }

    if (this.current_road_type != null) {
        GSRoad.SetCurrentRoadType(this.current_road_type);
    }

    local path = this.build_path;
    if (typeof path != "array") {
        local path_array = [];
        local node = path;
        while (node != null) {
            path_array.append(node.GetTile());
            node = node.GetParent();
        }
        path_array.reverse();
        this.build_path = path_array;
        path = this.build_path;
    }

    local segments_built = 0;
    while (this.build_path_index < path.len() - 1 && segments_built < LOCAL_BUILD_SEGMENTS_PER_TICK) {
        if (GSController.GetOpsTillSuspend() < LOCAL_OPS_SUSPEND_THRESHOLD) {
            return LocalBuildResult.CONTINUE;
        }

        local from_tile = path[this.build_path_index];
        local to_tile = path[this.build_path_index + 1];
        local built = false;

        if (GSBridge.IsBridgeTile(from_tile) || GSTunnel.IsTunnelTile(from_tile)) {
            built = true;
        } else if (GSMap.DistanceManhattan(from_tile, to_tile) > 1) {
            if (GSTunnel.GetOtherTunnelEnd(from_tile) == to_tile) {
                if (GSRoad.IsRoadTile(from_tile)) {
                    GSTile.DemolishTile(from_tile);
                }
                built = GSTunnel.BuildTunnel(GSVehicle.VT_ROAD, from_tile);
            } else {
                local bridge_list = GSBridgeList_Length(GSMap.DistanceManhattan(from_tile, to_tile) + 1);
                if (bridge_list.Count() > 0) {
                    bridge_list.Valuate(GSBridge.GetMaxSpeed);
                    bridge_list.Sort(GSList.SORT_BY_VALUE, false);
                    built = GSBridge.BuildBridge(GSVehicle.VT_ROAD, bridge_list.Begin(), from_tile, to_tile);
                }
            }
        } else {
            built = GSRoad.BuildRoad(from_tile, to_tile);
            if (!built) {
                local error = GSError.GetLastError();
                if (error == GSError.ERR_ALREADY_BUILT || GSRoad.AreRoadTilesConnected(from_tile, to_tile)) {
                    built = true;
                }
            }

            if (built && GSTile.HasTransportType(to_tile, GSTile.TRANSPORT_RAIL)) {
                SuperLib.Road.ConvertRailCrossingToBridge(to_tile, from_tile);
            }
        }

        this.build_path_index++;
        segments_built++;
    }

    if (this.build_path_index >= path.len() - 1) {
        Log.Info("RoadNetworkLocal: Built town " + GSTown.GetName(this.build_edge.town_id) + "(" + this.build_edge.town_id + ") -> industry " + GSIndustry.GetName(this.build_edge.industry_id) + "(" + this.build_edge.industry_id + ") " +
            "(" + path.len() + " tiles)", Log.LVL_DEBUG);
        return LocalBuildResult.COMPLETE;
    }

    return LocalBuildResult.CONTINUE;
}

function RoadNetworkLocal::ResetBuildAsyncState() {
    this.build_pathfinder = null;
    this.build_edge = null;
    this.build_path = null;
    this.build_path_index = 0;
    this.build_pathfind_iterations = 0;
}

function RoadNetworkLocal::ClearTaskQueue() {
    this.ResetBuildAsyncState();
    local kept_tasks = [];
    local kept_edge_keys = {};
    local removed_tasks = 0;
    local exhausted_edges = 0;

    foreach (task in this.town_tasks) {
        local keep_task = false;

        foreach (edge in task.edges) {
            if (!("retry_count" in edge)) edge.retry_count <- 0;

            if (edge.status == LocalEdgeStatus.PENDING ||
                (edge.status == LocalEdgeStatus.FAILED && edge.retry_count < LOCAL_EDGE_MAX_RETRY_COUNT)) {
                keep_task = true;
                break;
            }
        }

        if (!keep_task) {
            removed_tasks++;
        }

        if (keep_task) {
            task.status = LocalTownTaskStatus.PENDING;
            task.edge_index = 0;

            foreach (edge in task.edges) {
                if (!("retry_count" in edge)) edge.retry_count <- 0;

                if (edge.status == LocalEdgeStatus.FAILED) {
                    if (edge.retry_count < LOCAL_EDGE_MAX_RETRY_COUNT) {
                        edge.status = LocalEdgeStatus.PENDING;
                        edge.build_state = LocalEdgeBuildState.PENDING;
                    } else {
                        exhausted_edges++;
                    }
                } else if (edge.status == LocalEdgeStatus.PENDING) {
                    edge.build_state = LocalEdgeBuildState.PENDING;
                }
            }

            kept_tasks.append(task);

            foreach (edge in task.edges) {
                local edge_key = this.GetEdgeKey(edge.town_id, edge.industry_id);
                kept_edge_keys[edge_key] <- true;
            }
        }
    }

    this.town_tasks = kept_tasks;
    this.edge_key_set = kept_edge_keys;
    this.current_task_index = 0;
    this.active_task_index = null;

    Log.Info("RoadNetworkLocal: Queue compacted, kept=" + this.town_tasks.len() +
        ", removed=" + removed_tasks + ", retry_exhausted_edges=" + exhausted_edges, Log.LVL_DEBUG);
}

function RoadNetworkLocal::CompleteActiveTask() {
    if (this.active_task_index == null) return;

    local task = this.town_tasks[this.active_task_index];
    task.status = LocalTownTaskStatus.COMPLETE;

    local built_count = 0;
    foreach (edge in task.edges) {
        if (edge.status == LocalEdgeStatus.BUILT) built_count++;
    }
    if (built_count == 0) this.stats.towns_failed++;

    this.stats.towns_completed++;
    this.towns_processed_this_month++;

    if (this.active_task_index >= this.current_task_index) {
        this.current_task_index = this.active_task_index + 1;
    }

    this.active_task_index = null;
}

function RoadNetworkLocal::BuildBatchAsync() {
    this.towns_per_month = GSController.GetSetting("local_road_build_rate");

    local current_month = GSDate.GetMonth(GSDate.GetCurrentDate());
    if (current_month != this.last_build_month) {
        this.towns_processed_this_month = 0;
        this.last_build_month = current_month;
    }

    if (GSController.GetOpsTillSuspend() < LOCAL_OPS_SUSPEND_THRESHOLD) {
        return true;
    }

    if (this.active_task_index == null && this.build_edge == null) {
        if (this.towns_processed_this_month >= this.towns_per_month) {
            return true;
        }

        local task_index = this.GetNextPendingTaskIndex();
        if (task_index == null) {
            return false;
        }

        this.active_task_index = task_index;
    }

    if (this.active_task_index == null) {
        return true;
    }

    local task = this.town_tasks[this.active_task_index];

    if (task.edge_index >= task.edges.len()) {
        this.CompleteActiveTask();
        return true;
    }

    if (this.build_edge == null) {
        local edge = task.edges[task.edge_index];

        if (edge.status != LocalEdgeStatus.PENDING || edge.build_state != LocalEdgeBuildState.PENDING) {
            task.edge_index++;
            return true;
        }

        if (!GSIndustry.IsValidIndustry(edge.industry_id)) {
            edge.status = LocalEdgeStatus.FAILED;
            edge.build_state = LocalEdgeBuildState.FAILED;
            this.stats.edges_failed++;
            task.edge_index++;
            return true;
        }

        edge.to_tile = GSIndustry.GetLocation(edge.industry_id);
        if (GSTile.IsWaterTile(edge.to_tile)) {
            edge.status = LocalEdgeStatus.FAILED;
            edge.build_state = LocalEdgeBuildState.FAILED;
            this.stats.edges_failed++;
            task.edge_index++;
            return true;
        }

        this.StartBuildPathfinding(edge);
        
        // Check if StartBuildPathfinding failed immediately (no valid goal tiles)
        if (edge.build_state == LocalEdgeBuildState.FAILED) {
            edge.status = LocalEdgeStatus.FAILED;
            this.stats.edges_failed++;
            task.edge_index++;
            return true;
        }
        
        return true;
    }

    local edge = this.build_edge;
    if (edge.build_state == LocalEdgeBuildState.PATHFINDING) {
        local pf_result = this.ContinueBuildPathfinding();

        switch (pf_result) {
            case LocalPathfindResult.CONTINUE:
                return true;
            case LocalPathfindResult.FOUND:
                edge.build_state = LocalEdgeBuildState.BUILDING;
                return true;
            case LocalPathfindResult.FAILED:
                if (!("retry_count" in edge)) edge.retry_count <- 0;
                edge.retry_count++;
                edge.build_state = LocalEdgeBuildState.FAILED;
                edge.status = LocalEdgeStatus.FAILED;
                this.stats.edges_failed++;
                task.edge_index++;
                this.ResetBuildAsyncState();
                return true;
        }
    }

    if (edge.build_state == LocalEdgeBuildState.BUILDING) {
        local build_result = this.BuildRoadSegments();

        switch (build_result) {
            case LocalBuildResult.CONTINUE:
                return true;
            case LocalBuildResult.COMPLETE:
                edge.build_state = LocalEdgeBuildState.COMPLETE;
                edge.status = LocalEdgeStatus.BUILT;
                this.stats.edges_built++;
                task.edge_index++;
                this.ResetBuildAsyncState();
                return true;
            case LocalBuildResult.FAILED:
                if (!("retry_count" in edge)) edge.retry_count <- 0;
                edge.retry_count++;
                edge.build_state = LocalEdgeBuildState.FAILED;
                edge.status = LocalEdgeStatus.FAILED;
                this.stats.edges_failed++;
                task.edge_index++;
                this.ResetBuildAsyncState();
                return true;
        }
    }

    edge.status = LocalEdgeStatus.FAILED;
    if (!("retry_count" in edge)) edge.retry_count <- 0;
    edge.retry_count++;
    edge.build_state = LocalEdgeBuildState.FAILED;
    this.stats.edges_failed++;
    task.edge_index++;
    this.ResetBuildAsyncState();
    return true;
}

/* ========== State Handlers ========== */

function RoadNetworkLocal::DoInit() {
    Log.Info("RoadNetworkLocal: Initializing...", Log.LVL_INFO);
    this.InitLocalEdges();

    if (this.town_tasks.len() > 0) {
        this.state = LocalNetworkState.BUILDING;
    } else {
        this.state = LocalNetworkState.MONITORING;
    }
}

function RoadNetworkLocal::DoBuilding() {
    local still_working = this.BuildBatchAsync();

    local processed_edges = this.stats.edges_built + this.stats.edges_failed;
    if (processed_edges >= this.next_progress_log_at) {
        Log.Info("RoadNetworkLocal: Progress built=" + this.stats.edges_built +
            ", failed=" + this.stats.edges_failed + ", planned=" + this.stats.edges_planned,
            Log.LVL_DEBUG);
        this.next_progress_log_at += 10;
    }

    if (!still_working && this.build_edge == null && this.active_task_index == null) {
        Log.Info("RoadNetworkLocal: Building complete. Built=" + this.stats.edges_built +
            ", Failed=" + this.stats.edges_failed, Log.LVL_INFO);
        this.ClearTaskQueue();
        this.state = LocalNetworkState.MONITORING;
    }
}

function RoadNetworkLocal::DoMonitoring() {
    if (this.HasPendingTasks()) {
        this.state = LocalNetworkState.BUILDING;
    }
}

/* ========== Main Entry ========== */

function RoadNetworkLocal::Manage() {
    this.SyncRoadTypeFromShared();

    switch (this.state) {
        case LocalNetworkState.INIT:
            this.DoInit();
            break;
        case LocalNetworkState.BUILDING:
            this.DoBuilding();
            break;
        case LocalNetworkState.MONITORING:
            this.DoMonitoring();
            break;
    }
}

/* ========== Events ========== */

function RoadNetworkLocal::OnTownFounded(town_id) {
    if (!GSTown.IsValidTown(town_id)) return;
    if (!this.town_industries.rawin(town_id)) {
        this.town_industries[town_id] <- [];
    }
}

function RoadNetworkLocal::OnIndustryOpen(industry_id) {
    if (!GSIndustry.IsValidIndustry(industry_id)) return;

    local industry_tile = GSIndustry.GetLocation(industry_id);
    if (GSTile.IsWaterTile(industry_tile)) return;

    local town_id = GSTile.GetClosestTown(industry_tile);
    if (!GSTown.IsValidTown(town_id)) return;

    if (!this.town_industries.rawin(town_id)) {
        this.town_industries[town_id] <- [];
    }

    local found_industry = false;
    foreach (saved_industry in this.town_industries[town_id]) {
        if (saved_industry == industry_id) {
            found_industry = true;
            break;
        }
    }
    if (!found_industry) {
        this.town_industries[town_id].append(industry_id);
    }

    local edge = this.CreateLocalEdge(town_id, industry_id);
    if (edge == null) return;

    local task_index = this.FindPendingTaskForTown(town_id);
    if (task_index == null) {
        local task = {
            town_id = town_id,
            edges = [edge],
            edge_index = 0,
            status = LocalTownTaskStatus.PENDING
        };
        this.town_tasks.append(task);
        this.stats.towns_planned++;
    } else {
        this.town_tasks[task_index].edges.append(edge);
    }

    this.stats.edges_planned++;

    if (this.state == LocalNetworkState.MONITORING) {
        this.state = LocalNetworkState.BUILDING;
    }
}

/* ========== Save/Load ========== */

function RoadNetworkLocal::Save() {
    local save_data = {
        state = this.state,
        current_task_index = this.current_task_index,
        active_task_index = this.active_task_index,
        current_road_type = this.current_road_type,
        towns_processed_this_month = this.towns_processed_this_month,
        last_build_month = this.last_build_month,
        stats = this.stats,
        town_tasks_data = []
    };

    foreach (task in this.town_tasks) {
        local task_data = {
            town_id = task.town_id,
            edge_index = task.edge_index,
            status = task.status,
            edges = []
        };

        foreach (edge in task.edges) {
            local build_state = edge.build_state;
            local status = edge.status;

            if (build_state == LocalEdgeBuildState.PATHFINDING || build_state == LocalEdgeBuildState.BUILDING) {
                build_state = LocalEdgeBuildState.PENDING;
                status = LocalEdgeStatus.PENDING;
            }

            task_data.edges.append({
                town_id = edge.town_id,
                industry_id = edge.industry_id,
                status = status,
                build_state = build_state,
                retry_count = ("retry_count" in edge) ? edge.retry_count : 0
            });
        }

        save_data.town_tasks_data.append(task_data);
    }

    return save_data;
}

function RoadNetworkLocal::Load(data) {
    if (data == null) return;

    if (data.rawin("state")) this.state = data.state;
    if (data.rawin("current_task_index")) this.current_task_index = data.current_task_index;
    if (data.rawin("active_task_index")) this.active_task_index = data.active_task_index;
    if (data.rawin("current_road_type")) this.current_road_type = data.current_road_type;
    if (data.rawin("towns_processed_this_month")) this.towns_processed_this_month = data.towns_processed_this_month;
    if (data.rawin("last_build_month")) this.last_build_month = data.last_build_month;
    if (data.rawin("stats")) this.stats = data.stats;

    this.town_industries = GetNearbyIndustriesToTowns();
    this.town_tasks = [];
    this.edge_key_set = {};

    if (data.rawin("town_tasks_data")) {
        foreach (task_data in data.town_tasks_data) {
            if (!GSTown.IsValidTown(task_data.town_id)) continue;

            local task = {
                town_id = task_data.town_id,
                edges = [],
                edge_index = task_data.edge_index,
                status = task_data.status
            };

            foreach (edge_data in task_data.edges) {
                if (!GSIndustry.IsValidIndustry(edge_data.industry_id)) continue;

                local edge_key = this.GetEdgeKey(edge_data.town_id, edge_data.industry_id);
                if (this.edge_key_set.rawin(edge_key)) continue;

                local industry_tile = GSIndustry.GetLocation(edge_data.industry_id);
                if (GSTile.IsWaterTile(industry_tile)) continue;

                local edge = {
                    town_id = edge_data.town_id,
                    industry_id = edge_data.industry_id,
                    from_tile = GSTown.GetLocation(edge_data.town_id),
                    to_tile = industry_tile,
                    status = edge_data.status,
                    build_state = edge_data.build_state,
                    retry_count = edge_data.rawin("retry_count") ? edge_data.retry_count : 0
                };

                if (edge.build_state == LocalEdgeBuildState.PATHFINDING || edge.build_state == LocalEdgeBuildState.BUILDING) {
                    edge.build_state = LocalEdgeBuildState.PENDING;
                    edge.status = LocalEdgeStatus.PENDING;
                }

                task.edges.append(edge);
                this.edge_key_set[edge_key] <- true;
            }

            if (task.edges.len() == 0) continue;

            if (task.edge_index < 0) task.edge_index = 0;
            if (task.edge_index > task.edges.len()) task.edge_index = task.edges.len();

            this.town_tasks.append(task);
        }
    }

    if (this.current_task_index < 0) this.current_task_index = 0;
    if (this.current_task_index > this.town_tasks.len()) this.current_task_index = this.town_tasks.len();

    if (this.active_task_index != null) {
        if (this.active_task_index < 0 || this.active_task_index >= this.town_tasks.len()) {
            this.active_task_index = null;
        }
    }

    this.ResetBuildAsyncState();

    if (this.state == LocalNetworkState.MONITORING && this.HasPendingTasks()) {
        this.state = LocalNetworkState.BUILDING;
    }

    Log.Info("RoadNetworkLocal loaded: tasks=" + this.town_tasks.len(), Log.LVL_INFO);
}