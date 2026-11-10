# Changelog

This project uses semantic versioning. Existing version tags and released binary assets are not overwritten.

## [1.5.0] — 2026-11-10

- Broaden hardware control discovery with unique EDID matching, alternate AV reads and Framebuffer I²C fallback on compatible systems. Report the detected signal and responsive control route separately.
- Add per-display software dimming and optional manual LAN pairing for input and volume on compatible HyperOS monitors.

扩展显示器连接兼容性：DDC/CI 增加备用 I²C 路径，并显示信号协议与控制接口的诊断结果。支持独立屏幕的软件调暗，以及兼容澎湃 OS 显示器的手动 IP 遥控。软件调暗只改变画面，不改变背光或输入源；局域网遥控不扫描网段。

## [1.4.0] — 2026-11-10

- Add Display management to the sidebar and menu-bar menu. List all online displays, use native brightness where available, and discover and adjust supported monitor features over DDC/CI. Confirm changes that can disconnect the active image and verify settings with readback when possible.
- Check the official GitHub release at startup. Show an update notice in the sidebar footer; install a newer verified release on demand and restart, with a manual download fallback.
- Verify the release asset digest, ZIP boundaries, version, bundle identity and code signature before replacing the app. Retain the previous build and attempt rollback if the new app fails to open.
- Validate every release ZIP against the updater before publishing. Add a separate live Display Preview for hardware testing without affecting an installed copy or its layouts.

新增「显示管理」和启动时自动检查更新。外接屏按 DDC/CI 能力展示亮度、对比度、输入源、色彩与音量等项目，兼容内建屏显示原生亮度。侧栏底部提示新版，点击「一键更新」后先校验再替换、重启。旧版首次升级到 1.4.0 仍需手动下载；签名变化后 macOS 可能要求重新授予窗口控制权限。

## [1.3.1] — 2026-10-24

- Default local builds to an isolated Preview bundle with synthetic data, a distinct bundle ID and display name. This prevents development copies with a different ad-hoc signature from competing with the installed release's macOS permission identity.
- Require explicit release build mode in CI and packaging; document why a visible enabled permission switch or a trusted CLI subprocess does not prove that the installed GUI is authorized. Existing v1.3.0 binaries and tags are unchanged.
- Maintenance release: the installed app retains its normal workspace behavior. Existing stale macOS permission records still require the user to re-add the installed app; this release does not automatically change system security permissions.

本次维护版将默认开发构建改为独立身份的 Preview，避免开发副本与正式版争用系统授权记录；完善正式打包检查和权限排查说明。已存在的失配授权仍需用户在系统设置中重新添加已安装 App，更新不会自动重置或授予系统权限。历史版本及下载产物继续保留。

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
