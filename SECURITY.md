# Security policy

## Supported version

Security fixes currently target the latest 0.1.x preview. There is no long-term
support commitment or guaranteed response time.

## Report privately

For a vulnerability, use this repository's **Security → Report a vulnerability**
feature. Avoid public issues containing exploit details, private data, or logs
from other applications. Ordinary display compatibility problems belong in Issues.

## Security properties and limits

- No account, analytics, app-originated network requests, updater, or privileged helper.
- User settings and a recovery record stay in the current user's preferences.
- Launch-at-login registration uses Apple's `SMAppService`; it is opt-in.
- No SIP changes, EDID writes, system patching, or administrator installation.
- The app uses private macOS display APIs and is not sandboxed. A display change
  can make the desktop temporarily unusable; recovery is best effort.
- Preview binaries are ad-hoc signed and not Apple-notarized. Checksums establish
  archive integrity against the release manifest, not independent trust in the publisher.

Do not disable macOS security protections to install the app. Review the source
and use Apple's per-app opening flow if you choose to run a downloaded preview.
