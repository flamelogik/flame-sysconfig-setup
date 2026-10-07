# STATUS — Flame Sysconfig Setup

_Last updated: 2026-10-07_

## Where things stand

**v1.0.1 is the current release** ([releases](https://github.com/flamelogik/flame-sysconfig-setup/releases)). v1.0.0 was published 2026-09-30. v1.0.1 (2026-10-07) makes the app understand pointers that use the `<OS>`, `<MAJOR>`, `<MINOR>` and `<VERSION>` tokens, after a Logik forum user reported that `<OS>` resolves to lowercase `macos` / `linux`. This is the Logik org's first community repo, [`flamelogik/flame-sysconfig-setup`](https://github.com/flamelogik/flame-sysconfig-setup). Facility profiles were the last feature added, and everything specific to the facility it was first built for has been removed. The app is marked as working with Flame 2025 to 2027.2 on macOS.

Four starter issues are open ([issues](https://github.com/flamelogik/flame-sysconfig-setup/issues)):
- #4 test on an Intel Mac
- #5 first-time-user walkthrough
- #7 signing and notarization
- #8 a mixed macOS / Rocky Linux facility

#6 (README screenshots) was closed by PR #10, which added four screenshots to the README.

The repo meets the Logik repo standards: README template sections, MIT `LICENSE` (Logik community contributors), `CHANGELOG.md`, `.github/CODEOWNERS`, and no binaries. Releases are built by `.github/workflows/release.yml` when a `vX.Y.Z` tag is pushed.

Build locally with `./build.sh` → `build/Flame Sysconfig Setup.app` (universal arm64 + x86_64, macOS 13+, ad-hoc signed).

### Features

- **Facility Profile:**
  - Set a shared root and where each item lives inside it, then **Fill Paths** sets the whole window in one click.
  - Saved per user; export/import as JSON so every workstation uses the same layout.
  - Starts from a suggested generic layout (`cfg`, `models`, `lightbox`, `matchbox/shaders`, `pybox`, `fonts`).
  - Opens from the Setup section or Facility Profile… (⌘,).
- One row per sysconfig path, each with a description, **Choose…**, a reset to the Autodesk default, and a found / not found / uses tokens status.
- Save location picker. The saved file's versions entry points back to itself.
- "Oldest Flame version" picker. Settings newer than that version are dimmed and left out of the file.
- **Configuration Files Folder:** one folder for all `.cfg` files. Files found there are shown as a checklist with **Override…**; missing or overridden files get full rows.
- **Copy from This Mac / Copy All Missing** for missing `.cfg` files. Copies from `/opt/Autodesk/cfg`, else Autodesk's newest `.sample`; never overwrites.
- Shared-folder subfolder overrides (e.g. only `python`).
- **Load Existing…** handles files that only point elsewhere, and restores the last-used file at launch.
- **Future-proofing:** discovers new settings from each installed Flame's default sysconfig, and keeps unknown keys and non-path values from loaded files (shown in "Kept As-Is").
- **Review Before Saving:** flags local-only paths, missing paths, a save location on a local disk, and missing standard subfolders in the shared root; shows old → new changes against the existing file.
- **Pointer on This Mac:** shows the current pointer state and **Install Pointer…** (admin password; backs up any existing pointer).
- **Check Flame Log…:** shows which sysconfig the last Flame launch used, and each setting that differs from the window.
- Preview / copy of the generated JSON, and an app icon (custom flame plus gear).

### Verified

- Headless logic tests all pass:
  - Loading and regenerating a real shared file gives identical JSON.
  - A simulated Flame 2028 install surfaces a new `.cfg` and a new section.
  - Unknown lists, booleans and keys survive a load and save.
  - Profile paths resolve correctly: `.`, `./sub`, absolute paths, tokens, and blank.
  - A profile survives export and import unchanged.
  - Importing a non-profile file gives a clear error.
  - Filling from a profile describing a real facility's layout reproduces that facility's live file exactly.
  - Pointer state detection and log parsing are correct.
  - Shell and AppleScript quoting handle `'` and `"` in paths.
- README screenshots (`docs/images/`) were taken from a demo setup on a disk image mounted at `/Volumes/SHARED_LOCATION`, so they show no real facility paths.
- On screen: main window, config-files checklist, missing-file rows and the override flow, pointer status, the Facility Profile row and editor, the Review window (issues and diff), and the icon.
- Pointer tokens (v1.0.1): headless tests of 13 pointer cases, including the reported `…/<OS>/<MAJOR>/…` pointer against macOS, Linux and wrongly cased paths, plain pointers, literal version keys and no Flame installed. The new wording wasn't checked in the running app, because that needs a Mac whose pointer uses tokens.
- Release: the v1.0.0 download from the release page passes its SHA-256 check, is universal (arm64 + x86_64), is ad-hoc signed, and reports version 1.0.0. A manual run of the workflow built an app that launched normally.

## Next steps

1. **Respond to the starter issues** as testers report back, and update the README's compatibility table when a new combination is tested (e.g. Intel, #4).
2. **Test as a new user.** On a Mac with no saved preferences: the profile row should say "Not set up", **Set Up…** should open the editor with the suggested layout, and export → import on a second Mac should work. Issue #5 asks the community for the same.
3. Check the Check Flame Log window by eye. It was verified through its data; the Profile and Review windows have now been seen on screen (README screenshots).
4. **Notarization** (#7) needs an Apple Developer ID; until then the README explains how to open the app.
5. For the next release, follow **Releasing** in `CLAUDE.md`.

## Decisions locked in

- **Public and facility-neutral.** Site details live only in the git-ignored `CLAUDE.local.md`. The private development history was not carried into the org repo, so no earlier facility details remain.
- **Hosted in the Logik org** (`flamelogik`), following its repo standards: protected `main`, squash-merged PRs, MIT license, releases built by GitHub Actions with a SHA-256 checksum.
- **Versions come from git tags.** The first public release is v1.0.0; "v1.1" and "v1.2" were private development builds.
- **Autodesk's help text isn't redistributed.** `sysconfig_manual.txt` is git-ignored; docs point to the Flame Help topic instead.
- **Facility profile stores relative paths** (with `.` and absolute paths allowed) so one exported profile works on every workstation that mounts the share at the same path. `.cfg` files aren't listed individually; they follow the configuration folder.
- **Native SwiftUI app built by `build.sh`**, with no Xcode project, so it can be rebuilt from Terminal. It's universal so it runs on any Flame Mac.
- **Config-file override paths ask for a folder**, and the standard file name is added.
- **Future-proofing uses the three-level design:** built-in → discovered from installed Flame → preserved from loaded file. New Autodesk settings need no code change; add them to `Catalog.swift` only to give them a description.
- **`grab_reference` is in the built-in catalog** (since 2027): it's in every Flame 2027 default sysconfig but not in Autodesk's help.
- **Pointer install goes through `do shell script … with administrator privileges`**, and always backs up an existing `/opt/Autodesk/cfg/sysconfig.cfg` first.
- **Bundle ID `io.github.flamelogik.flame-sysconfig-setup`**, matching the org.

## Findings about Flame's sysconfig (keep these)

- A `sysconfig.cfg` in `/opt/Autodesk/cfg/` takes precedence over every `/opt/Autodesk/cfg/.<version>/sysconfig.cfg`. The log shows `Ignoring settings in /opt/Autodesk/cfg/sysconfig.cfg` when that file only redirects elsewhere.
- Each installed version's `/opt/Autodesk/cfg/.<version>/sysconfig.cfg` holds the full default list of settings for that version, which makes it the best source for discovering new ones.
- The app log `/opt/Autodesk/log/flame<ver>_<host>_app.log` lists every setting Flame applied (`SYSCFG:` lines) and the file used (`SYS CONFIG :`). A new log is written at each launch; older ones rotate to `.1`, `.2`, and so on.
- Common mistakes the Review step is designed to catch: a folder name that doesn't match what's on disk (e.g. `font` vs `fonts`), a `.cfg` still pointing at the local `/opt/Autodesk/cfg`, and a node bin pointing at an empty folder.
