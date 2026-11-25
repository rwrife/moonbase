# Technical architecture and implementation guide

**Status:** proposed architecture. This repository currently contains planning
documents, not a runnable Godot project. Creation of game project files and
download/execution of the engine were denied in the initial setup environment.
The foundation and validation issues own that remaining work.

## Engine baseline

Use the standard **Godot 4.7.2 stable** build, whose release was verified against
the upstream Godot release API on 2026-11-25. Use GDScript, not C#, for the shared
desktop/Web code path. Pin the same engine and matching export templates in
developer instructions and CI. Reassess the pin before implementation if the
release's platform support or project requirements change.

Start with Compatibility rendering on all platforms. Add an optional Forward+
desktop profile only after the same gameplay scene can run in both profiles.
See [ART_AND_PLATFORMS.md](ART_AND_PLATFORMS.md).

## Proposed repository structure

```text
project.godot                     # Application, main scene, renderer, input actions
export_presets.cfg               # Linux and single-threaded Web presets
scenes/
  main.tscn                     # World, simulation driver, camera, HUD composition
  world/
    lunar_site.tscn             # Surveyed terrain and build grid
    buildings/                 # Replaceable visual scenes for each module
  ui/
    colony_hud.tscn             # Resources, tools, selection, alerts, objective
scripts/
  simulation/
    colony_state.gd            # Serializable state, no rendering dependencies
    utility_network.gd         # Connected-component discovery and evaluation
    economy.gd                 # Funding, upkeep, export accounting
    simulation_driver.gd       # Fixed ticks, pause, speed, signals
  construction/
    building_catalog.gd        # Definitions and validation
    build_controller.gd        # Preview, placement, demolition, selection
  world/
    lunar_site.gd              # Site seed, deposits, world/grid transforms
    isometric_camera.gd        # Pan, rotate, zoom, bounds
  ui/
    colony_hud.gd              # Presentation and command signals
assets/
  models/                      # Original or licensed glTF assets
  materials/
  audio/
  licenses/                    # Provenance and attribution
tests/
  test_simulation.gd           # Headless behavioral tests
  test_scene.gd                # Scene integration smoke tests
docs/                          # Design, roadmap, technical and art direction
.github/
  workflows/                  # Import, test and eventually export checks
  ISSUE_TEMPLATE/             # Focused bug/feature templates
```

This is a target layout, not a requirement to create empty folders or all modules
immediately. Keep the first implementation small. Extract services when actual
behavior requires the boundary; do not create an enterprise framework.

## Data and simulation contract

- Store buildings by stable ID and integer grid cell. Definitions describe
  costs, footprint, placement rules, production, and demand; scenes only display
  those definitions and state.
- Use explicit units and time steps. The first-playable values are abstract
  units/day. Later physical models must migrate or replace them explicitly.
- Tick deterministically with a fixed simulation step, independent of render
  frame rate. Cap catch-up work and keep a documented backlog/skip policy.
- Pause prevents all state advancement; changing speed changes tick frequency,
  not the amount of output or upkeep per simulation day.
- Avoid deep dependencies on Node3D or UI nodes in the simulation so headless
  tests can instantiate it without rendering.
- Commands validate before modifying state. Failed placement must not charge
  credits or emit a success event. Show a precise user-facing rejection.
- Signals communicate changed state and explicit notifications. The HUD does
  not independently calculate production or alter authoritative state.

## Shared utility network: first playable

Each occupied tile, including a utility link, is a node. Orthogonal adjacency
creates an edge. Diagonal placement does not connect. Discover components using
a visited set and queue; rebuild after construction or demolition.

For each component:

1. Sum available power, accounting for the artificial day/night cycle.
2. Sum power demand. If overloaded, shut powered consumers down together.
3. Evaluate powered ice extraction, then compare water supply with demand.
4. Evaluate powered, watered life support; reactors independently produce heat.
5. Check habitat oxygen, water, heat, and power requirements.
6. Mark module status and identify shortages for inspection and HUD warnings.
7. Permit lab/refinery production only when powered and a nonempty crew is safe.

Evaluate from a snapshot rather than dictionary iteration order. Disconnected
components cannot share supply, even if total colony production exceeds total
demand. Colony-wide totals are informational only; display component deficits
so healthy totals cannot mask an isolated habitat.

The first version has no tanks, batteries, pressure, transport capacity, or
separate network layers. The network upgrade issue introduces those features
with explicit priorities, storage accounting, and failure cascades.

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

## Validation and CI plan

After an authorized engine installation, document and execute:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_scene.gd
```

These are **future commands**; there is no `project.godot` or test script yet.
Use a nonzero exit on assertion or load failure and a timeout in CI.

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
