<h1 align="center">Fullstop</h1>

<p align="center">Stop charging where you want, and keep your battery healthy.</p>

<p align="center">
  <a href="https://github.com/firatciftci/fullstop/actions/workflows/ci.yml"><img src="https://github.com/firatciftci/fullstop/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
</p>

Fullstop lives in your menu bar and stops your Mac from charging past the limit you choose. Lithium-ion batteries wear faster at a full charge. If your Mac is plugged in most of the day, a limit of 80% or lower helps the battery last longer.

Fullstop is in early development, and there's no release yet.

## How it works

- Limits from 80% to 100% use the charge limit built into macOS. Fullstop sets it for you, so you don't need to install anything else.
- Limits below 80% need a small helper that runs in the background. Fullstop asks you to install it the first time you pick a lower limit. You then approve it in System Settings > General > Login Items & Extensions.
- When your battery is above the limit, your Mac runs from the power adapter and lets the battery drain down to the limit.

## Requirements

A Mac with Apple silicon and macOS 27 or later.

## Privacy

Fullstop has no accounts, analytics, or servers of its own. Everything it reads about your battery stays on your Mac. The only network requests are update checks, which go to GitHub.

## Build from source

You need Xcode 27 and [Homebrew](https://brew.sh).

```sh
git clone https://github.com/firatciftci/fullstop.git
cd fullstop
brew bundle
xcodegen generate
open Fullstop.xcodeproj
```

The Xcode project is generated from `project.yml`, so change that file instead of the project settings, then run `xcodegen generate` again. To build without a signing team, pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`. The helper only installs from a build signed with a Developer ID or Apple Development certificate, so unsigned builds are limited to charge limits from 80% to 100%.

Before you open a pull request, run the same checks as CI:

```sh
tools/check.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more.

## License

[MIT](LICENSE)
