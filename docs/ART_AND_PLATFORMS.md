# Art direction and platform strategy

## Visual target

An austere, cinematic lunar landscape: near-black sky, pale regolith, long
directional shadows, bright thermal blankets, restrained agency markings, and
small pools of warm interior light. Detailed modular habitats should contrast
with the enormous, empty terrain. Orthographic composition remains readable
while allowing camera pan, zoom, and quarter-turn rotation.

The foundation uses original procedural shapes. Replace them through
a consistent scene/asset interface rather than coupling imported meshes to the
simulation. AAA is a production ambition, not an achieved milestone.

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
| Desktop baseline | Compatibility, simple materials, directional light and shadows | Implemented prototype |
| Desktop high fidelity | Forward+, profiled GI/SSAO/reflections, richer materials, LODs, limited shadowed lights | Future issue |
| Web | Compatibility/WebGL2, lighter effects, textures/shadows budgeted separately, single-thread export | Preset and Chromium founding-charter smoke check pass; full qualification remains future work |
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

Performance profiling and tuning are deferred at the owner's request. These are
future qualification targets, not measured results or gates for the current
prototype and gameplay development:

- Desktop: 60 FPS at 1080p on a declared midrange reference machine.
- Web: 30 FPS at 720p on a declared integrated-GPU reference machine.
- At least 200 modules in a representative utility stress scene for both tiers.
- HUD contrast and status conveyed by text/symbols as well as color.
- Record CPU simulation time, GPU time, draw calls, peak memory, and Web payload
  size before setting final art budgets.

Choose reference hardware and collect baseline captures in the desktop/Web
qualification issue.
After explicit owner approval resolved the initial setup block, Godot 4.7.2
imports, simulation tests, scene/input integration tests, and a rendered desktop
smoke test passed. Linux and Web release exports were produced. The rendered
check used Mesa llvmpipe software rendering, not representative player hardware.
The HTTP-served Web build completed its founding charter in Chromium at
1440x900 and remained usable after resizing to 1280x800, with no console errors.
ReadPixels performance warnings were observed during captures. These checks do
not establish the proposed performance budgets. Production art, reference-hardware
measurements, Firefox/lifecycle qualification, and mobile support remain future
work.
