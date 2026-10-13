# Mac utilities

Three free macOS menu bar apps, built with Swift Package Manager — no Xcode required.

| App | What it does | Permissions |
|---|---|---|
| **GazeFocus** | Moves keyboard focus to the screen you're looking at | Camera, Accessibility |
| **WakeHold** | Keeps the Mac awake only while something is genuinely working | None (admin only for lid-closed) |
| **AFK** | Locks the Mac while your work keeps running | None (admin only for lid-closed) |

## Layout

```
apps/
  GazeFocus/     camera + Vision head tracking, AX focus switching
  WakeHold/      activity-driven sleep holding
  AFK/           deliberate lock-and-hold sessions
packages/
  PowerCore/     shared process sampling + power assertions
scripts/
  build-app.sh   SwiftPM -> universal .app bundle, signed
  make-dmg.sh    .app -> distributable .dmg
  icongen/       renders every app icon from code
web/             marketing + download sites
assets/          generated .icns and .iconset files
dist/            build output
```

## Building

Requires the Command Line Tools (Swift 5.9+) and macOS 14+. Xcode is **not** needed.

```sh
./scripts/build-app.sh GazeFocus com.gazefocus.app "GazeFocus"
./scripts/build-app.sh WakeHold  com.wakehold.app  "WakeHold"
./scripts/build-app.sh AFK       com.afkapp.mac    "AFK"

./scripts/make-dmg.sh GazeFocus
```

Each app builds `arm64` and `x86_64` separately and merges them with `lipo`.
`swift build --arch` would be the obvious route to a universal binary, but it
goes through `xcbuild`, which ships only with full Xcode.

## Diagnostics

Every app has a built-in self-check that reports what it can actually see —
the fastest way to separate a settings problem from a permissions one.

```sh
/Applications/WakeHold.app/Contents/MacOS/WakeHold --diagnose
/Applications/GazeFocus.app/Contents/MacOS/GazeFocus --diagnose
/Applications/AFK.app/Contents/MacOS/AFK --diagnose
/Applications/AFK.app/Contents/MacOS/AFK --dry-run 20   # holds without locking
```

## Regenerating icons

```sh
cd scripts/icongen && swift run -c release icongen ../../assets
cd ../../assets && iconutil -c icns GazeFocus.iconset -o GazeFocus.icns
```

## Two implementation notes worth knowing

**CPU time is reported in mach units, not nanoseconds.** `proc_pid_rusage`
returns `ri_user_time` in mach absolute time. On Intel the timebase is 1/1 so
the two coincide; on Apple silicon it is 125/3. Reading the field as
nanoseconds under-reports CPU by ~42x — enough to make a fully pinned core
look idle. See `packages/PowerCore/Sources/PowerCore/ProcessSampler.swift`.

**Secure Event Input silently disables keystroke monitoring.** While a password
field is focused, macOS stops delivering key events to global monitors. Any
"are they typing?" check therefore goes quiet exactly when the user is typing
something that must not be misdirected. GazeFocus checks
`IsSecureEventInputEnabled()` directly rather than inferring. See
`apps/GazeFocus/Sources/GazeFocus/Guards/SystemGuards.swift`.

## Signing

Builds are ad-hoc signed and will show a Gatekeeper warning on first launch.
See [docs/SIGNING.md](docs/SIGNING.md) for what changes with a paid Apple
Developer account.
