# Contributing

Small, focused contributions are welcome. This is a young project using private
display APIs, so reliable recovery matters more than adding many controls.

## Before changing code

Open an issue for a substantial feature or architecture change. Include the
problem, affected hardware, and expected behavior. For display problems, include
macOS version, Mac chip, monitor model, cable/adapter, requested logical size,
and refresh rate. Do not include credentials, display serial numbers, or unrelated logs.

## Development

1. Fork and clone the repository.
2. Run `make build` and `make test` on macOS with Xcode or Command Line Tools.
3. Make a focused change and document any behavior or compatibility changes.
4. Run the relevant checks in `docs/TESTING.md` on a monitor you can safely use
   for testing. Never treat a successful compile as hardware validation.
5. Open a pull request explaining the problem, resulting behavior, and checks
   actually performed. List untested hardware and failure paths honestly.

Use Objective-C with ARC for the native app. Avoid third-party runtime
dependencies for functionality provided by the platform. Keep configuration
validation separate from operations that change displays.

Do not add telemetry, automatic downloads, privileged helpers, or security-setting
changes without a prior design discussion. Never put certificates or private
keys in the repository. Any new third-party code needs a compatible license and
an entry in `ThirdPartyNotices.md`.

Contributions are accepted under this repository's MIT license. Contributors
retain their copyright; preserve existing copyright and license notices.

Be respectful and specific in issues and reviews. Critique code and claims, not
people. Harassment, threats, and sharing another person's private information
are not acceptable; maintainers may remove that content and restrict participation.
