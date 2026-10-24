# WindowMemory

A native macOS menu-bar app that remembers which display each window belongs to, its position and its size. Save multiple scenes for the same monitor setup, then launch and restore a workspace in one action.

[中文](README.md) · **[Download](https://github.com/LZQVicLi/WindowMemory/releases/latest)** · [Changelog](CHANGELOG.md)

![Workspace console using synthetic demo data](docs/images/workspace-dark.png)

## Features

- Adaptive layout library: recommendations use display count, primary role, orientation and usable size. Browse seven display families and 12 partition patterns, configure installed apps independently on each display, leave areas empty, and save into the existing scene workflow.
- A top-level layout library with custom percentage-based regions. Add existing scenes as per-display templates, preserve app assignments, and edit, delete or reuse your templates.
- Multiple named scenes per display combination, with an active scene remembered for each setup.
- Launch enabled workspace apps without creating duplicate application instances.
- Per-app launch order, delay before the next app, and window retry timeout (up to 120 seconds).
- Configurable global shortcuts for launch, restore and save; registration errors and duplicate bindings are reported.
- JSON layout export/import, legacy backup import and an explicit display-mapping dialog for a different Mac. Imports add scenes without overwriting existing ones.
- Event-triggered restoration on app launch, window creation, display changes and wake.
- Login launch, optional startup window and optional automatic workspace launch.
- Immediate system/light/dark appearance, menu-bar controls and undo for the last manual restore.
- Six UN official languages: Simplified Chinese, English, French, Spanish, Russian and Arabic, including right-to-left layout and a system-language option.
- A floating permission guide with a draggable app icon and live permission checks.
- Project sharing through macOS, copy link, X, Facebook, LinkedIn, WhatsApp, Telegram, Reddit and email. WeChat uses copy link; the user confirms sending.

![Light settings in English, using synthetic data](docs/images/settings-light-en.png)

![Adaptive library with a laptop primary and portrait secondary display](docs/images/layout-library.png)

![Visual layout preset editor](docs/images/layout-presets.png)

## Install

Requires macOS 14+. Releases starting at 1.2.0 provide a universal app for Apple Silicon and Intel. Earlier 1.0/1.1 binaries are Apple Silicon only.

Download the ZIP or DMG from [Releases](https://github.com/LZQVicLi/WindowMemory/releases), move the app to Applications, and grant the window-control permission requested by macOS. Arrange your windows and select **Save layout**. **Restore positions** restores running windows; **Launch & restore** launches and restores the selected scene. Choose a language in **Settings → Language**.

Current binaries are ad-hoc signed and **not Apple notarized**. macOS may block a downloaded build. After verifying the source, use macOS's Privacy & Security “Open Anyway” flow, or build from source. Do not disable Gatekeeper or SIP. A recompiled update may require removing the old accessibility entry and authorizing the installed new app.

See [signing and first-launch details](docs/SIGNING.md) for the current ad-hoc status and the Developer ID + notarization distribution path. “Open Anyway” is a user exception, not notarization.

Each release retains versioned assets and `SHA256SUMS.txt`; verify with `shasum -a 256 -c SHA256SUMS.txt`.

## Shortcuts

- Launch scene: Control–Option–Command–Return
- Restore scene: Control–Option–Command–R
- Save scene: Control–Option–Command–S

Configure bindings in the **Launch & shortcuts** page. The app must be running. Scene selection itself does not move windows.

## Privacy and limitations

Data stays in `~/Library/Application Support/WindowMemory/`. Layout management works offline and includes no telemetry. Sharing opens a browser or system share sheet only when requested, with the public project link and description; layouts and window data are not included. Exports contain window titles and app identities; inspect them before sharing. Imports never execute scripts or apply global/login settings.

Only ordinary, non-minimized, non-fullscreen windows are handled. Access to other Spaces depends on macOS. Window-title matching and app minimum sizes can prevent exact restoration. Documents, browser tabs and missing extra windows are not recreated. Restoration uses events and bounded retries rather than continuously forcing geometry.

## Build

Xcode or compatible command-line tools are required. There are no third-party Swift dependencies.

```sh
git clone https://github.com/LZQVicLi/WindowMemory.git
cd WindowMemory
zsh build.sh                # universal binary + 53 checks
zsh scripts/package.sh      # versioned ZIP, DMG, checksums
```

The build is `build/窗口记忆.app`. See [Contributing](CONTRIBUTING.md) and [Releasing](docs/RELEASING.md). Screenshots use synthetic demo data.

[MIT License](LICENSE) © 2026 LZQVicLi.

Share channel artwork is from [Simple Icons](Assets/ShareIcons/NOTICE.md), under CC0-1.0. Brand trademarks remain with their respective owners.
