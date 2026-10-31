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
- Keep Xcode tests available for the project owner to run locally using the shared MovieTracker scheme. Do not add GitHub CI for Xcode builds or tests.
- Report exactly which build/tests ran and any environment limitations. Linux cannot validate SwiftUI or SwiftData.
- When development work is complete, commit and push the changes and create or update the pull request. Do not merge it. Report any access blocker explicitly.
- Each cloud task is already isolated. Use the existing checkout; do not create a worktree unless explicitly requested.

- Route personal library writes through the shared main-actor LibraryStore. Preserve its identity lookup, explicit saves, rollback behavior, and independent personal fields; do not add competing writers.
