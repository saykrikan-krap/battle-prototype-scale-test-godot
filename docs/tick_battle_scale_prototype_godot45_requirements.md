# Tick-Based Battle Scale Prototype — Godot 4.5+ Implementation Requirements

This document applies the **Base Requirements** to **Godot 4.5+**.

It is intentionally “requirements + implementation guide rails,” not a full tutorial. The goal is to build a prototype that answers:
- Can Godot run the **resolver** fast enough for ~2000 units?
- Can Godot render the **replay** at an acceptable FPS?

---

## 1. Target & Build

- Target engine: **Godot 4.5+** (desktop client application).
- Primary platform: Windows/Linux (macOS optional).
- Use a single windowed scene for replay; no fancy tooling required.

---

## 2. Godot Project Layout (Mirrors the Base Split)

Use folders inside `res://`:

- `res://schema/`
  - enums + typed data structures (unit types, event types, battle input/output)
- `res://resolver/`
  - pure simulation logic (no Node dependencies)
- `res://replayer/`
  - playback clock + rendering + UI
- `res://scenarios/`
  - hardcoded Scale Test v1 generator
- `res://ui/`
  - minimal controls + debug overlay

**Rule:** `replayer/` must never import scripts from `resolver/` (only from `schema/`).

---

## 3. Language Choice (Pragmatic)

### Option A — GDScript first (fastest to iterate)
Use data-oriented arrays and avoid per-unit Nodes.
- Good for quickly proving correctness and seeing performance.
- If sim FPS or resolve time is clearly failing, port resolver to C# or GDExtension.

### Option B — C# for resolver (likely faster)
Keep the replayer in GDScript or C#; either is fine.
- The resolver can live in `res://resolver_cs/` and expose a single “Resolve()” entry.

**Either way:** keep the data contracts the same so other stacks can plug in later.

---

## 4. Resolver Execution (Keep UI Responsive)

### Requirement
The resolver should run without freezing the UI.

### Recommended in Godot
- Run resolve on a background worker mechanism and return:
  - `EventLog`
  - `BattleResult`
  - basic timing stats

Godot provides a worker thread pool that can execute Callables as tasks (including group tasks), intended for offloading expensive work. (See `WorkerThreadPool` docs.) 

---

## 5. Deterministic PRNG (Do Not Use Global rand())

Implement a tiny PRNG inside `res://schema/` so behavior is identical across platforms and languages.

Recommended: `xorshift32` or `pcg32`.

Rules:
- Seed comes from `BattleInput.seed`.
- All random calls in resolver are through this PRNG instance.
- Never call engine-global random helpers from inside the resolver.

---

## 6. Data-Oriented Unit Storage (ECS-ish)

Do **not** represent 2000 units as 2000 Nodes with scripts.

Use parallel arrays (struct-of-arrays) or a packed struct array:
- `alive[id] : bool`
- `side[id] : int`
- `type[id] : int`
- `size[id] : int`
- `x[id], y[id] : int`
- `next_tick[id] : int`

Maintain tile occupancy indices:
- For each tile: `unit_ids[]`, `count`, `total_size`, `side` (or “empty”).

This is the single biggest lever for scale.

---

## 7. Pathing & Formation Movement

Follow the base document and the **Squad-Aware Pathing & Formations companion guide** (`docs/tick_battle_scale_prototype_squad_pathing_companion.md`).

Required implementation shape:
- Build multi-source **Dijkstra** distance fields per side + size (terrain + objectives only).
- Drive a per-squad **anchor** along the field.
- Per unit, choose moves with **goal slack + formation tie-break** (include `stay`).
- Apply movement in **two phases** (intent then conflict resolution).
- Use deterministic tie-breaks for both Dijkstra and move resolution.
 - Cache fields per `(side, size)` and rebuild on a cadence (dirty + `REBUILD_INTERVAL_TICKS`, or `MAX_STALE_TICKS` safety).
 - A BFS fast path is allowed when all edge costs are uniform.

### Terrain Costs (v1)
- Track `tile_terrain` in `BattleInput` and log `TERRAIN_SET` events at tick 0 for replay.
- Terrain types:
  - Grassland: cost **1**
  - Trees: cost **2**
  - Water: **impassable**
- Movement delay = base move cost × terrain cost.
- Cavalry (including Heavy Cavalry) use the Infantry base move cost on trees (no speed advantage).

---

## 8. Event Log Representation (Memory Matters)

At 2000 units, event counts can get large. Avoid per-event Dictionaries if they balloon memory.

### Tier 1 (simple)
- `Array[Dictionary]` events
- Fast to implement, may be memory heavy

### Tier 2 (recommended)
- Use a lightweight `Event` struct/class with fixed fields:
  - `tick : int`
  - `seq : int`
  - `type : int`
  - `a, b, c, d : int` (generic payload slots)
- Or use parallel arrays (`ticks[]`, `seqs[]`, `types[]`, `a[]`, `b[]`, ...)

If Tier 1 becomes a problem, switch to Tier 2 before blaming the engine.

---

## 9. Rendering Strategy (Replay)

### 9.1 Grid Rendering
- Render the grid as simple lines or a flat TileMap background.
- Tile size: keep consistent with your earlier prototype’s pixel mapping (e.g., 32×32 or 48×48).

### 9.2 Units Rendering (Recommended: MultiMeshInstance2D)

For thousands of similar sprites, use a batched approach.

Godot’s `MultiMeshInstance2D` is a specialized node to instance a `MultiMesh` in 2D (similar usage to the 3D MultiMeshInstance). 

**Recommended setup**
- One `MultiMeshInstance2D` per unit type (7 total):
  - Infantry, Heavy Infantry, Elite Infantry, Archer, Cavalry, Heavy Cavalry, Mage
- Each MultiMesh updates instance transforms each frame (or each tick, if you snap).

**Within-tile layout**
- Up to 4 units per tile → 2×2 sub-cells inside the tile.
- For 3 units, leave the 4th slot empty.

### 9.3 Projectiles Rendering
- Separate MultiMesh for arrows and fireballs (or draw markers in a single Node2D).
- Interpolate projectile position from fire tick to impact tick.

---

## 10. Playback Clock

Implement a simple replay clock:
- `currentTick`
- `playing : bool`
- `ticksPerSecond` (10/20/40)
- Optional: “fast forward” multiplier

Rendering should derive the visible state from:
- last applied events ≤ `currentTick`
- plus interpolation values for movement/projectiles

---

## 11. Instrumentation Overlay

Add a debug overlay (CanvasLayer) showing:
- FPS
- Current tick
- Units alive per side
- Event count
- Resolver timing:
  - resolve wall-clock time
  - ticks/sec (avg)

This is essential to answer the “can it handle scale” question.

---

## 12. Headless / No-Render Resolve Mode (Recommended)

Godot supports running with a headless mode flag (`--headless`) for environments without GPU access and to prevent window creation in some workflows. 

Add a command-line switch or project setting to:
- run resolver only
- print timing + result summary
- optionally write event log to disk

This lets you profile simulation speed independent of rendering.

---

## 13. Minimal Scene Sketch

### `Main.tscn`
- `Node` (Main)
  - `BattleController` (script)
  - `CanvasLayer` (UI)
    - Resolve button / auto-start toggle
    - Play/Pause/Step controls
    - Tick rate dropdown
    - Debug labels

### `BattleView.tscn`
- `Node2D` (BattleView)
  - `GridRenderer` (Node2D or TileMap)
  - `UnitsRenderer` (MultiMeshInstance2D nodes)
  - `ProjectilesRenderer` (MultiMesh or Node2D)

---

## 14. Known Godot Gotchas (Requirements)

- Do not touch the scene tree from background threads.
- Keep the resolver free of Node references to ensure it can run headless and deterministically.
- Avoid per-frame allocations in replay (reuse arrays, pre-size instance counts).

---

## 15. Deliverable Checklist (Godot)

- [ ] Hardcoded Scale Test v1 scenario produces 1000 units per side.
- [ ] Resolver produces deterministic `EventLog` (hash stable across runs).
- [ ] Replay renders from log only (no resolver imports).
- [ ] Debug overlay reports FPS and resolve timing.
- [ ] Baseline render approach can display all units distinctly.
- [ ] Optional: headless resolve mode for profiling.
