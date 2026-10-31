# Development instructions

- Read the README and existing project instructions before modifying code.
- Keep changes focused on the requested feature; do not add unrequested features.
- Follow the established feature folders, domain types, and naming.
- Prefer native Apple frameworks and avoid unnecessary third-party dependencies.
- Keep domain values separate from SwiftData storage; document important technical decisions.
- Add relevant tests for new behavior and preserve functionality outside the task's scope.
- Use Swift concurrency for asynchronous work; keep UI and model-context work on the main actor.
- Use semantic colors, dynamic text styles, SF Symbols, and accessible native controls.
- Never commit secrets, API keys, credentials, signing material, or generated build artifacts.
- Run the shared MovieTracker scheme's tests with an available iOS Simulator on macOS.
- Report exactly which build/tests ran and any environment limitations. Linux cannot validate SwiftUI or SwiftData.
- Each cloud task is already isolated. Use the existing checkout; do not create a worktree unless explicitly requested.
