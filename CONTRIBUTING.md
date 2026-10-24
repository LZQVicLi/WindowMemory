# Contributing

Issues and pull requests are welcome. Use the issue templates to describe the macOS/app versions, display topology and steps to reproduce. Remove private window titles, paths and exported layouts before posting.

## Development

1. Fork and create a branch from `main`.
2. Install Xcode or compatible command-line tools.
3. Run `zsh build.sh`: build the universal app and run all self-tests.
4. Run `git diff --check`, then verify relevant native UI behavior on macOS.
5. Include meaningful regression coverage for changes to migration, matching, launch planning, archive validation or coordinate math. Keep tests independent of actual user windows.
6. Update documentation and the changelog as appropriate, and open a focused pull request.

`ARCHS=arm64 zsh build.sh` speeds up Apple Silicon development. Release packaging requires both architectures. Build outputs, signing credentials and local user configuration must not be committed.

Tests cover pure logic. Accessibility, hotkey conflicts, actual display reconnection and login behavior also require manual macOS verification; document what you did and any limitations rather than treating unit tests as end-to-end proof.

Public screenshots are captured from the isolated demo mode (`--demo`, or the `WindowMemoryDemo` bundle flag), which uses synthetic data and does not register shortcuts, move windows, launch apps or write normal settings. Keep documentation screenshots free of private information.

See [release maintenance](docs/RELEASING.md). Contributions are provided under the project's MIT license.
