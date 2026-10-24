# Changelog

This project uses semantic versioning. Existing version tags and released binary assets are not overwritten.

## [1.3.0] — 2026-10-24

- Add a top-level layout library page alongside Settings, with 12 partition patterns across seven display families; match connected display count, primary role, orientation and usable dimensions by default, with manual catalog browsing. Configure installed apps per display, leave regions empty, and save into the existing scene/launch/restore/import/export workflow.
- Add a persistent user template library with editable percentage-based regions, app assignment reuse, per-display conversion from existing scenes and template edit/delete/use actions.
- Document the exact ad-hoc signing status, Gatekeeper first-launch steps and the Developer ID + notarization path for public distribution.
- Fix dark-to-system appearance changes by removing the conflicting SwiftUI presentation override and synchronizing colors from AppKit effective appearance.
- Replace duplicate accessibility prompts with one System Settings jump and a floating guide with a draggable app icon, manual recheck and stale-record recovery instructions.
- Refresh permission state on activation and every second in common run-loop modes; remove obsolete accessibility observers when permission is revoked.
- Add persistent, immediate language selection for the six UN official languages: Simplified Chinese, English, French, Spanish, Russian and Arabic, including right-to-left layout.
- Localize app controls, menus, alerts, accessibility labels and dynamic status/error messages. Preserve user-supplied scene names and window titles.
- Add user-triggered sharing through macOS, copy link, X, Facebook, LinkedIn, WhatsApp, Telegram, Reddit and email; provide copy-link support for WeChat and bundled offline brand icons for sharing channels. Sharing includes only the public project link and description.
- Expand validation to 166 checks, including translation completeness/placeholders, migration, app discovery, preset geometry and sharing URL encoding; add 19 native appearance/language UI regression checks.

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
