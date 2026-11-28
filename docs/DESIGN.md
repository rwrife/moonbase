# Selene Frontier: project description and game design

## Vision

Build an original, single-player lunar colony strategy game with an isometric
3D presentation and a long-term high-fidelity visual target. Capture the appeal
of commanding a technically believable lunar settlement without copying the
1990 *Moonbase* title, assets, manual, interface, or exact rules.

**Working title:** Selene Frontier. Trademark clearance is pending.
**Engine:** Godot 4, standard GDScript build.
**Primary platform:** desktop. Web is a deliberately lower-cost rendering tier;
native mobile is outside the current implementation and published backlog.
**Audience:** players who enjoy city builders, engineering, and economic strategy.
**Current scope:** foundation and prototype, not a complete AAA production.

## Design pillars

1. **Engineering has consequences.** Connected power, water, oxygen, and thermal
   systems make resilience and redundancy more important than raw expansion.
2. **Terrain drives decisions.** Ice, illumination, mineral quality, radiation
   exposure, and shelter determine viable sites and logistics.
3. **People make the colony.** Safety, workload, privacy, morale, and specialization
   turn infrastructure decisions into human consequences.
4. **A settlement needs a purpose.** Research, contracts, exports, tourism, and a
   funding board provide competing priorities and a meaningful late game.
5. **Readable spectacle.** Cinematic lunar landscapes and detailed modules must
   still communicate service coverage, shortages, and construction clearly.

## Core loop

Survey a site -> land supplies and crew -> establish connected shelter and
utilities -> produce resources -> satisfy research and commercial contracts ->
earn funding and unlock technology -> expand and harden the settlement ->
survive night and hazards -> support larger off-world missions.

The player chooses between a cheap, fragile expansion and a slower, redundant
base. Challenges must be forecast, explainable, and recoverable, not arbitrary
punishment. A failed connection should identify the upstream cause.

## Systems breakdown

| System | Intended design | Implemented first-playable scope |
| --- | --- | --- |
| Construction | Footprints, rotation, terrain constraints, construction jobs, roads, service ports | One-cell modules, adjacency, placement and demolition |
| Power | Solar illumination, fission, storage, load priorities, cable capacity, redundancy | Solar and reactor supply, connected component demand |
| Water | Ice extraction, purification, tanks, recycling, leakage | Powered extraction on ice, life-support demand |
| Oxygen | Electrolysis, recycling, pressure zones, emergency reserves | Powered/watered life support, habitat demand |
| Thermal | Heat production, transport, radiators, insulation, lunar night | Heat supply/demand in the shared network |
| Crew | Roles, shifts, health, morale, workload, recreation, rescue | Habitat crew count and aggregate morale |
| Economy | Imports, export contracts, market signals, upkeep, board commitments | Credits, upkeep, automatic refinery exports and periodic grants |
| Research | Branching technologies, science requirements, field trials | Science accumulation and founding objective only |
| Logistics | Landing windows, payload mass, depots, rovers, routes, stockpiles | Starter landing pad, constructible extra pads, recurring +4 t supply landings every 6 days per pad |
| Terrain | Polar ice, sunlit ridges, lava tubes, minerals, survey uncertainty | Deformable heightfield, bulldozer grading, immovable landmarks, ice strip |
| Hazards | Solar flares, impacts, dust, failures, warning and repair | Predictable artificial night cycle; shared damage/repair visual states ready for #10 |
| Modes | Tutorial campaign, authored scenarios, configurable sandbox | One founding scenario with continued play |
| Presentation | Production assets, audio, animation, accessible overlays | Original procedural placeholder geometry, lander visits, shared structure states, and HUD |

Utility quantities and building costs below are fictional balance values, not
NASA engineering predictions or verified original-game numbers. The
prototype uses one common adjacency graph, not four independently routed
pipes/cables. The runnable foundation was added after the owner explicitly
approved the previously blocked project-file writes and engine execution.

## First playable: founding charter

Start with a small supplied outpost, a starter landing pad with an approaching
supply lander, and a construction grant. Add reliable night-time generation,
science, and exports while maintaining safe habitats.
The completion condition is day 30 or later, at least 30 science, at least
40 export units, all crew supplied, and morale of at least 65.

One day advances every four seconds at 1x; pause, 2x, and 4x are available.
Days 1-24 (80%) of each artificial 30-day cycle are sunlit and days 25-30 (20%)
are dark, with smooth dusk and dawn lighting transitions. There is no claim that this
is a faithful lunar illumination model. The initial failure model produces
shortages, morale loss, and debt rather than permanent death or a hard game-over.

### Prototype building specification

All buildings occupy one tile. Orthogonal adjacency connects modules;
utility links bridge gaps. Construction is instantaneous and levels its own pad.
Bulldozing rough regolith into a pad costs 15 credits. Landmark craters and
boulders from the site survey are immovable and block construction. Vehicles that
drive out of a home garage and leave permanent tracks are planned in #16.

| Building | Credits | Upkeep/day | Supply or demand |
| --- | ---: | ---: | --- |
| Utility link | 20 | 0 | Carries the shared utility network |
| Habitat | 250 | 2 | 8 crew; uses 3 power, 2 water, 2 oxygen, 2 heat |
| Solar array | 160 | 1 | 12 power in sunlight, 0 at night |
| Fission reactor | 600 | 6 | 24 power, 12 heat; no fuel model yet |
| Ice extractor | 200 | 2 | Uses 3 power; produces 10 water; ice-only placement |
| Life support | 220 | 2 | Uses 3 power and 2 water; produces 12 oxygen and 4 heat |
| Science lab | 300 | 3 | Uses 4 power; 1 science/day with safe crew |
| Regolith refinery | 280 | 3 | Uses 5 power; 2 export units/day at 12 credits/unit |
| Landing pad | 240 | 0 | Self-powered beacon; receives +4 t supplies every 6 days per operational pad |

### Supplies and recurring landings

- **Supplies (`t`)** represent the colony's stockpile of Earth-delivered spares,
  consumables, and general cargo reserves. Supplies are tracked separately from
  **Credits** and piped local **Utilities** (power, water, oxygen, heat), and
  form the logistics stockpile that later repair consumables (#10), cargo depots
  (#22), and contract/import logistics (#8) will consume and extend.
- **Starter pad:** every new game and restart includes one operational landing
  pad on a graded, unblocked site near the starter outpost (`0, -2`) with its
  first SELENE cargo lander already on approach (first `+4 t` delivery completes
  in `2.2` days, then repeats every `6.0` days).
- **Scaling with extra pads:** every operational landing pad runs an independent
  `6.0`-day delivery schedule yielding `+4 t` once its lander visibly touches
  down and finishes offloading. Building additional landing pads increases total
  supply throughput linearly (`N` operational pads deliver `4 × N t` per 6 days)
  rather than splitting a fixed colony-wide allocation.
- **Lifecycle safety:** supplies are credited strictly once per completed
  offload—never early, never on animation frames, and never while paused.
  Demolishing or damaging a pad before offload completes cancels that visit
  without crediting cargo; demolishing during departure preserves the already-credited
  shipment without future or duplicate deliveries.

All consumers in an overloaded component shut down together. This is a
transparent prototype rule, not the final load-priority model. Production
requires a nonempty, fully supplied crew. Demolition returns 25% of build cost.
Funding arrives each 30-day cycle: 300 credits plus 2 per science, capped at
300 additional credits.

## Beyond the prototype

Research should enable alternate solutions, not simply bigger numbers.
Contracts should force choices between science, safety, and commercial growth.
Tourism should compete for habitat capacity and demand comfort rather than
being a passive income multiplier. Late-game objectives can include a permanent
research settlement, a cislunar fuel depot, and Mars mission support.

Campaign scenarios introduce one system at a time. Sandbox exposes difficulty,
funding, hazard frequency, and site seed without changing the simulation model.
Competing agencies initially act through contracts and market events, not
multiplayer or fully simulated rival cities.

## Non-goals for initial setup

No multiplayer, procedural universe, first-person exploration, combat,
real orbital mechanics, production voice acting, or claim of flight-grade
engineering accuracy. AAA presentation requires a funded asset and optimization
pipeline; engine selection alone cannot deliver it.

## Source and ownership policy

See [SOURCES.md](SOURCES.md) for the user-provided historical references and
unverified details. Historical facts and design proposals are separate.
Use original or appropriately licensed assets with provenance. Do not import
original-game assets, branding, screenshots as textures, manual text, or code.
A contributor licensing policy and title clearance are release prerequisites.
