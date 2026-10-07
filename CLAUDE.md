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
| `build.sh` | Builds `build/Flame Sysconfig Setup.app` (universal arm64 + x86_64, macOS 13+). Ad-hoc signed unless `SIGN_IDENTITY` is set. |
| `package_dmg.sh` | Packages the built app into `build/Flame-Sysconfig-Setup-<version>.dmg`, and notarizes and staples it when `NOTARY_PROFILE` is set. |

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
- **Tokens in a pointer:** a `versions` entry may use `<VERSION>` (e.g. `2027.1`, or `2027.2.pr250` for a prerelease), `<MAJOR>`, `<MINOR>` and `<OS>`. **`<OS>` resolves to lowercase `macos` / `linux`**, not "macOS or Linux" as Flame Help says (confirmed from Flame's logs by a forum user). `VersionTokens` (in `Catalog.swift`) resolves them per installed version, and `ConfigModel.pointerState(pointerData:target:installed:)` is a pure function, so it can be tested with made-up pointers and version lists. A pointer that leads to the edited file for at least one installed version counts as installed (`PointerState.isInstalled`); never offer to replace it. The app always writes a plain, token-free pointer itself.
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
5. **Add the notarized disk image.** This is done on the maintainer's Mac, because the Developer ID certificate and notary credentials live in its keychain, not in the repo. The identity and profile names are in `CLAUDE.local.md`.
   - **Build from the tag.** Check that `git rev-parse HEAD` equals `git rev-parse 'vX.Y.Z^{commit}'` and `git status --porcelain` is empty. Then build signed: `VERSION=X.Y.Z SIGN_IDENTITY="Developer ID Application: …" ./build.sh`
   - **Package and notarize:** `NOTARY_PROFILE=<profile> ./package_dmg.sh`. Apple's queue has taken from a few minutes to a couple of hours, so run it in the background. `xcrun notarytool history --keychain-profile <profile>` shows the status meanwhile. The script staples the app, rebuilds the image around it, checks it with `stapler validate` and `spctl`, and writes a `.sha256`.
   - **Check it as a downloader would.** Copy the `.dmg` to a temp folder and mark it as downloaded: `xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;" FILE.dmg`. Mount it with `hdiutil attach -nobrowse -readonly`, `ditto` the app out, and run `spctl --assess --type execute -vvv` on that copy. It should say `accepted` and `source=Notarized Developer ID`. `xcrun stapler validate` should pass too. Opening that copy from a script won't start the app: macOS shows its one-time "downloaded from the Internet" prompt and waits for a click.
   - **Upload after the user agrees:** `gh release upload vX.Y.Z build/Flame-Sysconfig-Setup-X.Y.Z.dmg build/Flame-Sysconfig-Setup-X.Y.Z.dmg.sha256`. Then download it back with `gh release download vX.Y.Z --pattern '*.dmg*'`, and check that its SHA-256 equals the local file's and that the app inside still passes `spctl`.

   Notarization needs the hardened runtime. A test program signed the same way runs `do shell script` without extra entitlements. The app's own `do shell script … with administrator privileges` (Install Pointer) uses the same mechanism, but hasn't been run under the hardened runtime yet, so check `STATUS.md` before relying on it. Never put the certificate, its password or notary credentials in the repo or in GitHub secrets without the user deciding that.

   A release that only changes docs doesn't need a trial notarization first. The trial for v1.0.1 was to prove the process.

## Screenshots

README images live in `docs/images/`. They must never show a real facility's paths, share names or hostnames. To retake them:

1. **Back up the app's preferences:** `defaults export io.github.flamelogik.flame-sysconfig-setup backup.plist`. Quit the app first.
2. **Create a demo share without an admin password.** Make a disk image and mount it:
   - `hdiutil create -size 200m -fs APFS -volname SHARED_LOCATION -type SPARSE demo.sparseimage`
   - `hdiutil attach -nobrowse demo.sparseimage`

   It mounts at `/Volumes/SHARED_LOCATION`. Create the suggested layout inside it (`cfg`, `models`, `lightbox`, `matchbox/shaders`, `pybox`, `fonts`, plus the standard shared subfolders). Fill `cfg/` from Autodesk's `.cfg.sample` files. Their contents never appear on screen, and the image is never committed.
3. **Generate the demo state with the app's own code** (a `-D TESTING` scratch build): a `FacilityProfile` named "Demo Facility" rooted at `/Volumes/SHARED_LOCATION`, then `fillFromProfile()`, then write `makeJSON()` to `cfg/sysconfig.cfg`. Write the profile and `lastSysconfigPath` into the app's defaults, so it opens in that state.
4. **The pointer row reads this Mac's real `/opt/Autodesk/cfg/sysconfig.cfg`**, which shows the real share path. For the shot, temporarily make `pointerState` read a demo pointer file instead (e.g. via an environment variable passed with `open --env`), rebuild, and discard the change with `git checkout` straight afterwards. Never commit it.
5. **Capture** with `screencapture -x -o -l<windowID>`. A sheet is captured together with the window behind it. Claude can't click or scroll here, so ask the user to scroll, open sheets and close them. Crop with Pillow to the relevant card or sheet, and re-save from pixel data so no metadata is kept. Keep each image under about 500 KB.
6. **Restore everything:** quit the app, `git checkout` any temporary code, rebuild, re-import the preferences backup, and `hdiutil detach /Volumes/SHARED_LOCATION`.

## Conventions

- Match the existing style: small focused files, `// MARK:` sections, doc comments only where the why isn't obvious.
- User-facing text uses plain, direct wording and names the exact path involved.
- Never modify `/opt/Autodesk/cfg/*` or a facility's shared `sysconfig.cfg` from a Claude session unless the user asks; the app is the intended way to change them.
