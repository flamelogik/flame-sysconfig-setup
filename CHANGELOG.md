# Changelog

Notable changes to this project, newest first. Versions follow [semantic versioning](https://semver.org): MAJOR for breaking changes, MINOR for new features, PATCH for fixes.

## [Unreleased]

First public release, planned as v1.0.0.

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
