# Contributing

Start with [the design](docs/DESIGN.md) and [the issue roadmap](docs/ROADMAP.md).
Take a focused issue, identify its dependencies, and agree on acceptance criteria
before expanding scope. Submit reviewable pull requests unless the owner gives
a task-specific publication instruction.

Use standard Godot 4.7.2, GDScript, and the Compatibility baseline. Keep simulation
state independent of rendering; commands must validate before charging resources.
Use InputMap actions, explicit types, and signals rather than UI-owned game rules.
Update directly affected documents when changing gameplay.
New or changed structures must follow the
[structure style guide](docs/STRUCTURE_STYLE_GUIDE.md).

On a fresh checkout, run these commands before submitting changes:

```sh
godot --headless --path . --editor --import
godot --headless --path . --script tests/test_simulation.gd
godot --headless --path . --script tests/test_scene.gd
```

Add focused behavioral tests for new rules and their failure paths. Also launch
the scene for changes involving visuals or input. Web changes require an actual
HTTP-served browser check; passing headless tests is not a Web performance result.

Never commit `.godot/`, build outputs, export credentials, or third-party assets
without verified redistribution rights and provenance. Current meshes/materials
are original procedural placeholders. There is no chosen project license yet;
resolve the licensing issue with the owner before distributing or incorporating
outside contributions.
