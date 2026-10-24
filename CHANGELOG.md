# Changelog

This project uses semantic versioning. Existing version tags and released binary assets are not overwritten.

## [1.2.0] — 2026-10-24

- Add multiple named workspace scenes for each display combination.
- Add configurable global shortcuts for launching, restoring and saving the selected scene, including duplicate/conflict feedback.
- Add layout JSON export/import, validation, legacy backup import and explicit cross-Mac display mapping. Imports add scenes without overwriting existing layouts.
- Add per-app launch ordering, launch intervals and configurable window retry timeouts up to 120 seconds.
- Preserve existing 1.0/1.1 layouts and settings; add active-scene persistence and read-only protection for unreadable configuration files.
- Ship universal Apple Silicon + Intel builds, versioned ZIP/DMG assets and SHA-256 checksums.
- Add MIT licensing, bilingual README, synthetic-data screenshots, contribution guidance and automated CI/tag releases.
- Expand validation to 53 self-tests.

## [1.1.0] — 2026-10-24

- Add one-action workspace application launch with bounded retries, cancellation and launch-failure feedback.
- Add login window behavior and optional workspace launch at login.
- Add dedicated preferences, system/light/dark appearance and a console-style UI.
- Preserve existing window geometry and login item state; add migration tests.
- Historical binary: Apple Silicon, locally signed, not notarized.

## [1.0.0] — 2026-10-24

- Initial native menu-bar window layout manager.
- Save window display assignments, positions and sizes per display combination.
- Restore on app/window/display/wake events; provide manual restore and undo.
- Login startup, per-window exclusion and local JSON storage.
- Historical binary: Apple Silicon, locally signed, not notarized.
