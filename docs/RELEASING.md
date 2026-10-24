# Release maintenance

## Version policy

- `VERSION` is the source of truth for the app bundle version.
- Use semantic versions (`major.minor.patch`) and a corresponding `## [x.y.z]` entry in `CHANGELOG.md`.
- `main` is the development branch. Keep `v1.0.0`, `v1.1.0` and subsequent version tags; never move a published tag or replace its released assets.
- Release files are retained on GitHub Releases, independently of temporary Actions artifact retention.

## Publish a new version

1. Update `VERSION`, user-visible version strings and `CHANGELOG.md`. Update screenshots when behavior or appearance changes.
2. Run `zsh build.sh`, relevant UI checks, and `git diff --check`.
3. Commit reviewed changes. The release script rejects a dirty working tree or an existing version tag.
4. Run `zsh scripts/release.sh` from a machine with push access. It locally builds/packages, creates an annotated tag, pushes `main`, then the new tag.
5. The tag workflow verifies the version, builds both architectures, runs tests, packages the ZIP/DMG and checksums, and publishes the Release.
6. Verify the workflow result, download links, version metadata and checksum file before announcing the release.

The Actions workflow uses GitHub's short-lived `GITHUB_TOKEN` with `contents: write` only for the release job; no personal token or image-hosting secret is needed. Pull requests and branch CI use read-only repository access. Dependabot checks action updates monthly.

## Release inventory

| Version | Architecture | Assets |
|---|---|---|
| 1.0.0 | arm64 | Historical ZIP and SHA256SUMS.txt |
| 1.1.0 | arm64 | Historical ZIP and SHA256SUMS.txt |
| 1.2.0+ | arm64 + x86_64 | Versioned universal ZIP, DMG, SHA256SUMS.txt |

Historical binaries are uploaded from the saved local release artifacts and labeled accordingly; their original tags are retained. They predate the automated tag-release workflow.

## Signing status

The default build is ad-hoc signed and not notarized. GitHub hosting and checksums do not make it an Apple-trusted binary. Do not describe the release as notarized or bypass system protections in an installer.

When the maintainer has a Developer ID certificate and a configured notarytool keychain profile, a signed distribution can be built separately:

1. Build and sign the bundle with the maintainer's Developer ID, hardened runtime and timestamp.
2. Archive with `ditto`, submit with `xcrun notarytool submit ... --keychain-profile ... --wait`, and inspect the result.
3. Staple with `xcrun stapler staple`, verify with `xcrun stapler validate`, then package and publish as a **new version**.
4. Keep signing keys/passwords and notary credentials outside Git. An automated signed-release workflow should use protected repository secrets and an ephemeral signing keychain.

No Apple signing or notarization credentials are configured by this repository. Existing downloaded builds may require permission reauthorization after a changed signature.
