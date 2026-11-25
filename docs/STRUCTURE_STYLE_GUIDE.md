# Structure style guide

How new colony structures should look, move, and plug into the game. The
reference implementation is `scripts/lunar_module.gd` with
`shaders/module_surface.gdshader`; follow it unless an issue explicitly
changes this guide.

## Design intent

Structures are **original, spacecraft-inspired hardware**: plausible lunar
surface equipment you might see in a NASA/ESA concept render, not sci-fi
buildings. Every structure must answer "what does this do?" from its silhouette
and its motion, and must still read clearly at gameplay zoom.

- Inspiration, not imitation. Do not use NASA, agency, or contractor logos,
  mission names, flags, or real hardware copied part-for-part. Markings use the
  fictional `SELENE` brand plus a short function code (`HAB-01`, `O2 / ECLSS`).
- Vacuum rules. No smoke, steam plumes, wind sway, fire, or atmospheric glow.
  No exposed glowing reactor cores. Light comes from the sun, windows, lamps,
  and small service lights only.
- Function first. Visible parts should correspond to a role: tanks store,
  radiators reject heat, drills dig, antennas communicate, and hatches give
  crew access. Avoid decorative greebles that mean nothing.

## Footprint, scale and orientation

| Rule | Value |
| --- | --- |
| Grid cell | `LunarSite.CELL_SIZE` = 2.3 units; all geometry stays within ±1.15 on X/Z (tested) |
| Foundation | Dark equipment skid ~2.18 × 0.13 × 2.18 with four leveling feet and a silver frame |
| Utility sockets | Gold-quilted ports on all four sides at ±1.07, y ≈ 0.32 (orthogonal adjacency) |
| Height | Production/crew structures ≥ 1.7 units tall (tested); links stay low |
| Front | +Z faces the default camera: status lamp, hatch, labels and main panel go here |
| Pivot | Model origin is the cell center at pad height; `LunarSite` positions it |

Multi-cell structures (landing pads, large radiators) are not supported by the
simulation yet. Do not fake them by spilling geometry into neighboring cells.
They need a footprint change in `ColonySimulation` first.

## Materials and color

Use the shared materials built in `LunarModule.build()` rather than new
one-off colors:

| Material | Use |
| --- | --- |
| `white` | Pressure hulls, tanks, equipment enclosures (dominant surface) |
| `silver` | Frames, struts, rings, bolts, piping, rails |
| `dark` | Skids, radiator panels, drill shafts, display bezels |
| `gold` (quilt shader) | Thermal blankets/MLI on roofs, sides and sockets |
| `blue` (cell shader) | Photovoltaic surfaces only |
| `accent` | The building's catalog `color`, used sparingly for stripes, valves and drive parts |
| `glass` | Windows and light lenses; emission is driven by active state |
| `lit` / `unlit` | Telemetry lamps |

The catalog color is an identification accent, not a body paint. Aim for
mostly white/silver/gold with one accent so the colony reads as one program.

## Detail checklist

A new structure should include, scaled to its role:

- Equipment skid, feet and four utility sockets (from `_foundation`).
- One clear primary form: a pressure cylinder, tank cluster, truss mast,
  radiator wing, or enclosure.
- Secondary structure: struts or braces (`_strut`), banding rings, and plumbing
  runs between components.
- Service affordances: a hatch or access panel (`_service_panel`), valves
  (`_valve`), and a bolted equipment box (`_equipment_box`).
- A `SELENE` label with a function code on the +Z face (`_label`).
- A telemetry lamp strip (`_lamp_strip`), the `OperatingStatus` indicator, and
  the shared service light.

Use 32 radial segments for visible cylinders. Prefer reusing helpers over new
primitive code so detail density stays consistent.

## Operating state and animation

- `set_active(bool)` reflects the authoritative simulation state. Lamps,
  window emission, the service light and the status indicator must follow it.
- `advance(delta)` runs only when active. Offline mechanisms freeze in place;
  they do not snap or reset.
- `delta` comes from the game clock, so pause, 2×/4× speed and the suspend
  clamp apply automatically. Never use `_process` or wall-clock time in a module.
- Each producing structure gets one readable `mechanism` motion that
  communicates its function. Examples: a rotating drill, a pump stroke, slow
  solar tracking, antenna scanning, or a conveyor drum. Keep motion bounded and
  slow enough to read; avoid constant fast spinning unless the part is a drill.
- Animation is cosmetic. It must never produce or consume resources.
- Night and offline states must still be readable through silhouette and the
  red status indicator. Do not rely on lighting alone.

## Testing and review

For each new structure:

1. Extend `tests/test_scene.gd`. Check the footprint bounds, minimum height,
   active motion, frozen offline/pause behavior, and lamp/light state.
2. Add a capture to `tests/capture_views.gd` if the structure appears in the
   default scenario, and review it under Xvfb at gameplay zoom in day and night.
3. Check silhouette readability against neighbors from all four camera orbits.
4. Record any imported asset's source and license per the provenance rules in
   [CONTRIBUTING.md](../CONTRIBUTING.md). Procedural models need no record.

## Replacing procedural models

Imported glTF models may replace procedural geometry later (#14). They must
keep the `LunarModule` interface (`build`, `set_active`, `advance`, `status`,
`lamps`, `mechanism`) and the footprint, socket and front-facing rules above,
so the simulation and tests do not change.
