# Phased roadmap

## Setup status

The initial setup delivers the project description, architecture, art/platform
direction, historical-source caveats, and developer backlog. **The game project,
playable prototype, export presets, tests, and CI are not implemented.**
Project-file writes and download/execution of the Godot engine were denied in
the initial environment. Do not mistake the design specification for completed
features or measured performance.

GitHub issues are the actionable backlog; this document records sequencing and
release gates. The issue index below links every published development task.

## Phase 0: runnable foundation

Create and pin the Godot project, original procedural lunar terrain, orthographic
camera, building catalog, construction interaction, shared utility simulation,
economy, HUD, and a founding scenario. Use the first-playable specification in
[DESIGN.md](DESIGN.md), but adjust balance only with recorded playtest evidence.

Add generated-file ignores, export presets, contribution/issue templates, and
matching engine setup instructions. Resolve the setup permission limitation in
an authorized development environment rather than bypassing it.

**Exit gate:** a fresh checkout imports and runs; the player can build and
demolish modules, diagnose disconnected utilities, survive night, earn exports
and science, and complete the founding charter. Headless behavioral tests and
actual desktop/Web smoke checks pass.

## Phase 1: robust simulation and recoverability

Add versioned saves, utility storage/capacity/priorities, separate power/water/
oxygen/thermal layers, hazard warnings, repairs, and readable failure diagnostics.
Profile representative colonies early and maintain deterministic simulation.

**Exit gate:** a failed generator causes explainable, testable downstream effects;
redundancy and reserves allow recovery. Saving and loading preserve exact state.

## Phase 2: strategic depth

Add a research tree with alternative solutions, crew roles/morale/health,
terrain surveying and site selection, supply ships and landing windows,
contracts and funding commitments, and limited rival-agency market events.

**Exit gate:** at least three viable approaches to a scenario, meaningful
science/safety/profit tradeoffs, and nontrivial consequences from site choice.

## Phase 3: authored game and visual vertical slice

Introduce a tutorial, campaign scenarios, configurable sandbox, mid/late-game
goals, and a production-quality lunar biome plus representative building set.
Maintain the lower-cost web tier alongside a profiled desktop Forward+ tier.
Add audio, effects, animation, and accessibility as gameplay-facing production
work, not decoration detached from the simulation.

**Exit gate:** one polished end-to-end scenario; validated visual budgets,
readable UI, licensed assets, original branding, and measured platform behavior.

## Phase 4: release readiness

Expand content only after the vertical slice works. Address balance, performance,
accessibility, localization hooks, onboarding, stable save migration, release
packaging, title clearance, asset provenance, and licensing. Native-mobile
support is out of the published backlog: creating its feasibility issue was
denied as outside the authorized scope. No mobile support is promised.

**Exit gate:** declared target hardware meets the budgets, platform test matrix
passes, critical issues are resolved, and release ownership/distribution checks
are complete. No calendar or AAA delivery promise is made without team,
funding, asset, and hardware estimates.

## Dependency rules

- Foundation precedes gameplay integration and export validation.
- The save format must account for changes in utility, crew, research, and
  logistics state; coordinate migrations rather than freezing a brittle format.
- Utility resilience precedes hazards; warnings and repair must exist before
  destructive events become normal gameplay.
- Research/crew/site/logistics can be designed in parallel, but implementation
  must integrate through the authoritative simulation state.
- Campaign work depends on stable systems and saves.
- Art look-development can begin early; production asset rollout depends on
  stable building footprints and a measured performance baseline.
- Ownership and source verification can proceed independently and gate release.

## Developer issue index

Each issue includes scope, dependencies, acceptance criteria, and validation
expectations. Keep deferred tasks in issues rather than undocumented promises
or in-code TODO lists.

| Phase | Issue | Work |
| --- | --- | --- |
| 0 | [#2](https://github.com/rwrife/moonbase/issues/2) | Godot project, camera, generated-file ignores, presets and reproducible setup |
| 0 | [#3](https://github.com/rwrife/moonbase/issues/3) | Isometric colony first playable and founding charter |
| 0 | [#7](https://github.com/rwrife/moonbase/issues/7) | Headless tests, CI, desktop/Web qualification and performance baseline |
| 1 | [#5](https://github.com/rwrife/moonbase/issues/5) | Versioned saves and recovery |
| 1 | [#6](https://github.com/rwrife/moonbase/issues/6) | Utility storage, capacity, priorities and failure cascades |
| 1 | [#10](https://github.com/rwrife/moonbase/issues/10) | Forecastable hazards and repairs |
| 2 | [#4](https://github.com/rwrife/moonbase/issues/4) | Site surveying and strategic terrain |
| 2 | [#9](https://github.com/rwrife/moonbase/issues/9) | Branching research and technology choices |
| 2 | [#11](https://github.com/rwrife/moonbase/issues/11) | Crew roles, health and morale |
| 2 | [#8](https://github.com/rwrife/moonbase/issues/8) | Supply logistics, contracts, markets and funding board |
| 3 | [#13](https://github.com/rwrife/moonbase/issues/13) | Tutorial, campaign scenarios and sandbox |
| 3 | [#14](https://github.com/rwrife/moonbase/issues/14) | High-fidelity lunar art and desktop/Web rendering tiers |
| 3 | [#12](https://github.com/rwrife/moonbase/issues/12) | UX, accessibility, localization hooks and audio |
| Release gate | [#1](https://github.com/rwrife/moonbase/issues/1) | Title clearance, licensing, asset provenance and historical verification |
| 4 | [#15](https://github.com/rwrife/moonbase/issues/15) | Release QA, balancing, packaging and distribution readiness |

The foundation issue owns the blocked initial game-file setup; the validation
issue owns engine/import/runtime/export qualification. Resolve permissions in
an authorized environment rather than attempting to bypass the initial denials.
