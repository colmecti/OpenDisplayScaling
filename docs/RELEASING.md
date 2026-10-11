# Release process

1. Update version strings in `Resources/Info.plist`, `Sources/App.m`, the README,
   and changelog. Describe observed compatibility, not presumed compatibility.
2. Run `make package` on macOS. Run the relevant manual checks in `TESTING.md`
   only on hardware available for deliberate display testing.
3. Inspect `git diff` and source artifacts for credentials, local machine paths,
   preference records, unrelated logs, and signing material. None belong in a release.
4. Commit the reviewed source and push it. If hosted CI is enabled, check its result for that commit. Otherwise record the local validation and disclose that hosted checks did not run.
5. Create an annotated version tag pointing at that commit and publish a GitHub
   release containing the app ZIP, `SHA256SUMS.txt`, and honest release notes.
6. Download the published asset again and verify its hash against the manifest.

Preview releases are marked **pre-release** on GitHub. The README links to the
specific preview tag rather than `/releases/latest`, which omits pre-releases.

## Signing

By default the build is ad-hoc signed. This checks bundle integrity but provides
no Apple-verified developer identity. Say clearly that it is not notarized.

A maintainer with a valid Developer ID Application certificate can supply
`ODS_SIGNING_IDENTITY` to `scripts/build.sh`. That alone does not implement
notarization. A notarized distribution also needs the appropriate signing/runtime
configuration, Apple's notarization service, stapling, and fresh verification of
the private display API behavior. Do not label an ad-hoc or Apple Development
signature as Developer ID or notarization.

Never commit certificates, private keys, account credentials, or notarization
profiles. This repository's CI requires no secrets and does not publish releases
or install login items automatically.

## Enabling GitHub Actions

The workflow is supplied at `docs/github-actions-ci.yml`. Move it to
`.github/workflows/ci.yml` using a GitHub credential authorized to write workflows.
The initial release publisher did not have that scope, so hosted CI is not yet
active. The template requests read-only repository access and no secrets.
