# Selene Frontier: project description and game design

## Vision

Build an original, single-player lunar colony strategy game with an isometric
3D presentation and a long-term high-fidelity visual target. Capture the appeal
of commanding a technically believable lunar settlement without copying the
1990 *Moonbase* title, assets, manual, interface, or exact rules.

**Working title:** Selene Frontier. Trademark clearance is pending.
**Engine:** Godot 4, standard GDScript build.
**Primary platform:** desktop. Web is a deliberately lower-cost rendering tier;
native mobile is a later feasibility milestone.
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

| System | Intended design | Planned first-playable scope |
| --- | --- | --- |
| Construction | Footprints, rotation, terrain constraints, construction jobs, roads, service ports | One-cell modules, adjacency, placement and demolition |
| Power | Solar illumination, fission, storage, load priorities, cable capacity, redundancy | Solar and reactor supply, connected component demand |
| Water | Ice extraction, purification, tanks, recycling, leakage | Powered extraction on ice, life-support demand |
| Oxygen | Electrolysis, recycling, pressure zones, emergency reserves | Powered/watered life support, habitat demand |
| Thermal | Heat production, transport, radiators, insulation, lunar night | Heat supply/demand in the shared network |
| Crew | Roles, shifts, health, morale, workload, recreation, rescue | Habitat crew count and aggregate morale |
| Economy | Imports, export contracts, market signals, upkeep, board commitments | Credits, upkeep, automatic refinery exports and periodic grants |
| Research | Branching technologies, science requirements, field trials | Science accumulation and founding objective only |
| Logistics | Landing windows, payload mass, depots, rovers, routes, stockpiles | Deferred |
| Terrain | Polar ice, sunlit ridges, lava tubes, minerals, survey uncertainty | Fixed surveyed grid and ice strip |
| Hazards | Solar flares, impacts, dust, failures, warning and repair | Predictable artificial night cycle only |
| Modes | Tutorial campaign, authored scenarios, configurable sandbox | One founding scenario with continued play |
| Presentation | Production assets, audio, animation, accessible overlays | Original procedural placeholder geometry and HUD |

Utility quantities and building costs below are fictional balance values, not
NASA engineering predictions or verified original-game numbers. The planned
prototype uses one common adjacency graph, not four independently routed
pipes/cables. **No game project or playable prototype was created in this setup:
project-file writes and engine installation were denied by the environment.**

## Planned first playable: founding charter

Start with a small supplied outpost and a construction grant. Add reliable
night-time generation, science, and exports while maintaining safe habitats.
The completion condition is day 30 or later, at least 30 science, at least
40 export units, all crew supplied, and morale of at least 65.

One day advances per second at 1x; pause, 2x, and 4x should be available.
Days 21-30 of each artificial 30-day cycle are dark. There is no claim that this
is a faithful lunar illumination model. The initial failure model should produce
shortages, morale loss, and debt rather than permanent death or a hard game-over.

### Proposed prototype building specification

All buildings occupy one tile. Orthogonal adjacency connects modules;
utility links bridge gaps. Construction is instantaneous.

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
