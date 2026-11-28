# Technical architecture and implementation guide

**Status:** runnable first-playable foundation. The initial permission block was
resolved by explicit owner approval. The project separates authoritative
simulation from procedural visuals, camera, construction input, and HUD.

## Engine baseline

Use the standard **Godot 4.7.2 stable** build, whose release was verified against
the upstream Godot release API on 2026-11-25. Use GDScript, not C#, for the shared
desktop/Web code path. Pin the same engine and matching export templates in
developer instructions and CI. Reassess the pin before implementation if the
release's platform support or project requirements change.

Start with Compatibility rendering on all platforms. Add an optional Forward+
desktop profile only after the same gameplay scene can run in both profiles.
See [ART_AND_PLATFORMS.md](ART_AND_PLATFORMS.md).

## Current repository structure

```text
project.godot                     # Application, main scene, renderer, input actions
export_presets.cfg               # Linux and single-threaded Web presets
scenes/main.tscn                 # Composition entry point
scripts/
  main.gd                       # Fixed clock, commands and component wiring
  building_catalog.gd           # Building definitions
  colony_simulation.gd          # State, validation, networks, deliveries, economy, charter and state export/import
  lunar_site.gd                 # Visual world: terrain meshes, rocks, boulders, modules, landers, lighting
  lunar_module.gd               # Spacecraft-style procedural hardware and shared build/damage/repair/active states
  supply_lander.gd              # Original SELENE supply lander driven by authoritative delivery state
  lunar_terrain.gd              # CPU heightfield, craters, grading and GPU textures
  site_survey.gd                # Immovable landmark craters/boulders and blocked cells
shaders/
  regolith.gdshader             # Displaced regolith, self-shadowing, grading and build overlay
  module_surface.gdshader       # Quilted thermal blankets and photovoltaic cell detail
  isometric_camera.gd           # Pan, orbit and zoom
  colony_hud.gd                 # Presentation and command signals
tests/
  test_simulation.gd           # Headless behavioral tests
  test_scene.gd                # Scene integration smoke tests
  capture_views.gd             # Look-development screenshot capture (needs a display)
docs/                          # Design, roadmap, technical and art direction
.github/
  workflows/                  # Pinned import and headless test checks
  ISSUE_TEMPLATE/             # Focused bug/feature templates
```

The first implementation is intentionally small; it does not contain empty
framework folders. Extract separate utility/economy/crew services when future
behavior warrants the boundary. Imported production assets will get dedicated
scenes and provenance records rather than coupling them to simulation state.
Commit script `.gd.uid` sidecars; ignore `.godot/` and generated build outputs.

## Data and simulation contract

- Store buildings by stable ID and integer grid cell. Definitions describe
  costs, footprint, placement rules, production, and demand; scenes only display
  those definitions and state.
- Use explicit units and time steps. The first-playable values are abstract
  units/day. Later physical models must migrate or replace them explicitly.
- Tick deterministically with a fixed one-day simulation step, independent of
  render frame rate. The driver clamps each frame's elapsed time to 250 ms before
  applying speed. Longer suspend/background gaps are discarded, not replayed,
  so returning to a tab does not suddenly run many unattended days.
- Pause prevents all state advancement; changing speed changes tick frequency,
  not the amount of output or upkeep per simulation day.
- `LunarSite` passes each authoritative building's active state to `LunarModule`.
  The game clock advances cosmetic mechanisms with the same pause, speed, and
  suspend-gap clamp as simulation time; animations never produce resources.
- Avoid deep dependencies on Node3D or UI nodes in the simulation so headless
  tests can instantiate it without rendering.
- Commands validate before modifying state. Failed placement must not charge
  credits or emit a success event. Show a precise user-facing rejection.
- Signals communicate changed state and explicit notifications. The HUD does
  not independently calculate production or alter authoritative state.

## Standardized Power and Service networks (Phase 1A)

Every building declares local `service_ports` and `power_ports` in `BuildingCatalog`, rotated by its integer `facing` (`0..3` in 90° steps around `+Y`). Two orthogonally adjacent cells connect only when matching ports face each other. Diagonal placement never connects.

`ColonySimulation.recalculate()` evaluates two deterministic snapshot-based graphs:

1. **Power networks (`power_networks`):** traverse mated `power_ports` (including power pass-through across mated Service Connectors) and elevated `power_lines` tiles (which can coexist on top of `tunnel` tiles as crossings). Sum operational power supply (accounting for lunar night) against power demand; overloaded electrical components shut consumers down together.
2. **Service networks (`service_networks`):** traverse strictly mated `service_ports`, `tunnel` corridors, and `support_hub` 4-way adapters (`power_lines` never carry Service). Within each service component:
   - Evaluate powered ice extraction, then compare water supply with demand.
   - Evaluate powered, watered life support; reactors in the service component also contribute heat.
   - Check habitat power, water, oxygen, and heat requirements to compute local `safe_crew`.
   - Permit crew-requiring production (`lab`, `mine`) only when powered AND sharing a service corridor with safe crew.

Disconnected components cannot share supply, even when colony-wide totals show a surplus. Storage tanks, batteries, line capacities, and load-priority shedding build on these two graphs in `#6`.

## Construction and camera

Project the mouse ray onto the build plane and map it to integer grid cells.
Validate map bounds, occupancy, resource requirements, and credits before
placement. Use green/red preview feedback plus text, not color alone.
UI-handled input must not reach world construction. Keep placement, inspection,
and demolition as explicit modes with a visible cancel action.

Use an orthographic Camera3D on a pitched orbit rig. Provide bounded WASD/arrow
pan, Q/E rotation, wheel zoom, and UI equivalents. Keep grid transforms unchanged
when rotating the camera. Map actions through Godot's InputMap, not raw key codes,
so rebinding can be introduced without rewriting controllers.

## Persistence and compatibility

Saving is deferred to its issue, but do not serialize scene nodes as game state.
Plan a versioned data format containing seed, buildings, simulation time,
resources, economy, research, crew, scenario flags, and RNG state.
Never silently reset corrupt or unsupported saves. Preserve the file and show
an actionable error. Web storage/persistence must be qualified independently.

## Validation and CI

On a fresh checkout, execute:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_scene.gd
```

Both test scripts return nonzero on failed checks. CI pins the engine version,
verifies its SHA-512 release checksum, rejects import errors, runs both scripts,
and has a bounded job timeout. Export/browser/performance qualification remains
in the validation issue rather than being implied by headless test success.

Behavioral coverage should include:

- Rejected occupancy, out-of-bounds, unaffordable, and ice-only placements without
  state mutation.
- Orthogonal connection, diagonal isolation, link removal, and component merge.
- Power loss cascading to water, oxygen, heat, habitat safety, and morale.
- Night transitions at days 21 and 31; reliable generation preserves services.
- Output/upkeep/funding accounting and zero production without safe crew.
- Pause and speed invariance; identical commands produce identical state.
- An achievable founding charter, including exact thresholds and restart reset.
- Scene load, camera/HUD wiring, UI input isolation, and placement feedback.

Then export Linux and Web using matching templates. Serve Web over HTTP and
exercise actual browser interaction, not only export completion. Qualify
renderer behavior and inspect engine/browser errors. Record results; do not
claim runtime success from static file checks.

## Contributor workflow

Take an issue with clear acceptance criteria; keep changes scoped to that
milestone. Update directly related documents when behavior changes. Future
development uses reviewable pull requests unless the owner gives a task-specific
publication instruction. The owner's direct-to-main instruction applies to this
initial setup; it is not an assumed permanent contribution policy.

## Lunar terrain

- `LunarTerrain` builds a 128 x 128 unit heightfield (1024^2 texels, 0.125 units each):
  macro relief from `FastNoiseLite`, then roughly 2,800 stamped craters. Craters follow
  a power-law size distribution, and most are degraded (soft bowls, no halo). A few are
  fresh, with sharp rims and rayed bright ejecta stored in an albedo channel.
- Heights upload as an `RH` texture, displacing a 512-subdivision plane in
  `regolith.gdshader`. The shader derives normals from the heightfield, adds rotated
  tiling micro-crater normals, and ray-marches the heightfield toward the sun for
  crisp terrain self-shadows (there is no atmosphere, so there is no haze). It uses
  a Lommel-Seeliger/Lambert regolith BRDF.
- Rocks and pebbles are MultiMesh instances of procedurally chipped meshes,
  clustered around fresh crater rims. `LunarSite.cell_rocks` maps cells to the
  instances that grading hides. Large boulders are separate meshes.
- `SiteSurvey` defines immovable landmarks. `ColonySimulation.blocked` rejects
  construction and bulldozing there.
- Grading: `ColonySimulation.graded` is authoritative and kept in grading order.
  `LunarSite.synchronize` flattens newly graded cells with `LunarTerrain.grade()`,
  which levels the cell to its mean height (blended with adjacent pads). It feathers
  into rough neighbours with a small spoil berm, marks the graded mask, and uploads
  textures. A reset restores the base heightfield and rocks.
- Buildings, the preview and cursor picking use the pad or terrain height
  (`LunarSite.surface_position`, iterative `ColonyGame.ground_point`).
