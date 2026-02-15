/*
 * Road Network - Automatic road construction between towns
 * Part of Renewed Village Growth Extended
 *
 * Features:
 * - k-nearest neighbor graph construction
 * - Region-based MST (Minimum Spanning Tree)
 * - Cross-region connections for full connectivity
 * - Incremental road building
 * - Road type upgrades for trunk roads
 */

require("algo/union_find.nut");

/* ========== Constants ========== */

// Region size for map partitioning (in tiles)
REGION_SIZE <- 512;

// k-nearest neighbors for candidate edges
K_NEIGHBORS <- 3;

// Debug visualization
DEBUG_SIGN_INTERVAL <- 20;  // Place sign every N tiles

// Async pathfinding constants
PATHFIND_STEP_SIZE <- 1000;       // Iterations per FindPath() call
PATHFIND_MAX_ITERATIONS <- 200000; // Max total iterations before timeout
BUILD_SEGMENTS_PER_TICK <- 10;   // Road segments to build per tick
OPS_SUSPEND_THRESHOLD <- 100;    // Min ops before yielding to game

/* ========== Enums ========== */

// Network state machine states
enum NetworkState {
    INIT = 0,          // Initial setup: partition towns, build MST
    BUILDING = 1,      // Building roads incrementally
    MONITORING = 2,    // Watching for new road types
    UPGRADING = 3      // Upgrading trunk roads
}

// Edge status
enum EdgeStatus {
    PENDING = 0,       // Not yet attempted
    BUILDING = 1,      // Currently being built
    BUILT = 2,         // Successfully built
    FAILED = 3         // Failed to build (terrain issues)
}

// Edge type (for prioritization)
enum EdgeType {
    INTRA_REGION = 0,  // Within same region (normal)
    INTER_REGION = 1,  // Between regions (trunk road)
    MAJOR_CITY = 2     // Connected to major city (trunk road)
}

// Edge build state (for async building)
enum EdgeBuildState {
    PENDING = 0,       // Waiting to start
    PATHFINDING = 1,   // Pathfinding in progress
    BUILDING = 2,      // Building road segments
    COMPLETE = 3,      // Successfully built
    FAILED = 4         // Failed (no path or build error)
}

// Pathfinding result codes
enum PathfindResult {
    CONTINUE = 0,      // Still searching, yield and continue
    FOUND = 1,         // Path found successfully
    FAILED = 2         // Pathfinding failed (no path or timeout)
}

// Build result codes
enum BuildResult {
    CONTINUE = 0,      // Still building, yield and continue
    COMPLETE = 1,      // Build complete
    FAILED = 2         // Build failed
}

/* ========== RoadNetwork Class ========== */

class RoadNetwork {
    // State
    state = null;
    
    // Town data
    towns = null;                   // Reference to main towns array
    town_id_set = null;             // Set of valid town_ids (town_id -> true)
    
    // Region data
    regions = null;                 // region_id -> array of town indices
    regions_x = null;               // Number of regions in X direction
    regions_y = null;               // Number of regions in Y direction
    
    // Graph data
    edges = null;                   // All candidate edges
    mst_edges = null;               // MST edges to build
    inter_region_edges = null;      // Cross-region edges
    trunk_edges = null;             // Trunk road edges (for upgrade)
    
    // Major cities tracking
    major_cities = null;            // Set of major city town_ids
    last_decade_update = null;      // Decade of last decade update (year / 10)
    
    // Build progress
    build_queue = null;             // Edges waiting to be built
    current_build_edge_index = null;      // Current position in build queue
    
    // Road type tracking
    current_road_type = null;       // Currently used road type
    best_road_type = null;          // Best available road type
    
    // Statistics
    stats = null;                   // Build statistics
    
    // Settings
    build_rate = null;              // Edges to build per month
    upgrade_rate = null;            // Edges to upgrade per month
    debug_signs = null;             // Show debug signs
    
    // Async build pathfinding state
    build_pathfinder = null;        // RoadPathFinder instance (persists across ticks)
    build_edge = null;              // Edge currently being processed
    build_path = null;              // Found path (array of tiles)
    build_path_index = null;        // Current position in path building
    build_pathfind_iterations = null; // Iterations spent on current pathfind
    
    // Monthly rate limiting
    edges_built_this_month = null;  // Edges completed this month
    last_build_month = null;        // Last month we built (for reset)
    
    // Async upgrade state
    current_upgrade_edge_index = null;   // Current position in trunk_edges for upgrade
    edges_upgraded_this_month = null; // Edges upgraded this month
    last_upgrade_month = null;      // Last month we upgraded (for reset)
    
    // Async upgrade pathfinding state (similar to build)
    upgrade_pathfinder = null;      // RoadPathFinder for finding existing road path
    upgrade_edge = null;            // Edge currently being upgraded
    upgrade_path = null;            // Found path (array of tiles)
    upgrade_path_index = null;      // Current position in path upgrading
    upgrade_pathfind_iterations = null; // Iterations spent on current pathfind
    
    // Road type monitoring (yearly check)
    last_road_type_check_year = null; // Last year road type was checked

    constructor(towns_array) {
        this.towns = towns_array;
        this.state = NetworkState.INIT;
        
        // Initialize data structures
        this.town_id_set = {};
        this.regions = {};
        this.edges = [];
        this.mst_edges = [];
        this.inter_region_edges = [];
        this.trunk_edges = [];
        this.build_queue = [];
        this.current_build_edge_index = 0;
        this.major_cities = {};
        this.last_decade_update = GSDate.GetYear(GSDate.GetCurrentDate()) / 10;
        
        // Initialize statistics
        this.stats = {
            edges_planned = 0,
            edges_built = 0,
            edges_failed = 0,
            edges_upgraded = 0
        };
        
        // Read settings
        this.build_rate = GSController.GetSetting("road_build_rate");
        this.upgrade_rate = GSController.GetSetting("road_upgrade_rate");
        this.debug_signs = GSController.GetSetting("debug_road_signs");
        
        // Initialize async build pathfinding state
        this.build_pathfinder = null;
        this.build_edge = null;
        this.build_path = null;
        this.build_path_index = 0;
        this.build_pathfind_iterations = 0;
        
        // Initialize monthly rate limiting
        this.edges_built_this_month = 0;
        this.last_build_month = GSDate.GetMonth(GSDate.GetCurrentDate());
        
        // Initialize async upgrade state
        this.current_upgrade_edge_index = 0;
        this.edges_upgraded_this_month = 0;
        this.last_upgrade_month = GSDate.GetMonth(GSDate.GetCurrentDate());
        
        // Initialize async upgrade pathfinding state
        this.upgrade_pathfinder = null;
        this.upgrade_edge = null;
        this.upgrade_path = null;
        this.upgrade_path_index = 0;
        this.upgrade_pathfind_iterations = 0;
        
        // Initialize road type monitoring (yearly check)
        this.last_road_type_check_year = GSDate.GetYear(GSDate.GetCurrentDate());
        
        // Calculate region grid size
        this.regions_x = (GSMap.GetMapSizeX() + REGION_SIZE - 1) / REGION_SIZE;
        this.regions_y = (GSMap.GetMapSizeY() + REGION_SIZE - 1) / REGION_SIZE;
        
        // Find best available road type
        this.current_road_type = this.FindBestRoadType();
        this.best_road_type = this.current_road_type;
        
        Log.Info("RoadNetwork initialized: " + this.regions_x + "x" + this.regions_y + " regions", Log.LVL_INFO);
    }
}

/* ========== Region Management ========== */

/* Get region ID for a tile */
function RoadNetwork::GetRegionId(tile) {
    local x = GSMap.GetTileX(tile) / REGION_SIZE;
    local y = GSMap.GetTileY(tile) / REGION_SIZE;
    return y * this.regions_x + x;
}

/* Get adjacent region IDs (only IDs greater than current, to avoid duplicates) */
function RoadNetwork::GetAdjacentRegions(region_id) {
    local adjacent = [];
    local rx = region_id % this.regions_x;
    local ry = region_id / this.regions_x;
    
    // Check all 8 directions
    for (local dy = -1; dy <= 1; dy++) {
        for (local dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;  // Skip self
            
            local nx = rx + dx;
            local ny = ry + dy;
            
            if (nx >= 0 && nx < this.regions_x && ny >= 0 && ny < this.regions_y) {
                local neighbor_id = ny * this.regions_x + nx;
                // Only add greater IDs to avoid duplicate edges
                if (neighbor_id > region_id) {
                    adjacent.append(neighbor_id);
                }
            }
        }
    }
    
    return adjacent;
}

/* Build town ID set (set of valid town_ids) */
function RoadNetwork::BuildTownIdSet() {
    this.town_id_set = {};
    
    foreach (town in this.towns) {
        this.town_id_set[town.id] <- true;
    }
    
    local count = 0;
    foreach (_, _ in this.town_id_set) count++;
    Log.Info("Built town ID set: " + count + " towns", Log.LVL_DEBUG);
}

/* Partition towns into regions */
function RoadNetwork::PartitionTownsIntoRegions() {
    this.regions = {};
    
    foreach (town in this.towns) {
        local town_tile = GSTown.GetLocation(town.id);
        local region_id = this.GetRegionId(town_tile);
        
        // Initialize region array if needed
        if (!this.regions.rawin(region_id)) {
            this.regions[region_id] <- [];
        }
        
        // Add town_id to region
        this.regions[region_id].append(town.id);
    }
    
    // Log region statistics
    local total_regions = 0;
    local max_towns_in_region = 0;
    foreach (region_id, town_indices in this.regions) {
        total_regions++;
        if (town_indices.len() > max_towns_in_region) {
            max_towns_in_region = town_indices.len();
        }
    }
    
    Log.Info("Partitioned into " + total_regions + " regions (max " + max_towns_in_region + " towns/region)", Log.LVL_INFO);
}

/* Get town tile location by town_id */
function RoadNetwork::GetTownTile(town_id) {
    return GSTown.GetLocation(town_id);
}

/* Get town population by town_id */
function RoadNetwork::GetTownPopulation(town_id) {
    return GSTown.GetPopulation(town_id);
}

/* Calculate Manhattan distance between two towns (by town_id) */
function RoadNetwork::TownDistance(town_id_a, town_id_b) {
    local tile_a = this.GetTownTile(town_id_a);
    local tile_b = this.GetTownTile(town_id_b);
    return GSMap.DistanceManhattan(tile_a, tile_b);
}

/* ========== Async Pathfinding ========== */

/* Start pathfinding for build */
function RoadNetwork::StartBuildPathfinding(edge) {
    // Set road type
    GSRoad.SetCurrentRoadType(this.current_road_type);
    
    // Create pathfinder instance
    local pf = SuperLib.RoadPathFinder();
    
    // Initialize path search
    pf.InitializePath([edge.from_tile], [edge.to_tile], false);
    pf.SetMaxIterations(PATHFIND_MAX_ITERATIONS);
    pf.SetStepSize(PATHFIND_STEP_SIZE);
    
    // Store state for continuation
    this.build_pathfinder = pf;
    this.build_edge = edge;
    this.build_path = null;
    this.build_path_index = 0;
    this.build_pathfind_iterations = 0;
    
    // Update edge state
    edge.build_state = EdgeBuildState.PATHFINDING;
    
    Log.Info("Started build pathfinding: " + edge.town_a + " -> " + edge.town_b, Log.LVL_DEBUG);
}

/* Continue build pathfinding - returns PathfindResult */
function RoadNetwork::ContinueBuildPathfinding() {
    if (this.build_pathfinder == null || this.build_edge == null) {
        return PathfindResult.FAILED;
    }
    
    // Execute one step of pathfinding (PATHFIND_STEP_SIZE iterations)
    local path = this.build_pathfinder.FindPath();
    this.build_pathfind_iterations += PATHFIND_STEP_SIZE;
    
    // Check result
    local error = this.build_pathfinder.GetFindPathError();
    
    if (path != null) {
        // Path found!
        this.build_path = path;
        Log.Info("Build path found: " + this.build_edge.town_a + " -> " + this.build_edge.town_b + 
                 " (" + this.build_pathfind_iterations + " iterations)", Log.LVL_DEBUG);
        return PathfindResult.FOUND;
    }
    
    // Check for errors
    if (error == SuperLib.RoadPathFinder.PATH_FIND_FAILED_NO_PATH) {
        Log.Info("No build path: " + this.build_edge.town_a + " -> " + this.build_edge.town_b, Log.LVL_DEBUG);
        return PathfindResult.FAILED;
    }
    
    if (error == SuperLib.RoadPathFinder.PATH_FIND_FAILED_TIME_OUT) {
        Log.Info("Build pathfind timeout: " + this.build_edge.town_a + " -> " + this.build_edge.town_b + 
                 " (" + this.build_pathfind_iterations + " iterations)", Log.LVL_DEBUG);
        return PathfindResult.FAILED;
    }
    
    // Still searching (PATH_FIND_NO_ERROR with null path means continue)
    return PathfindResult.CONTINUE;
}

/* Build road segments incrementally - returns BuildResult */
function RoadNetwork::BuildRoadSegments() {
    if (this.build_path == null || this.build_edge == null) {
        return BuildResult.FAILED;
    }
    
    // Set road type
    GSRoad.SetCurrentRoadType(this.current_road_type);
    
    local segments_built = 0;
    local path = this.build_path;
    
    // SuperLib path is a linked list: path.GetTile(), path.GetParent()
    // We need to traverse and build segments
    
    // First, convert path to array if not done yet (only on first call)
    if (typeof path != "array") {
        local path_array = [];
        local node = path;
        while (node != null) {
            path_array.append(node.GetTile());
            node = node.GetParent();
        }
        // Reverse so it goes from start to end
        path_array.reverse();
        this.build_path = path_array;
        path = this.build_path;
    }
    
    // Build segments from current position
    while (this.build_path_index < path.len() - 1 && segments_built < BUILD_SEGMENTS_PER_TICK) {
        local from_tile = path[this.build_path_index];
        local to_tile = path[this.build_path_index + 1];
        
        // Check ops budget
        if (GSController.GetOpsTillSuspend() < OPS_SUSPEND_THRESHOLD) {
            return BuildResult.CONTINUE;  // Yield and continue later
        }
        
        // Build road segment (handle both road and bridge/tunnel)
        local built = false;
        
        // Check if it's a bridge or tunnel
        if (GSBridge.IsBridgeTile(from_tile) || GSTunnel.IsTunnelTile(from_tile)) {
            // Skip - already built as part of pathfinder's plan
            built = true;
        } else if (GSMap.DistanceManhattan(from_tile, to_tile) > 1) {
            // Non-adjacent tiles - likely a bridge or tunnel needed
            // Check if this should be a tunnel (tunnel endpoint matches to_tile)
            if (GSTunnel.GetOtherTunnelEnd(from_tile) == to_tile) {
                // Demolish existing road if present (required for tunnel construction)
                if (GSRoad.IsRoadTile(from_tile)) {
                    GSTile.DemolishTile(from_tile);
                }
                // Build tunnel - the landscape allows it
                built = GSTunnel.BuildTunnel(GSVehicle.VT_ROAD, from_tile);
                if (!built) {
                    Log.Info("Tunnel build failed: " + GSError.GetLastErrorString(), Log.LVL_DEBUG);
                }
            } else {
                // Try to build bridge
                local bridge_list = GSBridgeList_Length(GSMap.DistanceManhattan(from_tile, to_tile) + 1);
                if (bridge_list.Count() > 0) {
                    bridge_list.Valuate(GSBridge.GetMaxSpeed);
                    bridge_list.Sort(GSList.SORT_BY_VALUE, false);
                    built = GSBridge.BuildBridge(GSVehicle.VT_ROAD, bridge_list.Begin(), from_tile, to_tile);
                }
                if (!built) {
                    Log.Info("Bridge build failed: " + GSError.GetLastErrorString(), Log.LVL_DEBUG);
                }
            }
        } else {
            // Normal road segment
            built = GSRoad.BuildRoad(from_tile, to_tile);
            if (!built) {
                // Maybe road already exists, check error
                local error = GSError.GetLastError();
                if (error == GSError.ERR_ALREADY_BUILT || GSRoad.AreRoadTilesConnected(from_tile, to_tile)) {
                    built = true;  // Already connected, that's fine
                }
            }
            
            // Check if we just built/connected road over a railway - convert to bridge
            if (built && GSTile.HasTransportType(to_tile, GSTile.TRANSPORT_RAIL)) {
                local bridge_result = SuperLib.Road.ConvertRailCrossingToBridge(to_tile, from_tile);
                if (bridge_result.succeeded) {
                    Log.Info("Converted rail crossing to bridge at tile " + to_tile, Log.LVL_DEBUG);
                }
            }
        }
        
        this.build_path_index++;
        segments_built++;
        
        // Continue even if single segment fails (terrain might already have road)
    }
    
    // Check if done
    if (this.build_path_index >= path.len() - 1) {
        Log.Info("Road built: " + this.build_edge.town_a + " -> " + this.build_edge.town_b + 
                 " (" + path.len() + " tiles)", Log.LVL_DEBUG);
        return BuildResult.COMPLETE;
    }
    
    return BuildResult.CONTINUE;
}

/* Reset async build pathfinding state */
function RoadNetwork::ResetBuildAsyncState() {
    this.build_pathfinder = null;
    this.build_edge = null;
    this.build_path = null;
    this.build_path_index = 0;
    this.build_pathfind_iterations = 0;
}

/* Get next pending edge from build queue */
function RoadNetwork::GetNextPendingBuildEdge() {
    while (this.current_build_edge_index < this.build_queue.len()) {
        local edge = this.build_queue[this.current_build_edge_index];
        
        // Initialize build_state if not present (backward compatibility)
        if (!("build_state" in edge)) {
            edge.build_state <- EdgeBuildState.PENDING;
        }
        
        // Check if this edge needs processing
        if (edge.build_state == EdgeBuildState.PENDING && edge.status == EdgeStatus.PENDING) {
            return edge;
        }
        
        this.current_build_edge_index++;
    }
    return null;  // All edges processed
}

/* Async build - process one unit of work then yield
 * Returns: true if still working, false if all done or blocked
 */
function RoadNetwork::BuildBatchAsync() {
    // Refresh debug_signs setting to allow runtime toggle
    this.debug_signs = GSController.GetSetting("debug_road_signs");
    
    // Check monthly rate limit
    local current_month = GSDate.GetMonth(GSDate.GetCurrentDate());
    if (current_month != this.last_build_month) {
        // New month - reset counter
        this.edges_built_this_month = 0;
        this.last_build_month = current_month;
    }
    
    // If reached monthly limit, pause (but keep current edge in progress)
    if (this.build_edge == null && this.edges_built_this_month >= this.build_rate) {
        return true;  // Still have work, but waiting for next month
    }
    
    // Check ops budget before starting
    if (GSController.GetOpsTillSuspend() < OPS_SUSPEND_THRESHOLD) {
        return true;  // Still working, but yield now
    }
    
    // If no current edge, get the next one
    if (this.build_edge == null) {
        local edge = this.GetNextPendingBuildEdge();
        if (edge == null) {
            return false;  // All edges processed
        }
        this.StartBuildPathfinding(edge);
        return true;  // Started new edge, yield to let game process
    }
    
    // Process current edge based on its state
    local edge = this.build_edge;
    
    switch (edge.build_state) {
        case EdgeBuildState.PATHFINDING: {
            local result = this.ContinueBuildPathfinding();
            
            switch (result) {
                case PathfindResult.CONTINUE:
                    // Still pathfinding, will continue next tick
                    return true;
                    
                case PathfindResult.FOUND:
                    // Move to building phase
                    edge.build_state = EdgeBuildState.BUILDING;
                    return true;
                    
                case PathfindResult.FAILED:
                    // Mark edge as failed
                    edge.build_state = EdgeBuildState.FAILED;
                    edge.status = EdgeStatus.FAILED;
                    this.stats.edges_failed++;
                    if (this.debug_signs) {
                        this.DebugMarkEdge(edge);
                    }
                    // Move to next edge
                    this.current_build_edge_index++;
                    this.ResetBuildAsyncState();
                    return true;
            }
            break;
        }
        
        case EdgeBuildState.BUILDING: {
            local result = this.BuildRoadSegments();
            
            switch (result) {
                case BuildResult.CONTINUE:
                    // Still building, will continue next tick
                    return true;
                    
                case BuildResult.COMPLETE:
                    // Mark edge as complete
                    edge.build_state = EdgeBuildState.COMPLETE;
                    edge.status = EdgeStatus.BUILT;
                    this.stats.edges_built++;
                    this.edges_built_this_month++;  // Count for monthly rate limit
                    if (this.debug_signs) {
                        this.DebugMarkEdge(edge);
                    }
                    // Move to next edge
                    this.current_build_edge_index++;
                    this.ResetBuildAsyncState();
                    return true;
                    
                case BuildResult.FAILED:
                    // Mark edge as failed
                    edge.build_state = EdgeBuildState.FAILED;
                    edge.status = EdgeStatus.FAILED;
                    this.stats.edges_failed++;
                    if (this.debug_signs) {
                        this.DebugMarkEdge(edge);
                    }
                    // Move to next edge
                    this.current_build_edge_index++;
                    this.ResetBuildAsyncState();
                    return true;
            }
            break;
        }
        
        default:
            // Unexpected state, reset
            Log.Warning("Unexpected edge build state: " + edge.build_state);
            this.current_build_edge_index++;
            this.ResetBuildAsyncState();
            return true;
    }
    
    return true;
}

/* Debug visualization - mark edge with signs */
function RoadNetwork::DebugMarkEdge(edge) {
    local from = edge.from_tile;
    local to = edge.to_tile;
    local dist = GSMap.DistanceManhattan(from, to);
    
    if (dist == 0) return;
    
    local dx = GSMap.GetTileX(to) - GSMap.GetTileX(from);
    local dy = GSMap.GetTileY(to) - GSMap.GetTileY(from);
    
    // Place sign every DEBUG_SIGN_INTERVAL tiles
    for (local i = 0; i <= dist; i += DEBUG_SIGN_INTERVAL) {
        local ratio = i.tofloat() / dist;
        local x = GSMap.GetTileX(from) + (dx * ratio).tointeger();
        local y = GSMap.GetTileY(from) + (dy * ratio).tointeger();
        local tile = GSMap.GetTileIndex(x, y);
        
        local label = "R:" + i;
        if (edge.type == EdgeType.INTER_REGION) label = "T:" + i;
        else if (edge.type == EdgeType.MAJOR_CITY) label = "M:" + i;
        
        GSSign.BuildSign(tile, label);
    }
}

/* ========== Graph Construction ========== */

/* Create an edge object */
function RoadNetwork::CreateEdge(town_a, town_b, edge_type) {
    return {
        town_a = town_a,
        town_b = town_b,
        from_tile = this.GetTownTile(town_a),
        to_tile = this.GetTownTile(town_b),
        distance = this.TownDistance(town_a, town_b),
        type = edge_type,
        status = EdgeStatus.PENDING
    };
}

/* Build k-nearest neighbor candidate edges for a region */
function RoadNetwork::BuildKNNEdgesForRegion(region_id) {
    if (!this.regions.rawin(region_id)) return [];
    
    local town_ids = this.regions[region_id];
    local n = town_ids.len();
    if (n < 2) return [];
    
    local edges = [];
    local edge_set = {};  // Key: "min_max" to avoid duplicates
    
    foreach (i, town_a in town_ids) {
        // Calculate distances to all other towns in region
        local distances = [];
        foreach (j, town_b in town_ids) {
            if (i == j) continue;
            distances.append({
                town = town_b,
                dist = this.TownDistance(town_a, town_b)
            });
        }
        
        // Sort by distance
        distances.sort(function(a, b) { return a.dist - b.dist; });
        
        // Take k nearest
        local k = (K_NEIGHBORS < distances.len()) ? K_NEIGHBORS : distances.len();
        for (local idx = 0; idx < k; idx++) {
            local town_b = distances[idx].town;
            
            // Create unique edge key (smaller id first)
            local min_id = (town_a < town_b) ? town_a : town_b;
            local max_id = (town_a < town_b) ? town_b : town_a;
            local key = min_id + "_" + max_id;
            
            // Add edge if not already added
            if (!edge_set.rawin(key)) {
                edge_set[key] <- true;
                edges.append(this.CreateEdge(min_id, max_id, EdgeType.INTRA_REGION));
            }
        }
    }
    
    return edges;
}

/* Build MST using Kruskal's algorithm for a set of edges */
function RoadNetwork::BuildMSTFromEdges(edges, town_ids) {
    if (edges.len() == 0) return [];
    
    // Build a local mapping from town_id to sequential index for Union-Find
    local id_to_idx = {};
    local idx = 0;
    foreach (town_id in town_ids) {
        if (!id_to_idx.rawin(town_id)) {
            id_to_idx[town_id] <- idx;
            idx++;
        }
    }
    
    // Sort edges by distance
    edges.sort(function(a, b) { return a.distance - b.distance; });
    
    // Create union-find for MST using sequential indices
    local uf = UnionFind(idx);
    local mst = [];
    
    foreach (edge in edges) {
        // Map town_ids to local indices
        if (!id_to_idx.rawin(edge.town_a) || !id_to_idx.rawin(edge.town_b)) continue;
        local idx_a = id_to_idx[edge.town_a];
        local idx_b = id_to_idx[edge.town_b];
        
        if (uf.Union(idx_a, idx_b)) {
            mst.append(edge);
        }
    }
    
    return mst;
}

/* Build MST for a single region */
function RoadNetwork::BuildRegionMST(region_id) {
    // Get KNN edges for this region
    local edges = this.BuildKNNEdgesForRegion(region_id);
    if (edges.len() == 0) return [];
    
    // Get town_ids in this region for Union-Find mapping
    local town_ids = this.regions[region_id];
    return this.BuildMSTFromEdges(edges, town_ids);
}

/* Find inter-region connections */
function RoadNetwork::FindInterRegionConnections() {
    local inter_edges = [];
    
    foreach (region_a, towns_a in this.regions) {
        local adjacent = this.GetAdjacentRegions(region_a);
        
        foreach (region_b in adjacent) {
            if (!this.regions.rawin(region_b)) continue;
            
            local towns_b = this.regions[region_b];
            
            // Find closest town pair between regions
            local min_dist = 999999;
            local best_a = null;
            local best_b = null;
            
            foreach (town_a in towns_a) {
                foreach (town_b in towns_b) {
                    local dist = this.TownDistance(town_a, town_b);
                    if (dist < min_dist) {
                        min_dist = dist;
                        best_a = town_a;
                        best_b = town_b;
                    }
                }
            }
            
            if (best_a != null && best_b != null) {
                inter_edges.append(this.CreateEdge(best_a, best_b, EdgeType.INTER_REGION));
            }
        }
    }
    
    Log.Info("Found " + inter_edges.len() + " inter-region connections", Log.LVL_INFO);
    return inter_edges;
}

/* Identify major city edges (top 10% by population) */
function RoadNetwork::IdentifyMajorCityEdges() {
    // Get town populations
    local town_pops = [];
    foreach (town in this.towns) {
        town_pops.append({
            town_id = town.id,
            population = this.GetTownPopulation(town.id)
        });
    }
    
    // Sort by population descending
    town_pops.sort(function(a, b) { return b.population - a.population; });
    
    // Mark top 10% as major cities
    local major_count = (town_pops.len() + 9) / 10;  // Ceiling division
    local major_set = {};
    
    for (local i = 0; i < major_count && i < town_pops.len(); i++) {
        major_set[town_pops[i].town_id] <- true;
    }
    
    // Store major cities set for later reference
    this.major_cities = major_set;
    
    // Mark edges connected to major cities
    foreach (edge in this.mst_edges) {
        if (major_set.rawin(edge.town_a) || major_set.rawin(edge.town_b)) {
            if (edge.type == EdgeType.INTRA_REGION) {
                edge.type = EdgeType.MAJOR_CITY;
            }
        }
    }
    
    Log.Info("Identified " + major_count + " major cities", Log.LVL_DEBUG);
}

/* ========== Road Type Management ========== */

/* Find the best available road type that is town buildable */
function RoadNetwork::FindBestRoadType() {
    local best_type = null;
    local best_speed = 0;
    
    // Check if JGRPP's IsTownBuildableRoadType is available
    local has_town_buildable_check = "IsTownBuildableRoadType" in GSRoad;
    
    local road_types = GSRoadTypeList(GSRoad.ROADTRAMTYPES_ROAD);
    foreach (road_type, _ in road_types) {
        if (!GSRoad.IsRoadTypeAvailable(road_type)) continue;
        
        // If JGRPP, only use town-buildable road types (so towns can expand on them)
        if (has_town_buildable_check) {
            if (!GSRoad.IsTownBuildableRoadType(road_type)) continue;
        }
        
        local speed = GSRoad.GetMaxSpeed(road_type);
        if (speed == 0) speed = 65535;  // Unlimited speed
        
        if (speed > best_speed) {
            best_speed = speed;
            best_type = road_type;
        }
    }
    
    if (best_type != null) {
        Log.Info("Best road type: " + GSRoad.GetName(best_type) + " (speed: " + best_speed + ", town_buildable: " + has_town_buildable_check + ")", Log.LVL_DEBUG);
    } else {
        Log.Warning("No suitable road type found!", Log.LVL_INFO);
    }
    
    return best_type;
}

/* ========== Save/Load ========== */

function RoadNetwork::Save() {
    local save_data = {
        state = this.state,
        current_build_edge_index = this.current_build_edge_index,
        stats = this.stats,
        current_road_type = this.current_road_type,
        last_decade_update = this.last_decade_update,
        edges_built_this_month = this.edges_built_this_month,
        last_build_month = this.last_build_month,
        // Upgrade state
        current_upgrade_edge_index = this.current_upgrade_edge_index,
        edges_upgraded_this_month = this.edges_upgraded_this_month,
        last_upgrade_month = this.last_upgrade_month,
        // Road type monitoring
        last_road_type_check_year = this.last_road_type_check_year
    };
    
    // Save major cities as array (tables can't be saved directly)
    save_data.major_cities_list <- [];
    foreach (town_id, _ in this.major_cities) {
        save_data.major_cities_list.append(town_id);
    }
    
    // Save edge statuses and build states
    save_data.edge_statuses <- [];
    save_data.edge_build_states <- [];
    foreach (edge in this.build_queue) {
        save_data.edge_statuses.append(edge.status);
        // Save build_state if exists, otherwise default to PENDING
        if ("build_state" in edge) {
            save_data.edge_build_states.append(edge.build_state);
        } else {
            save_data.edge_build_states.append(EdgeBuildState.PENDING);
        }
    }
    
    // Note: current_pathfinder, current_path cannot be serialized
    // They will be reset on load
    
    return save_data;
}

function RoadNetwork::Load(data) {
    if (data == null) return;
    
    if (data.rawin("state")) this.state = data.state;
    if (data.rawin("current_build_edge_index")) this.current_build_edge_index = data.current_build_edge_index;
    if (data.rawin("stats")) this.stats = data.stats;
    if (data.rawin("current_road_type")) this.current_road_type = data.current_road_type;
    if (data.rawin("last_decade_update")) this.last_decade_update = data.last_decade_update;
    // Legacy compatibility: convert yearly to decade
    else if (data.rawin("last_yearly_update")) this.last_decade_update = data.last_yearly_update / 10;
    
    // Restore monthly rate limiting
    if (data.rawin("edges_built_this_month")) this.edges_built_this_month = data.edges_built_this_month;
    if (data.rawin("last_build_month")) this.last_build_month = data.last_build_month;
    
    // Restore upgrade state
    if (data.rawin("current_upgrade_edge_index")) this.current_upgrade_edge_index = data.current_upgrade_edge_index;
    if (data.rawin("edges_upgraded_this_month")) this.edges_upgraded_this_month = data.edges_upgraded_this_month;
    if (data.rawin("last_upgrade_month")) this.last_upgrade_month = data.last_upgrade_month;
    
    // Restore road type monitoring
    if (data.rawin("last_road_type_check_year")) this.last_road_type_check_year = data.last_road_type_check_year;
    
    // Restore major cities from array
    if (data.rawin("major_cities_list")) {
        this.major_cities = {};
        foreach (town_id in data.major_cities_list) {
            this.major_cities[town_id] <- true;
        }
    }
    
    // Reset async build pathfinding state (cannot be restored from save)
    this.ResetBuildAsyncState();
    
    // Reset async upgrade pathfinding state (cannot be restored from save)
    this.ResetUpgradeAsyncState();
    
    // Note: edge_build_states will be restored after build_queue is rebuilt in DoInit
    // Any in-progress pathfinding will restart from scratch
    
    Log.Info("RoadNetwork loaded: state=" + this.state, Log.LVL_INFO);
}

/* ========== Main Entry Point ========== */

/* Called every tick from main loop */
function RoadNetwork::Manage() {
    switch (this.state) {
        case NetworkState.INIT:
            this.DoInit();
            break;
        case NetworkState.BUILDING:
            this.DoBuilding();
            break;
        case NetworkState.MONITORING:
            this.DoMonitoring();
            break;
        case NetworkState.UPGRADING:
            this.DoUpgrading();
            break;
    }
}

/* Called when a new town is founded */
function RoadNetwork::OnTownFounded(town_id, town_index) {
    // Skip if still initializing
    if (this.state == NetworkState.INIT) return;
    
    // Note: town_index parameter kept for interface compatibility but not used
    // We use town_id directly for robustness against town deletion
    
    Log.Info("RoadNetwork: New town founded (id=" + town_id + "), connecting to network", Log.LVL_INFO);
    
    // Add to town ID set
    this.town_id_set[town_id] <- true;
    
    // Get town location and region
    local town_tile = GSTown.GetLocation(town_id);
    local region_id = this.GetRegionId(town_tile);
    
    // Add to region (store town_id, not index)
    if (!this.regions.rawin(region_id)) {
        this.regions[region_id] <- [];
    }
    this.regions[region_id].append(town_id);
    
    // Find k nearest towns to connect to
    local new_edges = this.FindNearestTownEdges(town_id, K_NEIGHBORS);
    
    if (new_edges.len() > 0) {
        // Add new edges to build queue
        foreach (edge in new_edges) {
            this.build_queue.append(edge);
            this.mst_edges.append(edge);
        }
        
        this.stats.edges_planned += new_edges.len();
        Log.Info("RoadNetwork: Added " + new_edges.len() + " edges for new town", Log.LVL_DEBUG);
        
        // If we were monitoring or upgrading, go back to building
        if (this.state == NetworkState.MONITORING || this.state == NetworkState.UPGRADING) {
            this.state = NetworkState.BUILDING;
        }
    }
}

/* Find k nearest towns to connect a new town */
function RoadNetwork::FindNearestTownEdges(new_town_id, k) {
    local edges = [];
    local distances = [];
    
    // Calculate distance to all existing towns in the set
    foreach (town_id, _ in this.town_id_set) {
        if (town_id == new_town_id) continue;
        if (!GSTown.IsValidTown(town_id)) continue;  // Skip invalid towns
        
        distances.append({
            town = town_id,
            dist = this.TownDistance(new_town_id, town_id)
        });
    }
    
    if (distances.len() == 0) return edges;
    
    // Sort by distance
    distances.sort(function(a, b) { return a.dist - b.dist; });
    
    // Take k nearest
    local count = (k < distances.len()) ? k : distances.len();
    for (local i = 0; i < count; i++) {
        local nearest_id = distances[i].town;
        edges.append(this.CreateEdge(new_town_id, nearest_id, EdgeType.INTRA_REGION));
    }
    
    return edges;
}

/* ========== State Handlers (Stubs) ========== */

function RoadNetwork::DoInit() {
    Log.Info("RoadNetwork: Initializing...", Log.LVL_INFO);
    
    // 1. Build town ID set
    this.BuildTownIdSet();
    
    // 2. Partition towns into regions
    this.PartitionTownsIntoRegions();
    
    // 3. Build MST for each region
    this.mst_edges = [];
    foreach (region_id, _ in this.regions) {
        local region_mst = this.BuildRegionMST(region_id);
        foreach (edge in region_mst) {
            this.mst_edges.append(edge);
        }
    }
    Log.Info("Built MST with " + this.mst_edges.len() + " intra-region edges", Log.LVL_INFO);
    
    // 4. Find inter-region connections
    this.inter_region_edges = this.FindInterRegionConnections();
    
    // 5. Merge all edges and identify major city edges
    foreach (edge in this.inter_region_edges) {
        this.mst_edges.append(edge);
    }
    this.IdentifyMajorCityEdges();
    
    // 6. Prepare build queue (prioritize inter-region and major city edges)
    this.PrepareBuildQueue();
    
    this.stats.edges_planned = this.build_queue.len();
    Log.Info("Build queue prepared: " + this.build_queue.len() + " edges", Log.LVL_INFO);
    
    this.state = NetworkState.BUILDING;
}

/* Prepare build queue with prioritization */
function RoadNetwork::PrepareBuildQueue() {
    // Separate edges by type
    local high_priority = [];   // Inter-region and major city
    local normal_priority = []; // Regular edges
    
    foreach (edge in this.mst_edges) {
        if (edge.type == EdgeType.INTER_REGION || edge.type == EdgeType.MAJOR_CITY) {
            high_priority.append(edge);
            this.trunk_edges.append(edge);  // Mark for future upgrade
        } else {
            normal_priority.append(edge);
        }
    }
    
    // Sort each group by distance (shorter first)
    high_priority.sort(function(a, b) { return a.distance - b.distance; });
    normal_priority.sort(function(a, b) { return a.distance - b.distance; });
    
    // Build queue: high priority first, then normal
    this.build_queue = [];
    foreach (edge in high_priority) {
        this.build_queue.append(edge);
    }
    foreach (edge in normal_priority) {
        this.build_queue.append(edge);
    }
    
    this.current_build_edge_index = 0;
    
    Log.Info("Trunk edges: " + this.trunk_edges.len() + ", Regular edges: " + normal_priority.len(), Log.LVL_DEBUG);
}

function RoadNetwork::DoBuilding() {
    // Process one unit of work (async, yields between iterations)
    local still_working = this.BuildBatchAsync();
    
    // Log progress periodically
    if (this.stats.edges_built > 0 && this.stats.edges_built % 10 == 0) {
        Log.Info("RoadNetwork: Progress " + this.stats.edges_built + "/" + this.stats.edges_planned + 
                 " (failed: " + this.stats.edges_failed + ")", Log.LVL_DEBUG);
    }
    
    // Check if all edges are processed
    if (!still_working && this.build_edge == null) {
        Log.Info("RoadNetwork: Building complete! Built: " + this.stats.edges_built + 
                 ", Failed: " + this.stats.edges_failed, Log.LVL_INFO);
        this.ResetBuildAsyncState();
        this.state = NetworkState.MONITORING;
    }
}

function RoadNetwork::DoMonitoring() {
    // Check for decade update (every 10 years)
    local current_decade = GSDate.GetYear(GSDate.GetCurrentDate()) / 10;
    if (current_decade > this.last_decade_update) {
        this.DecadeUpdate();
        this.last_decade_update = current_decade;
    }
    
    // Check for new road types yearly
    local current_year = GSDate.GetYear(GSDate.GetCurrentDate());
    if (current_year <= this.last_road_type_check_year) return;
    this.last_road_type_check_year = current_year;
    
    local new_best = this.FindBestRoadType();
    
    if (new_best != null && new_best != this.best_road_type) {
        local old_speed = GSRoad.GetMaxSpeed(this.best_road_type);
        local new_speed = GSRoad.GetMaxSpeed(new_best);
        
        if (old_speed == 0) old_speed = 65535;
        if (new_speed == 0) new_speed = 65535;
        
        if (new_speed > old_speed) {
            Log.Info("RoadNetwork: New road type available! " + GSRoad.GetName(new_best), Log.LVL_INFO);
            this.best_road_type = new_best;
            this.current_road_type = new_best;
            
            // Prepare trunk roads for upgrade
            this.PrepareUpgradeQueue();
            this.state = NetworkState.UPGRADING;
        }
    }
}

/* Decade update: re-evaluate major cities and edge types every 10 years */
function RoadNetwork::DecadeUpdate() {
    Log.Info("RoadNetwork: Performing decade update...", Log.LVL_INFO);
    
    // Store old major cities for comparison
    local old_major_cities = this.major_cities;
    
    // Re-identify major cities based on current populations
    this.UpdateMajorCities();
    
    // Log changes in major cities
    local added = 0;
    local removed = 0;
    foreach (town_id, _ in this.major_cities) {
        if (!old_major_cities.rawin(town_id)) added++;
    }
    foreach (town_id, _ in old_major_cities) {
        if (!this.major_cities.rawin(town_id)) removed++;
    }
    if (added > 0 || removed > 0) {
        Log.Info("RoadNetwork: Major cities changed: +" + added + " -" + removed, Log.LVL_INFO);
    }
    
    // Update edge types based on new major cities
    this.UpdateEdgeTypes();
    
    // Rebuild trunk_edges list with current trunk roads only
    this.RebuildTrunkEdgesList();
    
    // Check for failed edges and retry building them
    local failed_count = this.RebuildFailedEdges();
    if (failed_count > 0) {
        Log.Info("RoadNetwork: Retrying " + failed_count + " failed edges", Log.LVL_INFO);
        this.state = NetworkState.BUILDING;
    }
}

/* Re-identify major cities based on current populations */
function RoadNetwork::UpdateMajorCities() {
    // Get town populations
    local town_pops = [];
    foreach (town in this.towns) {
        town_pops.append({
            town_id = town.id,
            population = this.GetTownPopulation(town.id)
        });
    }
    
    // Sort by population descending
    town_pops.sort(function(a, b) { return b.population - a.population; });
    
    // Mark top 10% as major cities
    local major_count = (town_pops.len() + 9) / 10;  // Ceiling division
    this.major_cities = {};
    
    for (local i = 0; i < major_count && i < town_pops.len(); i++) {
        this.major_cities[town_pops[i].town_id] <- true;
    }
    
    Log.Info("RoadNetwork: Identified " + major_count + " major cities", Log.LVL_DEBUG);
}

/* Update edge types based on current major cities */
function RoadNetwork::UpdateEdgeTypes() {
    local promoted = 0;
    local demoted = 0;
    
    foreach (edge in this.mst_edges) {
        local is_connected_to_major = this.major_cities.rawin(edge.town_a) || 
                                       this.major_cities.rawin(edge.town_b);
        
        // Skip inter-region edges - they always stay as trunk roads
        if (edge.type == EdgeType.INTER_REGION) continue;
        
        if (is_connected_to_major && edge.type == EdgeType.INTRA_REGION) {
            // Promote to major city edge
            edge.type = EdgeType.MAJOR_CITY;
            promoted++;
        } else if (!is_connected_to_major && edge.type == EdgeType.MAJOR_CITY) {
            // Demote to regular edge (city is no longer major)
            edge.type = EdgeType.INTRA_REGION;
            demoted++;
        }
    }
    
    if (promoted > 0 || demoted > 0) {
        Log.Info("RoadNetwork: Edge type changes: +" + promoted + " promoted, -" + demoted + " demoted", Log.LVL_DEBUG);
    }
}

/* Rebuild trunk_edges list with only current trunk roads */
function RoadNetwork::RebuildTrunkEdgesList() {
    this.trunk_edges = [];
    
    foreach (edge in this.mst_edges) {
        if (edge.type == EdgeType.INTER_REGION || edge.type == EdgeType.MAJOR_CITY) {
            // Only include successfully built edges for upgrade
            if (edge.status == EdgeStatus.BUILT) {
                this.trunk_edges.append(edge);
            }
        }
    }
    
    Log.Info("RoadNetwork: Trunk edges list updated: " + this.trunk_edges.len() + " edges", Log.LVL_DEBUG);
}

/* Find failed edges and add them back to build queue */
function RoadNetwork::RebuildFailedEdges() {
    local failed_edges = [];
    
    foreach (edge in this.mst_edges) {
        if (edge.status == EdgeStatus.FAILED) {
            // Reset status to pending for retry
            edge.status = EdgeStatus.PENDING;
            failed_edges.append(edge);
        }
    }
    
    if (failed_edges.len() > 0) {
        // Sort failed edges by priority (trunk roads first, then by distance)
        failed_edges.sort(function(a, b) {
            // Prioritize trunk roads
            if (a.type != b.type) {
                if (a.type == EdgeType.INTER_REGION || a.type == EdgeType.MAJOR_CITY) return -1;
                if (b.type == EdgeType.INTER_REGION || b.type == EdgeType.MAJOR_CITY) return 1;
            }
            return a.distance - b.distance;
        });
        
        // Add to build queue
        foreach (edge in failed_edges) {
            this.build_queue.append(edge);
        }
        
        // Update stats
        this.stats.edges_failed -= failed_edges.len();
    }
    
    return failed_edges.len();
}

function RoadNetwork::DoUpgrading() {
    // Process one upgrade (async, yields between iterations)
    local still_working = this.UpgradeBatchAsync();
    
    // Log progress periodically
    if (this.stats.edges_upgraded > 0 && this.stats.edges_upgraded % 10 == 0) {
        Log.Info("RoadNetwork: Upgrade progress " + this.current_upgrade_edge_index + "/" + this.trunk_edges.len(), Log.LVL_DEBUG);
    }
    
    // Check if upgrade is complete (no more work AND no edge in progress)
    if (!still_working && this.upgrade_edge == null) {
        Log.Info("RoadNetwork: Trunk road upgrade complete! Upgraded: " + this.stats.edges_upgraded, Log.LVL_INFO);
        this.current_upgrade_edge_index = 0;  // Reset for next upgrade cycle
        this.ResetUpgradeAsyncState();
        this.state = NetworkState.MONITORING;
    }
}

/* Prepare trunk edges for upgrade */
function RoadNetwork::PrepareUpgradeQueue() {
    // Rebuild trunk edges list to only include current trunk roads
    this.RebuildTrunkEdgesList();
    
    // Reset upgrade state
    this.current_upgrade_edge_index = 0;
    this.edges_upgraded_this_month = 0;
    this.last_upgrade_month = GSDate.GetMonth(GSDate.GetCurrentDate());
    
    // Reset async upgrade pathfinding state
    this.ResetUpgradeAsyncState();
    
    // Reset upgrade_state for all trunk edges
    foreach (edge in this.trunk_edges) {
        if (!("upgrade_state" in edge)) {
            edge.upgrade_state <- EdgeBuildState.PENDING;
        } else {
            edge.upgrade_state = EdgeBuildState.PENDING;
        }
    }
    
    Log.Info("RoadNetwork: Preparing to upgrade " + this.trunk_edges.len() + " trunk roads", Log.LVL_INFO);
}

/* Reset async upgrade pathfinding state */
function RoadNetwork::ResetUpgradeAsyncState() {
    this.upgrade_pathfinder = null;
    this.upgrade_edge = null;
    this.upgrade_path = null;
    this.upgrade_path_index = 0;
    this.upgrade_pathfind_iterations = 0;
}

/* Start pathfinding for upgrade - find existing road path */
function RoadNetwork::StartUpgradePathfinding(edge) {
    // Set road type
    GSRoad.SetCurrentRoadType(this.current_road_type);
    
    // Create pathfinder instance
    local pf = SuperLib.RoadPathFinder();
    
    // Initialize path search - use repair_existing=true to strongly prefer existing roads
    pf.InitializePath([edge.from_tile], [edge.to_tile], true);
    pf.SetMaxIterations(PATHFIND_MAX_ITERATIONS);
    pf.SetStepSize(PATHFIND_STEP_SIZE);
    
    // Store state for continuation
    this.upgrade_pathfinder = pf;
    this.upgrade_edge = edge;
    this.upgrade_path = null;
    this.upgrade_path_index = 0;
    this.upgrade_pathfind_iterations = 0;
    
    // Update edge state
    edge.upgrade_state = EdgeBuildState.PATHFINDING;
    
    Log.Info("Started upgrade pathfinding: " + edge.town_a + " -> " + edge.town_b, Log.LVL_DEBUG);
}

/* Continue upgrade pathfinding - returns PathfindResult */
function RoadNetwork::ContinueUpgradePathfinding() {
    if (this.upgrade_pathfinder == null || this.upgrade_edge == null) {
        return PathfindResult.FAILED;
    }
    
    // Execute one step of pathfinding
    local path = this.upgrade_pathfinder.FindPath();
    this.upgrade_pathfind_iterations += PATHFIND_STEP_SIZE;
    
    // Check result
    local error = this.upgrade_pathfinder.GetFindPathError();
    
    if (path != null) {
        // Path found!
        this.upgrade_path = path;
        Log.Info("Upgrade path found: " + this.upgrade_edge.town_a + " -> " + this.upgrade_edge.town_b + 
                 " (" + this.upgrade_pathfind_iterations + " iterations)", Log.LVL_DEBUG);
        return PathfindResult.FOUND;
    }
    
    // Check for errors
    if (error == SuperLib.RoadPathFinder.PATH_FIND_FAILED_NO_PATH) {
        Log.Info("No upgrade path: " + this.upgrade_edge.town_a + " -> " + this.upgrade_edge.town_b, Log.LVL_DEBUG);
        return PathfindResult.FAILED;
    }
    
    if (error == SuperLib.RoadPathFinder.PATH_FIND_FAILED_TIME_OUT) {
        Log.Info("Upgrade pathfind timeout: " + this.upgrade_edge.town_a + " -> " + this.upgrade_edge.town_b, Log.LVL_DEBUG);
        return PathfindResult.FAILED;
    }
    
    // Still searching
    return PathfindResult.CONTINUE;
}

/* Upgrade road segments incrementally - returns BuildResult */
function RoadNetwork::UpgradeRoadSegments() {
    if (this.upgrade_path == null || this.upgrade_edge == null) {
        return BuildResult.FAILED;
    }
    
    // Set road type
    GSRoad.SetCurrentRoadType(this.current_road_type);
    
    local segments_upgraded = 0;
    local path = this.upgrade_path;
    
    // Convert path to array if not done yet
    if (typeof path != "array") {
        local path_array = [];
        local node = path;
        while (node != null) {
            path_array.append(node.GetTile());
            node = node.GetParent();
        }
        path_array.reverse();
        this.upgrade_path = path_array;
        path = this.upgrade_path;
    }
    
    // Upgrade segments from current position
    while (this.upgrade_path_index < path.len() - 1 && segments_upgraded < BUILD_SEGMENTS_PER_TICK) {
        local from_tile = path[this.upgrade_path_index];
        local to_tile = path[this.upgrade_path_index + 1];
        
        // Check ops budget
        if (GSController.GetOpsTillSuspend() < OPS_SUSPEND_THRESHOLD) {
            return BuildResult.CONTINUE;
        }
        
        // Convert road type for this segment
        if (GSMap.DistanceManhattan(from_tile, to_tile) == 1) {
            // Adjacent tiles - convert road type directly
            GSRoad.ConvertRoadType(from_tile, to_tile, this.current_road_type);
        } else if (GSBridge.IsBridgeTile(from_tile)) {
            // Bridge detected - check if we can upgrade to a faster bridge
            local other_end = GSBridge.GetOtherBridgeEnd(from_tile);
            local current_bridge_type = GSBridge.GetBridgeType(from_tile);
            local current_speed = GSBridge.GetMaxSpeed(current_bridge_type);
            if (current_speed == 0) current_speed = 65535;
            
            // Find a faster bridge
            local bridge_length = GSMap.DistanceManhattan(from_tile, other_end) + 1;
            local bridge_list = GSBridgeList_Length(bridge_length);
            bridge_list.Valuate(GSBridge.GetMaxSpeed);
            bridge_list.KeepAboveValue(current_speed);
            
            if (!bridge_list.IsEmpty()) {
                // Sort by speed descending and pick the fastest
                bridge_list.Sort(GSList.SORT_BY_VALUE, false);
                local new_bridge_type = bridge_list.Begin();
                
                // Rebuild bridge with faster type
                if (GSBridge.BuildBridge(GSVehicle.VT_ROAD, new_bridge_type, from_tile, other_end)) {
                    local new_speed = GSBridge.GetMaxSpeed(new_bridge_type);
                    Log.Info("Upgraded bridge: speed " + current_speed + " -> " + new_speed, Log.LVL_DEBUG);
                }
            }
            
            // Skip to end of bridge in path
            while (this.upgrade_path_index < path.len() - 1 && path[this.upgrade_path_index] != other_end) {
                this.upgrade_path_index++;
            }
        } else if (GSTunnel.IsTunnelTile(from_tile)) {
            // Tunnel detected - skip to other end (tunnels have no speed limit)
            local other_end = GSTunnel.GetOtherTunnelEnd(from_tile);
            while (this.upgrade_path_index < path.len() - 1 && path[this.upgrade_path_index] != other_end) {
                this.upgrade_path_index++;
            }
        }
        
        this.upgrade_path_index++;
        segments_upgraded++;
    }
    
    // Check if done
    if (this.upgrade_path_index >= path.len() - 1) {
        Log.Info("Road upgraded: " + this.upgrade_edge.town_a + " -> " + this.upgrade_edge.town_b + 
                 " (" + path.len() + " tiles)", Log.LVL_DEBUG);
        return BuildResult.COMPLETE;
    }
    
    return BuildResult.CONTINUE;
}

/* Get next pending edge from upgrade queue */
function RoadNetwork::GetNextPendingUpgradeEdge() {
    while (this.current_upgrade_edge_index < this.trunk_edges.len()) {
        local edge = this.trunk_edges[this.current_upgrade_edge_index];
        
        // Initialize upgrade_state if not present
        if (!("upgrade_state" in edge)) {
            edge.upgrade_state <- EdgeBuildState.PENDING;
        }
        
        // Check if this edge needs processing
        if (edge.upgrade_state == EdgeBuildState.PENDING && edge.status == EdgeStatus.BUILT) {
            return edge;
        }
        
        this.current_upgrade_edge_index++;
    }
    return null;
}

/* Async upgrade - process one unit of work then yield
 * Returns: true if still working, false if all done
 */
function RoadNetwork::UpgradeBatchAsync() {
    // Check monthly rate limit
    local current_month = GSDate.GetMonth(GSDate.GetCurrentDate());
    if (current_month != this.last_upgrade_month) {
        // New month - reset counter
        this.edges_upgraded_this_month = 0;
        this.last_upgrade_month = current_month;
    }
    
    // If reached monthly limit, pause (but keep current edge in progress)
    if (this.upgrade_edge == null && this.edges_upgraded_this_month >= this.upgrade_rate) {
        return true;  // Still have work, but waiting for next month
    }
    
    // Check ops budget before starting
    if (GSController.GetOpsTillSuspend() < OPS_SUSPEND_THRESHOLD) {
        return true;  // Still working, but yield now
    }
    
    // If no current edge, get the next one
    if (this.upgrade_edge == null) {
        local edge = this.GetNextPendingUpgradeEdge();
        if (edge == null) {
            return false;  // All edges processed
        }
        this.StartUpgradePathfinding(edge);
        return true;
    }
    
    // Process current edge based on its state
    local edge = this.upgrade_edge;
    
    switch (edge.upgrade_state) {
        case EdgeBuildState.PATHFINDING: {
            local result = this.ContinueUpgradePathfinding();
            
            switch (result) {
                case PathfindResult.CONTINUE:
                    return true;
                    
                case PathfindResult.FOUND:
                    edge.upgrade_state = EdgeBuildState.BUILDING;
                    return true;
                    
                case PathfindResult.FAILED:
                    edge.upgrade_state = EdgeBuildState.FAILED;
                    Log.Warning("Failed to find upgrade path for edge: " + edge.town_a + " -> " + edge.town_b);
                    this.current_upgrade_edge_index++;
                    this.ResetUpgradeAsyncState();
                    return true;
            }
            break;
        }
        
        case EdgeBuildState.BUILDING: {
            local result = this.UpgradeRoadSegments();
            
            switch (result) {
                case BuildResult.CONTINUE:
                    return true;
                    
                case BuildResult.COMPLETE:
                    edge.upgrade_state = EdgeBuildState.COMPLETE;
                    this.stats.edges_upgraded++;
                    this.edges_upgraded_this_month++;
                    this.current_upgrade_edge_index++;
                    this.ResetUpgradeAsyncState();
                    return true;
                    
                case BuildResult.FAILED:
                    edge.upgrade_state = EdgeBuildState.FAILED;
                    this.current_upgrade_edge_index++;
                    this.ResetUpgradeAsyncState();
                    return true;
            }
            break;
        }
        
        default:
            Log.Warning("Unexpected upgrade edge state: " + edge.upgrade_state);
            this.current_upgrade_edge_index++;
            this.ResetUpgradeAsyncState();
            return true;
    }
    
    return true;
}
