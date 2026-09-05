# Contributing to TetherCam

Primary development happens on GitLab (`agents/obs-iphone-usb-cam` at
gitlab.gotzendorfer.at). This GitHub repository is a mirror, but pull requests here are
welcome and get reviewed the same way.

## Before you change the wire protocol

`protocol/PROTOCOL.md` is the contract between the iPhone app and the OBS plugin. If a
change touches framing, message types or error codes, update `protocol/PROTOCOL.md`
first, then update both sides (`ios-app/` and `obs-plugin/`, plus the shared code in
`shared/` where it applies) to match. Do not let the two sides drift.

## Building and testing each part

```sh
# shared: C11 core, unit tests via ctest
cmake -S shared -B shared/build && cmake --build shared/build
ctest --test-dir shared/build --output-on-failure

# tools: Swift package (simulator + CLI receiver), plus the end to end script
swift test --package-path tools
bash tools/integration.sh            # needs ffmpeg/ffprobe, no iPhone required

# ios-app: xcodegen generates the .xcodeproj from project.yml
cd ios-app && xcodegen generate
xcodebuild test -scheme TetherCam -destination 'platform=iOS Simulator,name=iPhone 17'

# obs-plugin: CMake preset, CI=1 is required
cd obs-plugin
CI=1 cmake --preset macos
CI=1 cmake --build --preset macos
```

`CI=1` is required for the plugin configure step; without it the obs-plugintemplate build
scripts try to ask interactively for signing details and fail in a non-interactive shell.

## Commit style

This repo uses [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, and so on). Keep the subject line short
and put the reasoning in the body when it is not obvious from the diff.

No sign-off (DCO-style `Signed-off-by`) is required to contribute.

## License split

Licensing in this repo is mixed and stays that way:

- `obs-plugin/` is GPL-2.0-or-later, because it links against libobs.
- Everything else (`shared/`, `ios-app/`, `tools/`, `protocol/`, `docs/`) is MIT.

Do not add GPL licensed code anywhere outside `obs-plugin/`.

## Pull requests

Open PRs against `main` on GitHub. Describe which side changed (plugin, app, shared,
protocol, docs) and how you tested it. See `.github/PULL_REQUEST_TEMPLATE.md` for the
checklist that is filled in automatically.
