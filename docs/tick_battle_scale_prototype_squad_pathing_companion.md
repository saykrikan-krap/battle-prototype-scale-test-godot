# Squad-Aware Pathing & Formations — Companion Implementation Guide (Prototype)

**Audience:** Codex (primary implementer).  
**Reviewer/QA/Direction:** You (project owner).

This is a companion to:
- `tick_battle_scale_prototype_godot45_requirements.md` (Section 7 now points here).

---

## 0. Scope Update

Squads + formations are now **in scope** for the prototype. This guide specifies the definitive approach we will implement first.

### Design goals

1. **Standard marches stay cohesive** on clear ground.
2. **Malleable around obstacles / choke points** (squads snake/compress as needed).
3. **Mixed speeds + debuffs** (slow/paralyzed units do not stall the whole squad).
4. **Deterministic & scalable** (thousands of units; dozens of squads; replay hash stable).
5. **Low tuning overhead**: avoid “weight soup” and brittle logic.

### Non-goals (for this prototype pass)

- Perfect formation locking / collision-free marching in all edge cases.
- Full group-level A* (anchor + flow field is the intended scale strategy).
- Optimal slot assignment (we’ll do a simple deterministic repack only if needed).

---

## 1. Definitive Approach To Implement

### Summary

We will implement:

1. **Strategic distance field (flow field)** via multi-source **Dijkstra** per side + movement profile + size.
   - **Terrain + objectives only.**
   - **Do not** include friendly occupancy as Dijkstra cost.

2. **Squad anchor** follows the strategic field.
   - One “anchor move” decision per squad instead of per unit.

3. **Unit movement uses “Goal-Slack + Formation Tie-Break”.**
   - Evaluate a tiny set of candidate moves.
   - Choose the best **goal progress** move(s), then pick the one that best preserves formation.
   - Only a handful of knobs: `SLACK_BASE`, `SLACK_CHOKE_BONUS`, `DETACH_DIST`, occupancy rules.

4. **Two-phase movement application** for units that activate on the same tick.
   - Phase A: compute intents.
   - Phase B: deterministic conflict resolution, then apply.

This combination specifically targets your current failure mode: “rear ranks try to path around the front and instantly break formation.”

---

## 2. Key Concepts & Terms

- **Strategic field**: `dist[tile]` that encodes “how close am I to the enemy/objective.” Lower is better.
- **Anchor**: a virtual squad reference point. The squad’s formation slots are defined relative to it.
- **Desired slot**: target tile for a unit when formation is healthy.
- **Slack**: how much worse a move is allowed to be (in goal-distance terms) in order to preserve formation.

---

## 3. Data Additions (Schema + Resolver State)

### 3.1 Per-unit additions (SoA arrays)

Add to existing unit storage:

- `squad_id[id] : int` (`-1` if none)
- `slot_dx[id], slot_dy[id] : int`
  - slot offset when squad facing is **North** (canonical orientation)
- `attached[id] : bool`
  - whether the unit is currently expected to adhere to formation strongly
- `keep_formation_in_melee[id] : bool` (or derive from unit type)

Optional (but helpful):
- `stuck_count[id] : int` (increment when a unit wants to move but can’t)

### 3.2 Per-squad state

- `anchor_x[s], anchor_y[s] : int`
- `anchor_next_tick[s] : int`
- `anchor_delay[s] : int`
  - squad “march cadence” (recommend median base move delay of members; see §7)
- `facing_dir[s] : int` (0=N,1=E,2=S,3=W)
- `slack_base[s] : int` (start with 1–2)
- `slack_choke_bonus[s] : int` (start with 2)
- `formation_enabled[s] : bool`
- `movement_profile[s] : int` (foot/cav/amphib/etc)
- `size_profile[s] : int` (usually max size among members)

### 3.3 Map / terrain state

- `terrain_type[tile] : int`
- `terrain_version : int` (increment on spell changes)
- Prototype v1 terrain types:
  - Grassland = 0
  - Trees = 1
- Prototype v1 terrain costs:
  - Grassland: 1
  - Trees: 2

### 3.4 Occupancy index

Use existing per-tile occupancy summary:
- `tile_total_size[tile]`
- `tile_side[tile]` (or mixed/none)
- `tile_unit_ids[]` (optional list)

Define a tile capacity rule:
- `TILE_CAPACITY = 4` (matches “up to 4 units per tile” rendering assumption)

---

## 4. Strategic Field Build (Dijkstra)

### 4.1 Why

- We need terrain weights (woods, hills, water, boulders) and unit-specific movement.
- Grid is small (~80×40 typical), so Dijkstra is cheap.

### 4.2 Field dimensions

Compute fields:

- Per **side**: `dist_side[side][profile][size][tile]`
- Profiles: start with 1 profile for the prototype if needed, but structure for more.
- Sizes: at least size-2 and size-3, as per the base requirements.

### 4.3 Seeds (objective definition)

Prototype seed rule (keep it simple):
- Multi-source seed = all tiles occupied by **enemy** units.
- Seed distance = 0 on those tiles.

(If enemy tiles are impassable, seed adjacent passable tiles instead.)

### 4.4 Tile traversal cost

Provide a function:

- `step_cost(profile, size, tile_from, tile_to) -> int`

Rules:
- If `tile_to` is impassable for this (profile,size), it is not expanded.
- Cost must be **integer** for determinism and easy slack tuning.
- Prototype v1: `step_cost = TERRAIN_COST[terrain_type[tile_to]]` (grass=1, trees=2).

Important: **Do not include friendly occupancy in this step cost.**

### 4.5 Determinism for Dijkstra

Use a priority queue with a stable tie-break:
- Key = `(dist, tile_index)`
- `tile_index = y * width + x`

This ensures consistent behavior even when distances tie.

### 4.6 Recompute schedule

- Maintain cached fields per `(side, profile, size)` and rebuild only when needed.
- Track `terrain_version` plus `occupancy_version[side]` (increment when a unit of that side moves/spawns/dies).
- Rebuild when dirty **and** `tick >= last_build_tick + REBUILD_INTERVAL_TICKS`.
- Always rebuild if `tick >= last_build_tick + MAX_STALE_TICKS` (safety).
- A stale guard can set `force_rebuild` if units repeatedly fail to improve goal distance.

### 4.7 Uniform-cost fast path

If all edge costs are 1, a multi-source BFS is equivalent to Dijkstra and is much faster in GDScript. Keep the same API and switch to PQ-based Dijkstra when terrain costs become non-uniform.

---

## 5. Squad Anchor Update

### 5.1 When the anchor moves

Anchor moves when `tick >= anchor_next_tick[s]`:

- Look up the correct field:
  - side = squad’s side
  - profile = `movement_profile[s]`
  - size = `size_profile[s]`

- Consider candidate moves: `{stay, N, S, E, W}`
- Choose move that minimizes `dist[tile]` (deterministic neighbor order)
- If no neighbor improves `dist`, anchor stays.

After decision:
- If anchor moved, update `facing_dir` to that direction.
- `anchor_next_tick[s] += anchor_delay[s]`

### 5.2 Why anchor speed is separate from unit speed

- Mixed speed squads exist.
- Debuffs/paralysis exist.
- We **do not** want the anchor cadence to be dictated by the slowest or incapacitated member.

Prototype rule:
- `anchor_delay[s] = median(base_move_delay[unit_type])` across alive members.
- Ignore temporarily slowed/paralyzed effects for the anchor.

---

## 6. Unit Move Choice (Goal-Slack + Formation Tie-Break)

This is the core formation behavior.

### 6.1 Candidate set

For an activating unit `u`, define candidate tiles:

- `C = { current (stay), N, S, E, W }`

Filter out candidates that are impassable for that unit’s profile/size.

### 6.2 Compute goal cost per candidate

For each candidate tile `p`:

`goal_cost(p) = dist[p] + local_occupancy_penalty(u, p)`

Local occupancy handling (prototype rules):

- If `tile_total_size[p] + size[u] > TILE_CAPACITY` → treat as **blocked**.
- Friendly occupancy is allowed (soft), but add a small penalty:
  - `FRIEND_PENALTY = 1` (start here)
  - (Optionally scale with crowding: +1 per extra size already in tile)
- Enemy occupancy: treat as blocked for movement (engagement handled elsewhere).

### 6.3 Build the “good enough” set with slack

Let:

- `best = min(goal_cost(p))` over passable candidates
- `slack = squad_slack(u)` (see §6.6)

Define:

- `S = { p in C | goal_cost(p) <= best + slack }`

This means: “only consider moves that are near-best for strategic progress.”

### 6.4 Formation tie-break

If the unit is in formation mode (see §6.5), compute desired slot tile:

- `desired = anchor + rotate(slot_dx[u], slot_dy[u], facing_dir[squad])`

Then choose from `S` the tile `p` minimizing:

- `form_error(p) = manhattan_distance(p, desired)`

Final tie-break order (deterministic):

1. smallest `form_error(p)`
2. smallest `goal_cost(p)`
3. fixed neighbor order (e.g., stay, N, E, S, W)

### 6.5 When formation is “active” for a unit

Formation is active if:

- `squad_id[u] != -1`
- `formation_enabled[squad] == true`
- `attached[u] == true`
- and either:
  - `keep_formation_in_melee[u] == true`, OR
  - `u` is not engaged (no adjacent enemy)

(Engagement break is optional per unit type.)

### 6.6 Computing `squad_slack(u)`

Keep this extremely simple.

Start with:

- `slack = slack_base[squad]`

Then add a choke bonus if the squad is congested:

- Compute `blocked_ratio` for the squad each tick:
  - among **attached** units that activated this tick, how many had `chosen_move == stay` while their `best` move was not stay?

If `blocked_ratio >= 0.5` then:

- `slack += slack_choke_bonus[squad]`

That’s it. One threshold, one bonus.

Rationale:
- On open ground: low blocked_ratio ⇒ formation stays tight.
- At choke: high blocked_ratio ⇒ formation loosens enough to snake through.

---

## 7. Unit Tick Scheduling (Speed, Terrain, Status)

Your architecture already supports per-unit activation (`next_tick[id]`). Keep that and let speed emerge from tick scheduling.

### 7.1 Move delay

When a unit moves into `p`, set:

- `next_tick[u] += move_delay(unit_type[u], terrain_type[p], status_effects[u])`

Prototype: if statuses aren’t implemented yet, just use `terrain_type[p]` and unit base speed.
For trees, cavalry types use the Infantry base move cost before applying the multiplier.

Examples:
- cavalry on open: 4
- infantry on open: 6
- cavalry in trees: 12 (advantage removed)
- infantry in trees: 12
- paralyzed: very large delay or “cannot move” flag (still can fight)

### 7.2 Why this avoids “rewrite tons of pathfinding code”

- The strategic field stays the same.
- Only `move_delay()` and movement profile selection changes as mechanics expand.

---

## 8. Attached / Detached (Stragglers Without Stalling The Squad)

### 8.1 Detach rule (prototype)

When a unit activates, compute its current desired slot tile (even if it won’t adhere) and:

- `err = manhattan_distance(current_pos, desired)`

If:

- `err > DETACH_DIST` (start with 6–10 tiles)

Then:

- `attached[u] = false`

Detached units:
- Ignore formation tie-break (or treat `slack` as very large).
- Still use the same strategic field + local occupancy rules.

### 8.2 Reattach rule

If detached and:

- `err <= REATTACH_DIST` (smaller than detach; start with 4–6)

Then:

- `attached[u] = true`

Use hysteresis (two thresholds) to avoid flip-flopping.

---

## 9. Two-Phase Move Application (Conflict Resolution)

### 9.1 Why

Applying moves immediately in a single pass causes rear units to treat front units as static obstacles. Two-phase application reduces that and makes formation cohesion much more stable.

### 9.2 Implementation

At each simulation tick `t`:

1. **Collect active units**: all `u` with `alive[u] && next_tick[u] <= t`.
2. **Compute intents**: for each active unit, compute intended target tile `intent[u]`.
3. **Resolve conflicts** deterministically.
4. **Apply** the winning moves simultaneously (update positions + occupancy + next_tick).

### 9.3 Conflict rules (prototype)

- If a tile can accept multiple units up to `TILE_CAPACITY`, treat it as a capacity problem:
  - accept intents in priority order until full, remaining units stay.

Priority order (deterministic, formation-friendly):

1. `squad_id` ascending (non-squad units after squads)
2. within squad: **front-to-back** order
   - compute each unit’s “rank” from its slot offset projected onto `facing_dir`
3. then `unit_id` ascending

This helps prevent “rear overtakes front.”

(We can add same-squad chain-move support later if needed, but start here.)

---

## 10. Debugging & Instrumentation (Required)

Add a debug overlay mode that can be toggled:

Per squad:
- draw anchor tile
- draw facing arrow
- display `slack` and whether choke bonus is active
- display `anchor_delay`

Per unit (optional):
- if selected/hovered, draw desired slot tile
- print `attached` + `err`

Metrics:
- average formation error per squad (`avg err` over attached units)
- percent detached

---

## 11. Acceptance Tests (Prototype)

### Test A — Clear march

- Two squads, wide open map.
- Expect: ranks remain aligned; minimal lateral drift.

### Test B — Choke point

- Add walls with a 1–2 tile gap.
- Expect: squad compresses/snakes through; reforms afterward.

### Test C — Paralyzed straggler

- Apply “cannot move” to a rear unit.
- Expect: squad continues; straggler detaches; does not cause the squad to explode.

### Test D — Mixed speed

- Mix cav + infantry.
- Expect: cav does not permanently peel off sideways; either waits or becomes detached depending on thresholds.

---

## 12. Implementation Plan (Codex)

### Phase 1 — Field + anchor + basic formation tie-break

- [ ] Remove friendly soft-blocking cost from strategic Dijkstra.
- [ ] Add squad anchor state + update rule.
- [ ] Implement unit move choice with goal-slack + formation tie-break.
- [ ] Add “stay” candidate.

### Phase 2 — Two-phase move + deterministic conflict

- [ ] Intent pass for active units.
- [ ] Conflict resolution with formation-friendly priority.
- [ ] Apply simultaneously.

### Phase 3 — Detach/reattach + choke slack

- [ ] `attached` + detach/reattach thresholds.
- [ ] blocked_ratio → slack bonus.
- [ ] melee break toggle.

Stop after Phase 3 and assess visuals.

---

## 13. Default Knobs (Start Here)

These are intentionally few.

- `TILE_CAPACITY = 4`
- `FRIEND_PENALTY = 1`
- `slack_base = 2`
- `slack_choke_bonus = 2`
- `DETACH_DIST = 8`
- `REATTACH_DIST = 5`

If formation still shears on clear ground:
- increase `slack_base` by 1 (more formation preference)
- increase `FRIEND_PENALTY` by 1 (more queueing)
- ensure “stay” is included and is not artificially penalized
