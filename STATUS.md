# STATUS — Flame Sysconfig Setup

_Last updated: 2026-09-30_

## Where things stand

**Live at [`flamelogik/flame-sysconfig-setup`](https://github.com/flamelogik/flame-sysconfig-setup), the Logik org's first community repo. v1.0.0 is the first public release.** The code is complete; facility profiles were the last feature added, and everything specific to the facility it was first built for has been removed. Every other feature has been confirmed working in daily use with Flame 2027.2.

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
- On screen: main window, config-files checklist, missing-file rows and the override flow, pointer status, the Facility Profile row, and the icon.

## Next steps

1. **Publish v1.0.0.** After this release PR is merged, push the `v1.0.0` tag on `main`; the workflow publishes the Release. The workflow was verified by a manual run on 2026-09-30: the downloaded build passed its checksum, is universal and signed, and launches.
2. **Open starter issues** labeled `good first issue` / `help wanted` (MASTER_PLAN Phase 3), including "test on Flame 2025/2026 and report back", "test on an Intel Mac" and "add a screenshot to the README". Any screenshot must use a neutral demo profile, not a real facility's paths.
3. **Test as a new user.** On a Mac with no saved preferences: the profile row should say "Not set up", **Set Up…** should open the editor with the suggested layout, and export → import on a second Mac should work.
4. Check the Profile, Review and Check Flame Log windows by eye. They were verified through their data, not by clicking through them.
5. **Later: notarization.** It needs an Apple Developer ID; until then the README explains how to open the app.

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
