# Colerm project instructions

- Keep the application AppKit-first for terminal surfaces and paging.
- Keep SwiftUI limited to surrounding controls and settings.
- Keep Ghostty C types and ABI-sensitive code inside `Sources/ColermApp/GhosttyBridge`.
- Do not treat persisted sessions as live process restoration; relaunch creates new shells in saved directories.
- Do not enable App Sandbox for the direct-distribution target.
- Run `swift build`, `swift test`, and `scripts/check.sh` before handoff.
