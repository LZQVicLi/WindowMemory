# Contributing

Issues and pull requests are welcome. Use the issue templates to describe the macOS/app versions, display topology and steps to reproduce. Remove private window titles, paths and exported layouts before posting.

## Development

1. Fork and create a branch from `main`.
2. Install Xcode or compatible command-line tools.
3. Run `zsh build.sh`: build the universal Preview app and run all self-tests. Preview uses a separate bundle ID and synthetic data; it never reads/writes real layouts or controls windows.
4. Run `git diff --check`, then verify relevant native UI behavior on macOS.
5. Include meaningful regression coverage for changes to migration, matching, launch planning, archive validation or coordinate math. Keep tests independent of actual user windows.
6. Update documentation and the changelog as appropriate, and open a focused pull request.

`ARCHS=arm64 zsh build.sh` speeds up Apple Silicon development. Release packaging requires both architectures. Build outputs, signing credentials and local user configuration must not be committed.

Use `BUILD_MODE=release zsh build.sh` only for production packaging or explicit live integration testing. Do not run a differently signed production build alongside the installed release. LaunchServices can resolve the shared bundle ID to the development copy when macOS saves a permission grant, leaving the installed release denied despite the visible switch being on. Keep the app used for permission verification in `/Applications`, and verify the running GUI rather than relying on a CLI process launched by an already-authorized terminal/agent.

Tests cover pure logic. Accessibility, hotkey conflicts, actual display reconnection and login behavior also require manual macOS verification; document what you did and any limitations rather than treating unit tests as end-to-end proof.

Public screenshots are captured from the isolated demo mode (`--demo`, or the `WindowMemoryDemo` bundle flag), which uses synthetic data and does not register shortcuts, move windows, launch apps or write normal settings. Keep documentation screenshots free of private information.

See [release maintenance](docs/RELEASING.md). Contributions are provided under the project's MIT license.

## Translations and appearance regression

`Resources/Translations.json` uses the Simplified Chinese source text as a key, with `en`, `fr`, `es`, `ru` and `ar` translations. Preserve every numbered `{0}` placeholder. Swift interpolation is captured separately by `LocalizedText` so user content is never interpreted as a format string. Use `L("text with \(value)")` for user-facing app strings; keep user-provided scene names, app names and window titles untouched. `AppLanguage` provides an explicit system option and right-to-left layout for Arabic. Native OS panels may retain the OS language.

`zsh build.sh` validates all localized source keys and translations, interpolation safety, preference migration and share URL encoding along with the layout tests. On a Mac with a WindowServer, run `build/WindowMemory Preview.app/Contents/MacOS/WindowMemory --ui-self-test` to exercise dark/light/system transitions through actual AppKit hosting and live language changes using synthetic data. This mode does not read or write the user's layouts, launch real apps or register shortcuts.

Preset geometry and partially configured scenes are tested through the normal archive/launch planner. App discovery tests use temporary synthetic bundles and a symlink fixture, without launching apps.
