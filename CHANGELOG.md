# Changelog

Notable changes to this project, newest first. Versions follow [semantic versioning](https://semver.org): MAJOR for breaking changes, MINOR for new features, PATCH for fixes.

## [Unreleased]

## [1.0.1] - 2026-10-07

### Added
- A signed and notarized disk image, `Flame-Sysconfig-Setup-<version>.dmg`, so the app opens on other Macs without the Gatekeeper warning. `build.sh` signs with a Developer ID when `SIGN_IDENTITY` is set, and the new `package_dmg.sh` builds, notarizes and staples the image.

### Fixed
- **Pointer on This Mac** now understands pointers that use the `<OS>`, `<MAJOR>`, `<MINOR>` and `<VERSION>` tokens. It resolves them for each installed Flame version, shows which versions the pointer sends to the file being edited, and no longer offers to replace a pointer that already leads there.
- **Load Existing…** on a pointer that uses tokens now names the files it leads to on this Mac, instead of showing the raw tokens.

### Changed
- README: documents per-platform and per-version files, and that `<OS>` resolves to lowercase `macos` / `linux`, not "macOS or Linux" as Flame Help says. Thanks to jarak08 on the Logik forum.

## [1.0.0] - 2026-09-30

First public release.

### Added
- One row per `sysconfig.cfg` setting, with a description, folder picker, found / not found status and reset to the Autodesk default.
- Facility profile: a shared root plus layout that fills every path in one click. Saved per user; export and import as JSON.
- Configuration Files Folder: all `.cfg` files read from one folder, with per-file overrides, and copying of missing files from `/opt/Autodesk/cfg` or Autodesk's samples.
- Shared-folder subfolder overrides.
- "Oldest Flame version" setting, which leaves out settings newer than that version.
- Discovery of new settings from each installed Flame's default `sysconfig.cfg`, and preservation of unrecognised values in loaded files.
- Review before saving: local-only paths, missing paths, missing shared subfolders, and a diff against the existing file, which is backed up before being replaced.
- Pointer status and install for `/opt/Autodesk/cfg/sysconfig.cfg` (administrator password; backs up any existing file).
- Check Flame Log: which `sysconfig.cfg` Flame used at its last launch, and every setting that differs.
- Load Existing, Preview, and reopening the last file at launch.
- `build.sh` for a universal (Apple silicon + Intel) app, and a GitHub Actions workflow that publishes releases with a SHA-256 checksum.
