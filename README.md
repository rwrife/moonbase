# Selene Frontier

An original lunar-colony strategy game inspired by the engineering and economy
of the 1990 *Moonbase*. Built in Godot 4 with GDScript and an orthographic
isometric 3D camera. **Selene Frontier is a working title, not a cleared trademark.**

## Current milestone

The playable foundation includes a procedural, deformable lunar surface
(heightfield regolith with craters, rocks, pebbles, immovable landmark craters and
boulders, and bulldozer grading), nine building types (including a starter landing
pad with recurring SELENE supply lander visits delivering +4 t supplies every
6 days per operational pad), grid construction and demolition, local utility
networks, lunar night, crew morale, upkeep, funding, science, exports, and a
founding charter objective. Original procedural buildings feature spacecraft-style
pressure hulls, thermal insulation, plumbing, radiator fins, solar cells,
status-driven operating animations, and shared construction, damage, and repair
visual states. They are **not production/AAA assets**.

Research trees, detailed utility storage/crew/logistics, hazards beyond night,
campaign, production art, and audio are future work in [the issue roadmap](docs/ROADMAP.md).

## Run

Install **standard Godot 4.7.2 stable** (not .NET), import `project.godot`, and
press **F5**. For command-line use:

```sh
godot --path . --editor
godot --headless --path . --editor --import
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_saves.gd
godot --headless --path . --script tests/test_scene.gd
```

Substitute `godot4` if that is your executable name. Import before running tests
on a fresh checkout. The pinned CI workflow imports and runs all three test scripts.
Render look-development screenshots (needs a display, e.g. `xvfb-run -a`) with
`godot --path . --script tests/capture_views.gd -- --out <dir>`.

## Play

Select a building in the right panel and click an empty tile. Orthogonally
adjacent modules and utility links exchange power, water, oxygen, and heat.
Diagonal neighbors do not connect. Ice extractors require the frost-tinted ice
deposit (shown blue in the build-mode grid). **Bulldoze pad** (15 cr) clears rocks
and levels rough regolith; construction grades its own pad for free. Immovable
landmark craters and boulders (red in the build grid) cannot be cleared or built on.
Cancel the tool to inspect a module's **local** utility supply and shortages.

| Control | Action |
| --- | --- |
| WASD / arrow keys | Pan camera |
| Q / E | Orbit camera |
| Mouse wheel | Zoom |
| Left click | Build, bulldoze, demolish, or inspect |
| Right click / Esc | Cancel construction tool |
| Space | Pause / resume |
| 1 / 2 / 3 | Set 1x / 2x / 4x speed |
| HUD buttons | Tools, camera, pause, speed, restart, save/load & backup recovery |

One simulated day takes one second at 1x. Days 21-30 of each artificial 30-day
cycle are dark; this is a **game rule**, not real lunar illumination. Solar
arrays stop at night. A reactor, lab, and refinery connected to the starter
outpost provide a viable founding-charter solution. Keep all crew supplied,
reach 30 science and 40 exports, and maintain at least 65 morale after day 30.

Colony state persists using a versioned data-only JSON schema (v2, with v1
migration) to `user://saves` on desktop (atomic temporary writes + `.bak`
backups) and `localStorage` on Web (with `visibilitychange`/`pagehide` lifecycle
autosave). Autosave runs every 5 days and on charter completion, and refuses to
silently overwrite a different colony after Restart without explicit confirmation.
Corrupt, unsupported-version, quota-exceeded, and storage-denied errors preserve
existing files and surface actionable HUD recovery controls instead of resetting.
Long background gaps are ignored instead of fast-forwarding disasters.

## Exports

Install matching Godot export templates, then:

```sh
mkdir -p build/linux build/web
godot --headless --path . --export-release "Linux Desktop" build/linux/selene-frontier.x86_64
godot --headless --path . --export-release "Web" build/web/index.html
python3 -m http.server 8000 --directory build/web
```

Open `http://localhost:8000`, not `file://`. Linux and Web use Compatibility;
Web requires WebAssembly/WebGL2 and uses the single-threaded export. Desktop
Forward+ is future work. Native-mobile support is not included.
Build outputs are ignored and excluded from Godot's resource scan.

## Project guides

- [Game description and system design](docs/DESIGN.md)
- [Technical architecture](docs/ARCHITECTURE.md)
- [Phased roadmap and developer issues](docs/ROADMAP.md)
- [Art direction and platform limits](docs/ART_AND_PLATFORMS.md)
- [Structure style guide](docs/STRUCTURE_STYLE_GUIDE.md)
- [Historical sources and uncertainty](docs/SOURCES.md)
- [Contribution guidance](CONTRIBUTING.md)

No original game's assets, code, manual text, branding, or audio are included.
No distribution license has been chosen; resolve the ownership issue before
distributing builds or incorporating third-party contributions.
