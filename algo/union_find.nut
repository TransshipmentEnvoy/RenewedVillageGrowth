/*
 * Union-Find (Disjoint Set Union) data structure
 * Used for Kruskal's MST algorithm in road network construction
 *
 * This file is part of Renewed Village Growth Extended.
 */

class UnionFind {
    p = null;      // parent array (can't use 'parent' - reserved word)
    rnk = null;    // rank array
    size = null;

    constructor(n) {
        this.size = n;
        this.p = array(n);
        this.rnk = array(n, 0);
        for (local i = 0; i < n; i++) {
            this.p[i] = i;
        }
    }
}

/* Find root of element with path compression */
function UnionFind::Find(x) {
    if (this.p[x] != x) {
        this.p[x] = this.Find(this.p[x]);
    }
    return this.p[x];
}

/* Union two sets by rank */
function UnionFind::Union(x, y) {
    local root_x = this.Find(x);
    local root_y = this.Find(y);

    if (root_x == root_y) {
        return false;  // Already in same set
    }

    // Union by rank
    if (this.rnk[root_x] < this.rnk[root_y]) {
        this.p[root_x] = root_y;
    } else if (this.rnk[root_x] > this.rnk[root_y]) {
        this.p[root_y] = root_x;
    } else {
        this.p[root_y] = root_x;
        this.rnk[root_x]++;
    }

    return true;
}

/* Check if two elements are in the same set */
function UnionFind::Connected(x, y) {
    return this.Find(x) == this.Find(y);
}
