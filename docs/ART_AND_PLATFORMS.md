# Art direction and platform strategy

## Visual target

An austere, cinematic lunar landscape: near-black sky, pale regolith, long
directional shadows, bright thermal blankets, restrained agency markings, and
small pools of warm interior light. Detailed modular habitats should contrast
with the enormous, empty terrain. Orthographic composition remains readable
while allowing camera pan, zoom, and quarter-turn rotation.

The planned foundation will use original procedural shapes. Replace them through
a consistent scene/asset interface rather than coupling imported meshes to the
simulation. AAA is a production ambition, not an achieved milestone. This setup
contains documentation only; project-file writes were denied.

## Production asset pipeline

- Author modular buildings with a consistent scale, pivot, footprint, utility
  sockets, collision bounds, and LOD naming scheme.
- Use glTF 2.0 for exchange and PBR materials. Keep source assets and license/
  attribution records separate from imported runtime assets.
- Prototype the habitat, solar array, and reactor first; review silhouette,
  ground contact, status readability, and materials at gameplay zoom.
- Build a terrain look-development scene before committing to a large content
  library. Use reusable rocks, craters, dust decals, and regolith materials.
- Budget geometry, textures, draw calls, shadows, and particle overdraw against
  measured target hardware. Avoid decorative detail that hides utility problems.
- Add sound, animations, landing effects, and UI motion only after the core
  loop and performance envelope are established.

## Rendering tiers

| Tier | Direction | Status |
| --- | --- | --- |
| Desktop baseline | Compatibility, simple materials, directional light and shadows | Planned initial project target |
| Desktop high fidelity | Forward+, profiled GI/SSAO/reflections, richer materials, LODs, limited shadowed lights | Future issue |
| Web | Compatibility/WebGL2, lighter effects, baked lighting where useful, compressed assets, single-thread export | Future preset and runtime qualification required |
| Native mobile | Mobile renderer or Compatibility would require device profiling, touch UI and smaller budgets | Out of published backlog; feasibility issue creation was denied, support not promised |

Do not describe Godot's **Mobile renderer** as supported by Web: it is a renderer
for native platforms, distinct from running a Web build in a mobile browser.
Changing renderers must not change simulation outcomes. Keep the scene compatible
with the baseline and gate optional high-end effects by a tested profile.

## Current documentation check

On 2026-11-25 the Godot `stable` web-export documentation was checked through
the upstream documentation repository because the documentation site's DNS
was unavailable in the setup environment:

- [Godot web export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Upstream source](https://github.com/godotengine/godot-docs/blob/stable/tutorials/export/exporting_for_web.rst)

It states that Web requires WebAssembly and WebGL2, supports Compatibility only,
and does not currently support WebGPU or Forward+/Mobile on Web. GDScript avoids
the documented Godot 4 C# Web-export limitation. Single-thread Web export has
been supported since 4.3 and is now the default recommendation; threaded exports
require cross-origin isolation and appropriate headers. Recheck these constraints
when upgrading the pinned engine.

Serve Web builds over HTTP(S), not `file://`. Test browser memory, initial
download, context loss, tab suspension, resize, and audio after a user gesture.
Do not promise desktop feature parity or equal performance.

## Proposed qualification targets

These are acceptance targets, not measured results:

- Desktop: 60 FPS at 1080p on a declared midrange reference machine.
- Web: 30 FPS at 720p on a declared integrated-GPU reference machine.
- At least 200 modules in a representative utility stress scene for both tiers.
- HUD contrast and status conveyed by text/symbols as well as color.
- Record CPU simulation time, GPU time, draw calls, peak memory, and Web payload
  size before setting final art budgets.

Choose reference hardware and collect baseline captures in the desktop/Web
qualification issue.
Runtime/export testing was blocked during initial setup because permission to
download and execute the Godot binary was denied; no visual/performance result
should be inferred from the existence of a project or export preset.
