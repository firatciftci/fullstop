# Contributing to Fullstop

Thanks for helping out. Bug reports, small fixes, and well-scoped features are all welcome.

## Before you start

For anything bigger than a small fix, open an issue first so we can agree on the approach before you spend time on it. Fullstop is meant to feel like it shipped with macOS, so follow the [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) and use system controls and behavior wherever they exist.

All code in Fullstop is written from scratch. Don't copy code, text, or images from other charge limiters, including closed-source ones.

## Set up

You need Xcode 27 and [Homebrew](https://brew.sh).

```sh
brew bundle
xcodegen generate
open Fullstop.xcodeproj
```

`project.yml` is the source of truth for the Xcode project. The generated `Fullstop.xcodeproj` isn't checked in, so put build settings, files, and capabilities in `project.yml` and run `xcodegen generate` again.

The project has two targets:

- Fullstop is the menu bar app. It sets limits from 80% to 100% through the charge limit built into macOS, without special permissions.
- FullstopHelper is a small launch daemon that runs as root. The app installs it with `SMAppService` and talks to it over XPC. It does only three things: sets charge limits below 80%, connects or disconnects the power adapter, and sets the MagSafe light. It accepts connections only from the Fullstop app signed by the same team.

Code that both targets use lives in `Shared`. Keep the helper's surface as small as possible, and put every decision about what to do in the app.

The helper installs only from a signed build. To test it, set your team in `project.yml` and build with signing turned on.

## Code style

- Swift 6 with complete concurrency checking. App types are main-actor isolated by default, and helper types aren't.
- swift-format handles layout and SwiftLint handles everything else. Both run in strict mode, and the build treats warnings as errors.
- Write `Array<Element>` instead of `[Element]`, and use a `for` loop instead of `reduce`.
- Let names and structure explain the code. Don't add comments to the source.
- User-facing text lives in `Fullstop/App/Strings.swift`. Use American English. Write descriptions in sentence case and labels and buttons in title case, as macOS does.

Run all the checks with:

```sh
tools/check.sh
```

The script formats the code in place, so commit any changes it makes.

## Pull requests

- Keep each pull request to one change.
- Start the title with a [Conventional Commits](https://www.conventionalcommits.org) type, like `feat: add a charge schedule` or `fix(helper): restore the adapter on exit`. Pull requests are squash-merged, so the title becomes the commit message and the release note.
- For visible changes, include a screenshot or a short recording in both light and dark mode.
- CI must pass before a pull request can merge.

## Releases

Maintainers cut a release by raising `MARKETING_VERSION` in `project.yml`, merging that change, and pushing a matching `v` tag, like `v1.2.0`. The release workflow builds, signs, and notarizes the app and its helper, publishes the DMG, and updates the Sparkle feed that installed copies check for updates. `tools/release-secrets.sh` walks you through setting up the signing and notarization secrets the workflow needs.

The disk image is built by `tools/dmg/make-dmg.sh`, which lays out the installer window with a background, the app, and a shortcut to Applications. To change the design, edit the colors, caption, or layout in `tools/dmg/dmg.json`, then render a new background and commit it:

```sh
xcrun swift tools/dmg/background.swift tools/dmg
tools/dmg/make-dmg.sh path/to/Fullstop.app build/Fullstop.dmg
```
