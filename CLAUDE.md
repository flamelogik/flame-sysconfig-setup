# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

**Flame Sysconfig Setup** (`flamelogik/flame-sysconfig-setup`): a native macOS SwiftUI app, shared with the Autodesk Flame community through the Logik GitHub org, that guides a user through building a central Flame `sysconfig.cfg`. Several Flame workstations can then read their shared folders, node bins, configuration files and project defaults from one file on shared storage. `README.md` is the user-facing guide, `CHANGELOG.md` the release notes, and `STATUS.md` says where the work stands.

This is a public, facility-neutral project. Don't commit anything about a particular facility: no studio names, hostnames, IP addresses, or site paths such as `/Volumes/<a real share>`. Placeholders use `/Volumes/YourShare/flame`. Site-specific notes belong in the git-ignored `CLAUDE.local.md`, if one exists.

Autodesk's help page for `sysconfig.cfg` (Flame Help, "sysconfig.cfg") is the primary reference. A local text copy may exist as `sysconfig_manual.txt`; it's git-ignored because it's Autodesk's copyrighted text. The help lags the software: it doesn't mention `grab_reference`, which Flame 2027 ships.

## Layout

| Path | What it is |
|---|---|
| `Sources/Catalog.swift` | Built-in list of settings (key, description, default, Flame version it arrived in), `FlameVersion`, and `Discovery`, which reads each installed Flame's default sysconfig. |
| `Sources/Model.swift` | `ConfigModel`: editing state, JSON output, load/save, review checks, diff, copying missing `.cfg` files, pointer state/install. |
| `Sources/Profile.swift` | `FacilityProfile`: a facility's shared root plus relative layout, stored per user, exportable as JSON; fills the window in one click. |
| `Sources/FlameLog.swift` | Parses the `SYSCFG:` lines in Flame's app log and compares them with the window. |
| `Sources/Views.swift` | Main window, rows, and the Profile / Review / Log / Preview sheets. |
| `Sources/App.swift` | App entry point (wrapped in `#if !TESTING`) and the Facility Profile… menu command (⌘,). |
| `Sources/Helpers.swift` | Path cleanup, JSON/shell/AppleScript quoting, file panels. |
| `tools/make_icon.swift` | Draws the app icon (custom flame path plus SF Symbol gear) into `Resources/AppIcon.icns`. |
| `build.sh` | Builds `build/Flame Sysconfig Setup.app` (universal arm64 + x86_64, macOS 13+). |

## Build and test

```bash
./build.sh
```

- There's no Xcode project: `build.sh` calls `swiftc -parse-as-library` on `Sources/*.swift` per architecture, then `lipo`, writes Info.plist, and ad-hoc signs. `VERSION` and `BUILD` come from the environment (the release workflow sets them from the tag). The bundle ID is `io.github.flamelogik.flame-sysconfig-setup`, which is also the UserDefaults domain.
- **Signing happens in a temp dir.** Network volumes such as Avid NEXIS add extended attributes that `codesign` rejects ("resource fork, Finder information, or similar detritus"), even after `xattr -cr`. `build.sh` assembles and signs off the volume, then copies into `build/` with `ditto --norsrc --noextattr`.
- `build.sh` must stay executable in git (`git update-index --chmod=+x build.sh`). Network volumes like NEXIS don't keep Unix permissions, so `core.fileMode` is false and a plain commit loses the flag; the release workflow then fails with "Permission denied".
- The icon is generated when `Resources/AppIcon.icns` is missing. It's git-ignored (no binaries in the repo); delete it locally to redraw.
- SourceKit shows "cannot find type" errors per file because it doesn't see the other sources. Ignore them; `build.sh` is the real check.

**Headless logic tests:** compile the sources with `-D TESTING` (which drops `@main`) together with a scratch `main.swift` wrapped in `MainActor.assumeIsolated { … }`:

```bash
swiftc -swift-version 5 -D TESTING Sources/*.swift /path/to/scratch/main.swift -o /path/to/scratch/run
```

Useful checks:
- Load a real `sysconfig.cfg` and regenerate it: the JSON should be identical.
- `ConfigModel(cfgRoot:)` pointed at a fake folder containing `.2028/sysconfig.cfg` with extra keys proves discovery works.
- A `FacilityProfile` describing an existing facility's layout, then `fillFromProfile()`, should reproduce that facility's file.

Keep test scratch files out of the repo.

## How settings are handled (keep this design)

Settings come from three levels, so new Autodesk settings work without code changes:

1. **Built-in** (`Catalog.sections`): has descriptions and a `since` version.
2. **Discovered** (`SettingOrigin.installed`): keys found in `/opt/Autodesk/cfg/.<version>/sysconfig.cfg` that the catalog lacks. They get a generic description and a "New in X" badge, and whole new sections are created if needed.
3. **Loaded / preserved:** unknown string keys in a loaded file become `.loadedFile` rows. Non-string values (lists, booleans, whole non-object sections) go into `preserved` and are written back verbatim.

To describe a newly discovered setting, add it to `Catalog.sections`. Don't special-case it anywhere else.

Other rules worth knowing:

- **Facility profile:** `paths` is keyed by setting id (e.g. `nodebin_folders.pybox`) plus `saveFolder` and `configFolder`. Values are relative to `sharedRoot`; `.` is the root itself, a leading `/` is absolute, and blank means "leave the window alone". Individual `.cfg` files aren't in the profile; they follow the configuration folder. The profile is stored in UserDefaults under `facilityProfile` and exported/imported as pretty-printed JSON with a `format` version.
- **Configuration files** follow one `configFolder`. Only files missing from it, or overridden (`configOverrides`), get their own row. On load, the folder most `.cfg` paths share is chosen as `configFolder` and the rest become overrides.
- **"Oldest Flame version"** picker: items whose `since` is newer are dimmed and left out of the output.
- **Output JSON is hand-built** (not `JSONSerialization`) to keep Autodesk's key order and 2-space layout. `save()` parses the result as a sanity check before writing, and backs up an existing file as `sysconfig.cfg.bak_<timestamp>`.
- **Pointer:** `/opt/Autodesk/cfg/sysconfig.cfg` with only a versions entry redirects every Flame version on that Mac to the shared file. It's root-owned; the app writes it via `do shell script … with administrator privileges` and backs up any existing file first.
- **Flame log format:** `SYSCFG: <category words> <key> : <value>`, with categories `shared folder`, `nodebin folder`, `cfg file`, `configuration folder`, `project folders`. `SYS CONFIG : <path>` names the file Flame used. A key missing from the log means Flame used its built-in default.

## Logik org rules for this repo

The repo follows the Logik [repo standards](https://github.com/flamelogik/.github/blob/main/REPO_STANDARDS.md):

- **`main` is protected.** Every change goes through a branch and a squash-merged pull request.
- **Update `CHANGELOG.md` in the same PR**, newest first, under `[Unreleased]` until a release.
- **Keep the README's template sections**, and only mark a Flame version × OS as tested when it really was.
- **Never commit binaries.** That includes the built app and the generated icon. Releases come from `.github/workflows/release.yml`: pushing a `vX.Y.Z` tag on `main` builds the app on a macOS runner and publishes a GitHub Release with the zip and its SHA-256. The org only allows GitHub-owned and verified actions, and the default token is read-only, so the workflow declares `contents: write`.
- **No Autodesk-proprietary material, client media, secrets, or internal facility paths.**
- **The user merges PRs** (as an owner, with the rules bypass). Before syncing, tagging, or anything else that depends on a merge, check `gh pr view N --json state` says `MERGED`. Run that as its own step, not chained with `&&`: the command succeeds even when the PR is still open, and syncing an unmerged PR once switched the working copy to a `main` without the app.

## Releasing

1. **Test the workflow first.** Run it by hand on `main` or the release branch: `gh workflow run release.yml --ref BRANCH`. Download the artifact (`gh run download RUN_ID`) and check it:
   - `shasum -a 256 -c *.sha256`
   - `lipo -archs` should show `x86_64 arm64`
   - `codesign -v` should pass
   - `CFBundleShortVersionString` should be the expected version (`0.0.0` for manual runs)
   - the app should launch
2. **Open a release PR** that moves `[Unreleased]` in `CHANGELOG.md` to `[X.Y.Z] - YYYY-MM-DD` and updates `STATUS.md`.
3. **After it's merged and confirmed**, tag the merge commit with an annotated tag and push it: `git tag -a vX.Y.Z -m "Flame Sysconfig Setup X.Y.Z" <merge-sha> && git push origin vX.Y.Z`. The workflow builds the app and publishes the GitHub Release with `Flame-Sysconfig-Setup-X.Y.Z.zip`, its `.sha256`, and generated notes.
4. **Check the published release** by downloading it with `gh release download vX.Y.Z` and repeating the checks in step 1.

## Conventions

- Match the existing style: small focused files, `// MARK:` sections, doc comments only where the why isn't obvious.
- User-facing text uses plain, direct wording and names the exact path involved.
- Never modify `/opt/Autodesk/cfg/*` or a facility's shared `sysconfig.cfg` from a Claude session unless the user asks; the app is the intended way to change them.
