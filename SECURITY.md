# Security

The latest minor release is the supported version. Older binaries remain available for reproducibility but do not receive backported fixes by default.

Use this repository's private vulnerability reporting feature when available. If unavailable, open a minimal issue asking for a private reporting channel, without including exploit details or sensitive data. Do not post real exported layouts, window titles, credentials, signing material or private screenshots.

WindowMemory requires macOS window-control/accessibility permission to inspect and move windows. Layouts remain local. Imported JSON is size-limited and validated, never interpreted as scripts; import does not launch applications or enable login automation. A user explicitly triggering a saved scene can open the apps recorded in it.

Release downloads are ad-hoc signed, not Apple notarized. Verify version assets with the published SHA-256 checksums. Never disable macOS system protections to run a build.
