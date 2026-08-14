# C# and .NET Rules

Load this rule only when selected by this package's manifest.

## Baseline
- Inspect solution/project files, target framework, SDK declaration, nullable/implicit-using settings, package references, and repository build instructions.
- Use installed `dotnet --info` and tool versions as evidence.

## Implementation
- Preserve the framework-specific SDK and project structure. A successful build using an inappropriate generic SDK is not an acceptable substitute.
- Do not add or upgrade packages, SDKs, target frameworks, analyzers, or generated project files without authorization.
- Preserve namespaces, assembly references, nullability, and public API compatibility.

## Verification
- Run the package validator and require a passing `PREFLIGHT_RESULT_V1`.
- When C# belongs to an engine/framework, also run that stack's validator; compilation alone is insufficient.
