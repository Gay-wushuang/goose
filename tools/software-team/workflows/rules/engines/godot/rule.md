# Godot Engine Rules

Load this rule only when selected by this package's manifest.

## Baseline
- Read `project.godot` to determine configured features, renderer, input actions, and main scene.
- Use the installed Godot executable's actual version; never invent a version.
- Inspect existing scenes, resources, scripts, imports, and project instructions before editing.

## Implementation
- Do not invent uncertain `.tscn` or `.tres` syntax. Follow a valid repository pattern or generate resources through the matching Godot version when practical.
- Keep project configuration, main scene, resource paths, script paths, node paths, and input actions consistent.
- Preserve engine-generated identifiers and import metadata unless the requested change requires updating them.

## Verification
- Run the package validator and require a passing `PREFLIGHT_RESULT_V1`.
- A language compiler passing does not prove Godot can import or run the project.
- Invalid scenes/resources, unresolved paths/scripts, or engine startup errors are implementation failures eligible for bounded preflight repair only when the diagnostic is localized and unambiguous.
