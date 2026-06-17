# Snag

A tiny macOS menu-bar app: paste a video URL, it downloads to `~/Downloads`.

Wraps `yt-dlp` (+ `ffmpeg` for merges). Works for X/Twitter, Instagram, YouTube,
and anything else yt-dlp supports.

## Download

[**Download Snag**](https://www.alexfrih.com/snag.dmg) (macOS, signed + notarized).
Open the disk image and drag Snag to Applications. The app keeps itself up to date
via Sparkle.

## Use

- Click the menu-bar arrow icon.
- The URL field auto-fills from your clipboard; press Enter (or click the arrow).
- Each download shows live progress / speed / ETA; **Reveal** opens it in Finder.

## Behaviour

- Saves to `~/Downloads` as `<title>.<ext>`, best mp4 when available.
- `--no-playlist`: a single paste downloads one item, not a whole playlist.
- Tools are resolved from Homebrew/miniconda paths (a GUI app has no shell PATH),
  with a login-shell `command -v` fallback. If `yt-dlp` is missing, the popover
  shows the install command.

Requires `yt-dlp` and `ffmpeg`:

```bash
brew install yt-dlp ffmpeg
```

Menu-bar utility (`LSUIElement`), no Dock icon. Launch-at-login via the footer
toggle (SMAppService).

## Build

```bash
scripts/run.sh      # swift build -c release, bundle dist/Snag.app, launch (dev)
```

## Release (maintainer)

```bash
scripts/release.sh         # build, sign (Developer ID), notarize + staple app & dmg
scripts/publish.sh 0.2.0   # GitHub release (zip) + EdDSA-signed Sparkle appcast -> Pages
```

Auto-update feed: <https://alexfrih.github.io/snag/appcast.xml>.
