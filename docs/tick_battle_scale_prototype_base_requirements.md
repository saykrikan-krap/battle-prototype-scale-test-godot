# Tick-Based Battle Scale Prototype — Base Requirements (Tech-Stack Agnostic)

## Purpose

This is a **throwaway prototype** whose only goal is to answer a practical question:

> Can a candidate engine/runtime run a **deterministic**, **tick-based** battle simulation and replay at **~2000 total units** (≈1000 per side) at a performance level that suggests the approach is viable?

This document is derived from the earlier “tick-based battle prototype plan” (resolver/replayer split, event-log-driven replay, deterministic tick scheduler), but updated for **desktop client apps** and **scale testing**.

---

## Scope

### In-scope
- Deterministic resolver producing an authoritative event log.
- Replayer that renders **only** from the event log (no importing resolver logic).
- A single hardcoded “Scale Test v1” scenario with ~1000 units per side.
- Basic AI sufficient to create movement, melee, and ranged pressure.
- Basic rendering sufficient to differentiate unit types at a glance.
- Instrumentation to measure “is this viable” (FPS, ticks/sec, time-to-resolve, memory).

### Explicit non-goals
- No audio, no UI polish, no networking.
- No advanced tactics, morale, or flanking beyond the formation movement rules in the companion pathing guide.
- No sophisticated balance.
- Heavy optimization is **not required** yet, but the design must avoid obviously catastrophic patterns (e.g., O(units × grid) BFS per tick).

---

## Success Criteria (What “viable” means)

The prototype should produce **real measurements** for two workloads:

1) **Resolve (simulation) workload**
- Measure: wall-clock time to resolve the battle to completion (or time limit), plus average **ticks/sec** during resolution.
- “Concerning” if resolution takes **many minutes** on a typical dev machine.
- “Failing” if resolution takes **~1 hour** or more (suggests fundamental approach problems).

2) **Replay (rendering) workload**
- Measure: **FPS** during replay at 1× speed, plus frame time breakdown if available.
- “Acceptable prototype” even if FPS is ~10 in worst moments.
- “Failing” if FPS is <1 in normal replay conditions.

> These thresholds are intentionally pragmatic rather than strict; the point is to separate “needs optimization” from “likely impossible/incorrect approach.”

---

## Core Design: Resolver / Replayer Split

### Resolver
- Pure simulation logic.
- Input: `BattleInput` (grid, constants, seed, and initial units).
- Output: `BattleResult` + `EventLog[]`.
- Must be able to run without rendering (ideally on a background worker/thread).

### Replayer
- Imports **schema/types only**.
- Consumes only the event log + playback controls to render.
- Must not call into simulation logic.

This separation is required so we can:
- validate determinism (log is authoritative),
- swap tech stacks without changing core assumptions,
- profile sim vs render independently.

---

## Determinism Requirements

- All randomness must come from a **seeded PRNG** controlled by the resolver.
- Stable ordering for same-tick actions.
- Events are ordered by `(tick, seq)` where:
  - `tick` = simulation tick
  - `seq` = integer ordering key (source unit id, or 0 for non-unit events)
- For events with identical `(tick, seq)`, log order is authoritative.

---

## Constants & Rules

### Combatant Types & Sizes

**Keep existing units**, and add:
- **Heavy Infantry**
- **Elite Infantry**
- **Heavy Cavalry**

Sizes follow the existing base types:

| Unit Type        | Base Type | Size |
|------------------|----------:|-----:|
| Infantry         | Infantry  | 2 |
| Heavy Infantry   | Infantry  | 2 |
| Elite Infantry   | Infantry  | 2 |
| Archer           | Archer    | 2 |
| Mage             | Mage      | 2 |
| Cavalry          | Cavalry   | 3 |
| Heavy Cavalry    | Cavalry   | 3 |

### Tile Constraints (unchanged)
- Max combatants per tile: **4**
- Max total size per tile: **10**
- Tiles are single-side only (no mixed Red/Blue occupancy)
- Constraints apply to all units currently on the tile

### Battle Grid (Scale Test v1)

Use:

- Grid size: **80 × 40**
- Deployment width: **15** columns per side
- Deployment height: **32** rows, centered vertically (4-tile margins top/bottom)
- Deployment columns:
  - **Red**: columns **0–14**
  - **Blue**: columns **65–79**
  - Neutral zone: columns **15–64**
  
This yields **15 × 32** deployment tiles per side.

### Tick Rate (Replay)
- Default: **20 ticks/sec**
- Options: 10 / 20 / 40
- Controls: Play / Pause / Step tick / Speed multiplier

### Action Costs (ticks)

Move is 1 tile per action. Minimum cost is always ≥ 1 tick.

| Unit Type        | Move | Attack / Spell | Wait | Notes |
|------------------|-----:|---------------:|-----:|------|
| Infantry         | 6 | 12 (melee) | 1 | baseline |
| Heavy Infantry   | 7 | 13 (melee) | 1 | slower |
| Elite Infantry   | 6 | 11 (melee) | 1 | faster attack |
| Archer           | 6 | 14 (arrow) | 1 | ranged |
| Cavalry          | 4 | 12 (melee) | 1 | fast move |
| Heavy Cavalry    | 5 | 13 (melee) | 1 | heavier |
| Mage             | 6 | 16 (fireball) | 1 | AoE |

### Terrain Costs (v1)

Terrain applies a movement multiplier to the base move cost:
- Grassland: **1×**
- Trees: **2×**
- Water: **impassable** (cannot enter)

Special case:
- Cavalry (including Heavy Cavalry) **lose their speed advantage in trees** and use the Infantry base move cost before applying the 2× multiplier.
- Terrain should be part of `BattleInput` and emitted in the event log at tick 0 so the replayer can render it.

### Melee Hit Chances

Keep “one-hit removal,” but allow melee hit chance to vary by unit type:

| Unit Type        | Melee Hit Chance |
|------------------|-----------------:|
| Infantry         | 50% |
| Heavy Infantry   | 55% |
| Elite Infantry   | 60% |
| Cavalry          | 50% |
| Heavy Cavalry    | 55% |

### Ranges & Projectiles (unchanged)
- Distance metric: **Manhattan**
- Archer range: **10**
- Mage fireball range: **20**
- Minimum ranged distance: **1** (cannot target own tile)

Projectile speed:
- Arrow: **2 ticks per tile**
- Fireball: **3 ticks per tile**

Impact tick:
```
impactTick = fireTick + (speed * distance)
```

### Damage & Removal (unchanged)
- No HP.
- If damaged → unit removed immediately.
- Arrow: on impact, removes a random enemy on the impacted tile (if any).
- Fireball: on impact, removes **all units** on the impacted tile.
- Fireball affects enemies only (prototype assumption).

### Target Movement Rule (unchanged)
- Projectile always travels to the original target tile.
- Impact checks current occupants of that tile.

### Same-tick Ordering (unchanged)
1. Projectile impacts
2. Unit actions (stable by ID)

If movement fails → unit waits 1 tick.

### End Conditions
- A side loses when it has **0 units remaining**
- Time limit: **5000 ticks** (configurable constant)
- If reached → Draw

---

## Scale Test v1 Scenario (Hardcoded)

### Army Composition (per side)
- Infantry: **150**
- Heavy Infantry: **150**
- Elite Infantry: **150**
- Cavalry: **150**
- Heavy Cavalry: **150**
- Archers: **200**
- Mages: **50**

Total: **1000 units per side** (2000 total).

### Squads & Formations (v1)
- Squads are used for placement **and** formation-aware movement (see companion pathing guide).
- Max squad size: **50**.
- Each squad has:
  - `id`
  - `side`
  - `formation` (currently **Square** only)
- For Scale Test v1, squads are created per unit type (homogeneous squads), but the data model does not require that.

**Square formation rule**
- Pack squad units into tiles respecting tile constraints (max units + max total size).
- Arrange the resulting tiles into the smallest possible square-ish footprint (row-major fill).

### Initial Placement (Deterministic, Constraint-Safe)

Hardcode a deterministic placement algorithm instead of a placement UI.

**Current approach**
- Use the deployment region for each side (15 × 32 tiles).
- Build squads from the roster in deterministic order.
- For each squad:
  - Pack units into tiles with size/count constraints.
  - Place tiles in a square formation footprint.
- Place squad footprints into a deterministic block grid within the deployment zone to avoid overlap.
  - Block size equals the largest squad footprint for the side.
  - Red squads are front-aligned toward the neutral zone; Blue squads are front-aligned toward the neutral zone.

**Front line definition**
- Red front is toward increasing X (toward the neutral zone).
- Blue front is toward decreasing X.

This guarantees:
- Equal armies
- Constraint compliance
- Very high sprite variety in view from tick 0
- Deterministic initial conditions

---

## AI Rules

AI is intentionally simple, but must be deterministic and avoid pathological compute patterns.

### Common definitions
- “Enemy in melee range” = any enemy tile at Manhattan distance **1**.
- “Nearest enemy tile” = smallest Manhattan distance; ties broken deterministically.

### Infantry / Heavy Infantry / Elite Infantry
1. If any enemy in melee range → melee attack the nearest enemy tile.
2. Else move one tile toward nearest enemy tile.
3. Else wait.

### Cavalry / Heavy Cavalry
Same as infantry logic, but using their move/attack costs.

### Archer
1. Shoot nearest enemy tile in range (≤ 10).
2. Else move toward nearest enemy tile.
3. Else wait.

### Mage
1. If any enemy tiles in range (≤ 20), choose the tile in range with **most enemies** (ties broken deterministically), fireball.
2. Else move toward nearest enemy tile.
3. Else wait.

---

## Projectile Resolution

- Projectiles can hit any units on the target tile at impact (friendly fire enabled).
- Arrow impact removes one random unit on the tile (if any).
- Fireball impact removes all units on the tile (if any).

---

## Battle End Conditions

- Battle ends when a side has zero units, the time limit is reached, or stall detection triggers a draw.
- If the battle would end while projectiles are in flight, continue advancing ticks until all projectiles resolve. Units do not act during this cleanup phase.

---

## Movement & Pathing (Scale-Friendly Requirement)

The original small-scale prototype could do BFS per unit. At 2000 units, that can become a bottleneck.
The current implementation uses a **strategic distance field (multi-source Dijkstra)** plus **formation-aware movement**.

Minimum requirement:
- Movement decision must be **bounded and predictable** per tick.

Required approach (see `tick_battle_scale_prototype_squad_pathing_companion.md` for full detail):
- Build a cached **distance field (multi-source Dijkstra)** per side and unit size, seeded from all enemy-occupied tiles.
  - Terrain + objectives only.
  - Do **not** include friendly occupancy as a Dijkstra cost.
- Rebuild fields on a cadence:
  - when dirty (terrain/occupancy changes) **and** past `REBUILD_INTERVAL_TICKS`,
  - or when `MAX_STALE_TICKS` is reached (safety).
- Allow a stale guard to force a rebuild if units repeatedly fail to improve their goal distance.
- If all edge costs are uniform, a BFS fast path is acceptable (equivalent to Dijkstra).
- Each squad updates a virtual **anchor** that follows the field.
- Each unit evaluates `{stay, N, E, S, W}` and chooses:
  - near-best **goal progress** (within slack), then
  - best **formation adherence** (distance to desired slot).
- Apply movement in **two phases** (intent then conflict resolution) so same-tick units do not treat each other as static blockers.
- Apply detach/reattach rules for stragglers to avoid slow units stalling the whole squad.

Passability rules (per unit size):
- Tile is passable if:
  - empty, or occupied by same side,
  - and adding the unit would not exceed max count or max size.

---

## Data Contracts

### BattleInput
- `gridWidth`, `gridHeight`
- Tile limits: `maxUnitsPerTile`, `maxTotalSizePerTile`
- `seed`
- `timeLimitTicks`
- `units[]`:
  - `id` (int)
  - `side` (Red/Blue)
  - `type`
  - `size`
  - `pos` (x, y)
  - `nextAvailableTick` (optional; default 0)
- `squads[]`:
  - `id`
  - `side`
  - `formation`
- `unitSquadIds[]` (parallel to `units[]`)
- `unitSlotDx[]`, `unitSlotDy[]` (canonical formation slot offsets, parallel to `units[]`)

### Event Log
Each event:
- `tick`
- `seq` (ordering key)
- `type`
- `payload` (typed per event type)

Minimum event types (same as the earlier prototype):
- `BattleInit`
- `UnitSpawned`
- `UnitMoved`
- `MeleeAttackResolved`
- `ProjectileFired`
- `ProjectileImpacted`
- `UnitRemoved`
- `BattleEnded`

### BattleResult
- `winner` (Red/Blue/Draw)
- `ticksElapsed`
- `unitsRemainingBySide`
- Optional: summary counts per unit type

---

## UI Requirements (Minimum)

### Resolution UI
- “Resolve battle” button (or auto-start)
- “Resolving…” progress indicator
- Keep UI responsive while resolving (thread/process separation if available)

### Replay UI
- Play / Pause / Step
- Speed options (10/20/40 ticks/sec)
- Current tick display
- Winner + survivors display

### Rendering Requirements
- Grid visible (simple lines or tile backgrounds)
- Units visible and type-distinguishable
- Projectiles visible (simple markers)
- Movement animation (interpolate between tiles over 1 tick or a fixed fraction of move action)

---

## Instrumentation & Validation

Must-have overlays/logging:
- Current FPS (replay)
- Current tick
- Units alive per side
- Events count
- Resolution wall-clock time
- Avg ticks/sec during resolution (or ms/tick)

Invariant checks:
- Tile constraints never violated
- Removed units never act again
- Deterministic re-run: same `BattleInput` + seed produces identical `EventLog` hash

Stall detection (optional but recommended):
- If no units moved/removed/projectiles for N ticks, end as Draw with reason “Stalled”.

---

## Tech Stack Suitability Checklist

A tech stack is “acceptable” if it can:
- run deterministic tick simulation with a seeded PRNG,
- keep simulation and rendering separate,
- handle ~2000 units without extreme per-entity object overhead,
- render 2000 sprites/markers at ≥ ~10 FPS in replay,
- run the resolver in a background worker/thread (or otherwise keep UI responsive).

If any of these cannot be met, the stack should be flagged as “not appropriate” for this scale prototype.

---

## Task Breakdown

1. **Schema**
   - Define `BattleInput`, `Event`, `BattleResult`
2. **Resolver**
   - Tick scheduler (units & projectiles indexed by tick)
   - Distance field movement
   - Actions & event emission
3. **Hardcoded Scenario**
   - Deterministic placement + seed
4. **Replay**
   - Playback clock + controls
   - Renderer
5. **Instrumentation**
   - FPS + sim timing + log hash
