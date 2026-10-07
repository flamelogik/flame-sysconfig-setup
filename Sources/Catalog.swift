// What the tool knows about sysconfig.cfg settings, plus discovery of settings added by newer Flame releases.

import Foundation

// MARK: - Versions

/// A Flame release, parsed from strings like "2027", "2027.1" or "2027.2.pr250".
struct FlameVersion: Comparable, Hashable, Identifiable {
    let major: Int
    let minor: Int

    init(_ major: Int, _ minor: Int = 0) {
        self.major = major
        self.minor = minor
    }

    /// Parses the leading "year[.minor]" part; returns nil for anything that isn't a Flame version.
    init?(parsing s: String) {
        let parts = s.split(separator: ".")
        guard let first = parts.first, let major = Int(first), major >= 2000 else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    }

    var id: String { label }
    var label: String { minor == 0 ? "\(major)" : "\(major).\(minor)" }
    static func < (a: Self, b: Self) -> Bool { (a.major, a.minor) < (b.major, b.minor) }

    static let v2025 = FlameVersion(2025), v2025_1 = FlameVersion(2025, 1), v2025_2 = FlameVersion(2025, 2)
    static let v2026 = FlameVersion(2026), v2026_1 = FlameVersion(2026, 1), v2026_2 = FlameVersion(2026, 2)
    static let v2027 = FlameVersion(2027)
}

// MARK: - Settings

enum PathKind {
    /// The value is the chosen folder itself.
    case folder
    /// The value is a file with this name inside the chosen folder.
    case file(String)
    /// The value is the chosen folder plus a token suffix, e.g. "/<project name>".
    case tokenFolder(suffix: String)

    func path(inFolder folder: String) -> String {
        let base = folder == "/" ? "" : folder
        switch self {
        case .folder: return folder
        case .file(let name): return base + "/" + name
        case .tokenFolder(let suffix): return base + suffix
        }
    }
}

enum SettingOrigin: Equatable {
    /// Described by this tool.
    case builtIn
    /// Found in an installed Flame's default sysconfig.cfg (e.g. ".2027.2") but unknown to this tool.
    case installed(String)
    /// Only found in a loaded sysconfig.cfg.
    case loadedFile
}

struct SettingItem: Identifiable {
    let section: String
    let key: String
    let title: String
    let kind: PathKind
    let defaultValue: String
    let since: FlameVersion
    let summary: String
    var origin: SettingOrigin = .builtIn
    var id: String { "\(section).\(key)" }
}

struct SettingSection: Identifiable {
    let key: String
    let title: String
    let footer: String
    var items: [SettingItem]
    var id: String { key }
}

/// Turns "grab_reference" into "Grab Reference".
func humanize(_ key: String) -> String {
    key.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
}

enum Catalog {
    /// Fallback list of /opt/Autodesk/shared subfolders, used when this Mac has no local copy to compare with.
    static let sharedSubfolders = [
        "action", "batch", "bookmarks", "burn_metadata", "colour_mgmt", "export", "fbx",
        "import", "inference", "modular_keyer", "paint", "presets", "python",
    ]

    static let versions: [FlameVersion] = [.v2025, .v2025_1, .v2025_2, .v2026, .v2026_1, .v2026_2, .v2027]

    static let sections: [SettingSection] = [
        SettingSection(
            key: "shared_folders", title: "Shared Folders",
            footer: "If this location is unreachable when Flame launches, Flame silently falls back to the factory paths.",
            items: [
                item("shared_folders", "default", "Shared Folders Root", .folder, "/opt/Autodesk/shared", .v2025,
                     "Root of Flame's shared tree: Python hooks, export/import presets, bookmarks, colour management and more. Must keep the same subfolder layout as /opt/Autodesk/shared."),
            ]),
        SettingSection(
            key: "nodebin_folders", title: "Node Bins",
            footer: "Tokens such as <user>, <project> and <workstation> can be typed into these paths.",
            items: [
                item("nodebin_folders", "action_import_geometry", "Action › Import Geometry", .folder,
                     "/opt/Autodesk/presets/<VERSION>/models", .v2025,
                     "Start folder of Action's Import Geometry browser (FBX, Alembic, OBJ and other 3D models)."),
                item("nodebin_folders", "action_lightbox", "Action › Lightbox", .folder,
                     "/opt/Autodesk/presets/<VERSION>/action/lightbox", .v2025,
                     "Lightbox shaders (.lx) listed in Action's Lightbox node bin."),
                item("nodebin_folders", "action_matchbox", "Action › Matchbox", .folder,
                     "/opt/Autodesk/presets/<VERSION>/matchbox/shaders", .v2025,
                     "Matchbox shaders listed in Action's Matchbox node bin."),
                item("nodebin_folders", "matchbox", "Batch › Matchbox", .folder,
                     "/opt/Autodesk/presets/<VERSION>/matchbox/shaders", .v2025,
                     "Matchbox shaders (.glsl / .xml) listed in the Batch Matchbox node bin."),
                item("nodebin_folders", "pybox", "Batch › Pybox", .folder,
                     "/opt/Autodesk/presets/<VERSION>/pybox", .v2025,
                     "Pybox handler scripts (.py) listed in the Batch Pybox node bin."),
            ]),
        SettingSection(
            key: "configuration_files", title: "Configuration Files",
            footer: "Overrides ask for a folder; the standard file name is added for you.",
            items: [
                cfg("batch", "Batch", .v2026_2,
                    "Batch defaults: Render and Write File node naming and media/setup path patterns."),
                cfg("channelrules", "Channel Rules", .v2025_1,
                    "Assigns channel types (Beauty, Matte, Motion…) to multi-channel clips based on channel names."),
                cfg("colour_coding", "Colour Coding", .v2025_1,
                    "Automatic colour-coding rules for timeline segments and Media Panel entries."),
                cfg("colour_mgmt_displays", "Colour Management Displays", .v2026,
                    "Viewing transforms for the graphics, broadcast and scopes monitors."),
                cfg("custom_tokens", "Custom Tokens", .v2027,
                    "Custom naming tokens (e.g. <timeline>) usable in name and path patterns."),
                cfg("default_colour_mgmt_settings", "Default Colour Management Settings", .v2026,
                    "Default colour policy settings such as the locked policy and look search path."),
                cfg("export_snapshot", "Export Snapshot", .v2026_1,
                    "Defaults for Export Snapshot: destination, name pattern, preset and overlays."),
                cfg("grab_reference", "Grab Reference", .v2027,
                    "Defaults for Grab Reference: name pattern, annotations, view transform and frame mode. Not in the manual, but present in Flame 2027's default sysconfig."),
                cfg("media_panel", "Media Panel", .v2026_2,
                    "Default reels and shelves created in new libraries, desktops and Batch."),
                cfg("project_templates", "Project Templates", .v2026,
                    "Templates offered in the Create New Project dialog (paths, resolution, settings)."),
                cfg("resolutions_custom", "Custom Resolutions", .v2025_1,
                    "Custom resolutions added to Flame's resolution presets."),
                cfg("tags", "Tags", .v2025_2,
                    "Predefined tag lists for the Media Panel, Timeline and Project Management."),
            ]),
        SettingSection(
            key: "configuration_folders", title: "Configuration Folders",
            footer: "",
            items: [
                item("configuration_folders", "font", "Fonts", .folder, "/opt/Autodesk/font", .v2025_2,
                     "Home of the Load Font browser and the Select Font widget's Shared tab. Also searched when a Text setup's font can't be found."),
            ]),
        SettingSection(
            key: "project_folders", title: "Project Folders",
            footer: "These only pre-fill the Create New Project dialog. Existing projects keep the paths they were created with. Tokens: <project name>, <project home>, <hostname>, <host ip>, <workstation>.",
            items: [
                item("project_folders", "default_home", "Project Home (local)", .tokenFolder(suffix: "/<project name>"),
                     "/var/opt/Autodesk/flame/projects/<project name>", .v2026,
                     "Proposed project root when the project server is this workstation."),
                item("project_folders", "default_remote_home", "Project Home (remote)", .tokenFolder(suffix: "/<project name>"),
                     "/hosts/<host ip>/var/opt/Autodesk/flame/projects/<project name>", .v2026,
                     "Proposed project root when the project server is another host."),
                item("project_folders", "default_setups_dir", "Setups Folder", .tokenFolder(suffix: "/<project name>/setups"),
                     "<project home>/setups", .v2026,
                     "Proposed setups folder for new projects. <project home> is the resolved project root."),
                item("project_folders", "default_media_cache", "Media Cache", .tokenFolder(suffix: "/<project name>/media"),
                     "<project home>/media", .v2026,
                     "Proposed media cache for new projects. Keep this on fast storage."),
            ]),
    ]

    private static func item(_ section: String, _ key: String, _ title: String, _ kind: PathKind,
                             _ defaultValue: String, _ since: FlameVersion, _ summary: String) -> SettingItem {
        SettingItem(section: section, key: key, title: title, kind: kind,
                    defaultValue: defaultValue, since: since, summary: summary)
    }

    private static func cfg(_ key: String, _ title: String, _ since: FlameVersion, _ summary: String) -> SettingItem {
        item("configuration_files", key, title, .file("\(key).cfg"),
             "/opt/Autodesk/cfg/\(key).cfg", since, summary)
    }

    /// Builds a row for a setting this tool has no description for.
    static func discoveredItem(section: String, key: String, defaultValue: String,
                               since: FlameVersion, origin: SettingOrigin) -> SettingItem {
        let kind: PathKind
        if section == "configuration_files" {
            let name = URL(fileURLWithPath: defaultValue).lastPathComponent
            kind = .file(name.hasSuffix(".cfg") ? name : "\(key).cfg")
        } else {
            kind = .folder
        }
        let summary: String
        switch origin {
        case .installed(let dir):
            summary = "New setting found in Flame's default sysconfig.cfg (\(dir)). This tool doesn't describe it yet; check the Flame release notes."
        case .loadedFile:
            summary = "Found in the loaded sysconfig.cfg. This tool doesn't describe it yet, but it will be saved."
        case .builtIn:
            summary = ""
        }
        return SettingItem(section: section, key: key, title: humanize(key), kind: kind,
                           defaultValue: defaultValue, since: since, summary: summary, origin: origin)
    }
}

// MARK: - Discovery from installed Flame versions

enum Discovery {
    static let cfgRoot = URL(fileURLWithPath: "/opt/Autodesk/cfg")

    struct Template {
        let version: FlameVersion
        let dirName: String
        let settings: [String: Any]
    }

    /// Default sysconfig.cfg files written by each installed Flame, oldest version first.
    static func installedTemplates(root: URL = cfgRoot) -> [Template] {
        versionDirs(root: root).compactMap { dir, version in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("sysconfig.cfg")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let settings = (json["configuration"] as? [String: Any])?["settings"] as? [String: Any]
            else { return nil }
            return Template(version: version, dirName: dir.lastPathComponent, settings: settings)
        }
    }

    /// Autodesk's sample for a .cfg file from the newest installed version that ships one.
    static func newestSample(named name: String, root: URL = cfgRoot) -> URL? {
        versionDirs(root: root).reversed()
            .map { $0.0.appendingPathComponent(name + ".sample") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Version names of the Flames installed on this Mac, e.g. "2027.1" or "2027.2.pr250", oldest first.
    /// These are what Flame substitutes for the `<VERSION>` token.
    static func installedVersionNames(root: URL = cfgRoot) -> [String] {
        versionDirs(root: root).map { String($0.0.lastPathComponent.dropFirst()) }
    }

    /// Hidden per-version folders such as ".2027.1", oldest first (resolving symlinks like ".current").
    private static func versionDirs(root: URL) -> [(URL, FlameVersion)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names
            .filter { $0.hasPrefix(".") }
            .compactMap { name in FlameVersion(parsing: String(name.dropFirst())).map { (root.appendingPathComponent(name), $0) } }
            .sorted { ($0.1, $0.0.lastPathComponent) < ($1.1, $1.0.lastPathComponent) }
    }
}

// MARK: - Tokens in the versions section

/// Resolves the tokens Flame accepts in a sysconfig `versions` entry, for one Flame version on this Mac.
enum VersionTokens {
    /// What Flame substitutes for `<OS>`. It's lowercase ("macos" / "linux"), not "macOS" as the help says.
    static let os = "macos"

    static func hasTokens(_ s: String) -> Bool {
        ["<VERSION>", "<MAJOR>", "<MINOR>", "<OS>"].contains { s.contains($0) }
    }

    static func resolve(_ s: String, version: String) -> String {
        let parsed = FlameVersion(parsing: version)
        return s
            .replacingOccurrences(of: "<VERSION>", with: version)
            .replacingOccurrences(of: "<MAJOR>", with: parsed.map { "\($0.major)" } ?? version)
            .replacingOccurrences(of: "<MINOR>", with: parsed.map { "\($0.minor)" } ?? "0")
            .replacingOccurrences(of: "<OS>", with: os)
    }

    /// The file a `versions` section sends this Flame version to, or nil if no entry matches it.
    static func target(in versions: [String: String], for version: String) -> String? {
        for (key, path) in versions.sorted(by: { $0.key < $1.key }) where resolve(key, version: version) == version {
            return resolve(path, version: version)
        }
        return nil
    }

    /// "2027.2.pr250" → "2027.2", for display.
    static func label(_ version: String) -> String {
        FlameVersion(parsing: version)?.label ?? version
    }
}
