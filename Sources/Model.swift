// State of the sysconfig being edited, and everything that reads or writes files.

import SwiftUI
import AppKit

struct SharedOverride: Identifiable {
    let id = UUID()
    var name: String
    var path: String
}

/// A loaded value this tool can't edit (not a plain path), written back unchanged.
struct PreservedEntry: Identifiable {
    let id = UUID()
    let section: String
    /// nil when the whole section isn't a key/value object.
    let key: String?
    let json: String
}

struct ToolError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum PathStatus {
    case found, missing, tokens
}

enum PointerState: Equatable {
    case none, pointsHere, pointsElsewhere([String]), ownSettings, invalid
}

struct ReviewIssue: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let items: [String]
}

struct DiffLine: Identifiable {
    let id = UUID()
    let key: String
    let old: String?
    let new: String?
}

@MainActor
final class ConfigModel: ObservableObject {
    static let defaultConfigFolder = "/opt/Autodesk/cfg"
    static let pointerURL = URL(fileURLWithPath: "/opt/Autodesk/cfg/sysconfig.cfg")
    private static let lastFileKey = "lastSysconfigPath"

    /// Built-in sections merged with settings discovered in installed Flame versions.
    let baseSections: [SettingSection]
    /// Flame versions offered in the "oldest version" picker.
    let versions: [FlameVersion]
    private let cfgRoot: URL

    @Published var sections: [SettingSection]
    @Published var values: [String: String] = [:]
    @Published var sharedOverrides: [SharedOverride] = []
    /// Folder every configuration file is read from unless overridden.
    @Published var configFolder = ConfigModel.defaultConfigFolder
    /// Configuration files that live somewhere other than `configFolder` (item id → file path).
    @Published var configOverrides: [String: String] = [:]
    @Published var preserved: [PreservedEntry] = []
    @Published var saveFolder = ""
    @Published var target: FlameVersion
    /// This user's facility profile; saved whenever it changes.
    @Published var profile = FacilityProfile.loadSaved() {
        didSet { profile.saveToDefaults() }
    }
    /// Set by the menu command to open the profile editor.
    @Published var showProfileEditor = false

    init(cfgRoot: URL = Discovery.cfgRoot) {
        self.cfgRoot = cfgRoot
        let templates = Discovery.installedTemplates(root: cfgRoot)
        var sections = Catalog.sections
        for template in templates {
            for (sectionKey, value) in template.settings.sorted(by: { $0.key < $1.key }) {
                guard let dict = value as? [String: Any] else { continue }
                for (key, v) in dict.sorted(by: { $0.key < $1.key }) {
                    guard let path = v as? String else { continue }
                    Self.merge(into: &sections, section: sectionKey, key: key, value: path,
                               since: template.version, origin: .installed(template.dirName))
                }
            }
        }
        baseSections = sections
        versions = Array(Set(Catalog.versions + templates.map(\.version))).sorted()
        target = versions.last ?? .v2027
        self.sections = sections
        resetAll()
    }

    func resetAll() {
        sections = baseSections
        values = Dictionary(uniqueKeysWithValues: sections.flatMap(\.items).map { ($0.id, $0.defaultValue) })
        sharedOverrides = []
        configFolder = Self.defaultConfigFolder
        configOverrides = [:]
        preserved = []
    }

    /// Re-render after something changed on disk (copied files, installed pointer).
    func refresh() { objectWillChange.send() }

    /// Adds a setting the catalog doesn't know about, creating its section if needed. No-op if it exists.
    private static func merge(into sections: inout [SettingSection], section: String, key: String, value: String,
                              since: FlameVersion, origin: SettingOrigin) {
        if section == "shared_folders" && key != "default" { return } // subfolder overrides, handled separately
        let index = ensureSection(section, in: &sections)
        guard !sections[index].items.contains(where: { $0.key == key }) else { return }
        sections[index].items.append(Catalog.discoveredItem(section: section, key: key, defaultValue: value,
                                                            since: since, origin: origin))
    }

    @discardableResult
    private static func ensureSection(_ key: String, in sections: inout [SettingSection]) -> Int {
        if let i = sections.firstIndex(where: { $0.key == key }) { return i }
        sections.append(SettingSection(
            key: key, title: humanize(key),
            footer: "A section this tool doesn't describe yet. Its settings are kept and saved.",
            items: []))
        return sections.count - 1
    }

    func binding(_ item: SettingItem) -> Binding<String> {
        Binding(get: { self.values[item.id] ?? item.defaultValue },
                set: { self.values[item.id] = $0 })
    }

    func isIncluded(_ item: SettingItem) -> Bool { item.since <= target }

    var allItems: [SettingItem] { sections.flatMap(\.items) }

    // MARK: Configuration files

    static func isConfigFile(_ item: SettingItem) -> Bool { item.section == "configuration_files" }

    /// Where a configuration file would be if it followed the shared config folder.
    func folderPath(_ item: SettingItem) -> String {
        item.kind.path(inFolder: cleanPath(configFolder))
    }

    func isOverridden(_ item: SettingItem) -> Bool { configOverrides[item.id] != nil }

    func existsInConfigFolder(_ item: SettingItem) -> Bool {
        status(ofPath: folderPath(item), kind: item.kind) == .found
    }

    func overrideBinding(_ item: SettingItem) -> Binding<String> {
        Binding(get: { self.configOverrides[item.id] ?? self.folderPath(item) },
                set: { self.configOverrides[item.id] = $0 })
    }

    /// Best local copy of a missing .cfg: this Mac's live file, else Autodesk's newest .sample.
    func copySource(for item: SettingItem) -> URL? {
        guard case .file(let name) = item.kind else { return nil }
        let local = URL(fileURLWithPath: Self.defaultConfigFolder).appendingPathComponent(name)
        if cleanPath(configFolder) != Self.defaultConfigFolder,
           FileManager.default.fileExists(atPath: local.path) {
            return local
        }
        return Discovery.newestSample(named: name, root: cfgRoot)
    }

    /// Copies a missing .cfg into the configuration folder. Never overwrites.
    func copyMissing(_ item: SettingItem) throws {
        guard let source = copySource(for: item) else {
            throw ToolError("No copy of \(item.key).cfg was found on this Mac.")
        }
        let dest = URL(fileURLWithPath: folderPath(item))
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try FileManager.default.copyItem(at: source, to: dest)
        refresh()
    }

    /// Value written to the file; a blank field falls back to the Autodesk default.
    func outputValue(_ item: SettingItem) -> String {
        if Self.isConfigFile(item) {
            let v = cleanPath(configOverrides[item.id] ?? "")
            if !v.isEmpty { return v }
            return cleanPath(configFolder).isEmpty ? item.defaultValue : folderPath(item)
        }
        let v = cleanPath(values[item.id] ?? "")
        return v.isEmpty ? item.defaultValue : v
    }

    var sysconfigPath: String {
        cleanPath(saveFolder) + "/sysconfig.cfg"
    }

    var availableOverrideNames: [String] {
        let used = Set(sharedOverrides.map(\.name))
        return sharedSubfolderNames.filter { !used.contains($0) }
    }

    /// Subfolders of this Mac's /opt/Autodesk/shared, or the built-in list if it has none.
    var sharedSubfolderNames: [String] {
        let local = (try? FileManager.default.contentsOfDirectory(atPath: "/opt/Autodesk/shared")) ?? []
        let dirs = local.filter { name in
            var isDir: ObjCBool = false
            return !name.hasPrefix(".")
                && FileManager.default.fileExists(atPath: "/opt/Autodesk/shared/\(name)", isDirectory: &isDir)
                && isDir.boolValue
        }
        return dirs.isEmpty ? Catalog.sharedSubfolders : dirs.sorted()
    }

    func addOverride(_ name: String) {
        sharedOverrides.append(SharedOverride(name: name, path: ""))
    }

    func removeOverride(_ id: UUID) {
        sharedOverrides.removeAll { $0.id == id }
    }

    // MARK: JSON output

    func makeJSON() -> String {
        func object(_ pairs: [(String, String)], indent: String) -> String {
            "{\n" + pairs.map { "\(indent)  \(jsonString($0.0)): \($0.1)" }.joined(separator: ",\n") + "\n\(indent)}"
        }

        var out: [(String, String)] = []
        for section in sections {
            var pairs = section.items.filter(isIncluded).map { ($0.key, jsonString(outputValue($0))) }
            if section.key == "shared_folders" {
                pairs += sharedOverrides
                    .map { (cleanPath($0.name), cleanPath($0.path)) }
                    .filter { !$0.0.isEmpty && !$0.1.isEmpty }
                    .map { ($0.0, jsonString($0.1)) }
            }
            pairs += preserved.filter { $0.section == section.key && $0.key != nil }.map { ($0.key!, $0.json) }
            if !pairs.isEmpty { out.append((section.key, object(pairs, indent: "      "))) }
        }
        out += preserved.filter { $0.key == nil }.map { ($0.section, $0.json) }

        let versions = object([("<VERSION>", jsonString(sysconfigPath))], indent: "    ")
        let settings = object(out, indent: "    ")
        return "{\n  \"configuration\": {\n    \"versions\": \(versions),\n    \"settings\": \(settings)\n  }\n}\n"
    }

    /// Contents of /opt/Autodesk/cfg/sysconfig.cfg on each workstation, redirecting Flame to the central file.
    func pointerJSON(to url: URL) -> String {
        "{\n  \"configuration\": {\n    \"versions\": {\n      \"<VERSION>\": \(jsonString(url.path))\n    }\n  }\n}\n"
    }

    // MARK: Save / load

    var destinationURL: URL {
        URL(fileURLWithPath: cleanPath(saveFolder)).appendingPathComponent("sysconfig.cfg")
    }

    func validateSaveFolder() throws {
        var isDir: ObjCBool = false
        guard !cleanPath(saveFolder).isEmpty else { throw ToolError("Choose where sysconfig.cfg should be saved.") }
        guard FileManager.default.fileExists(atPath: cleanPath(saveFolder), isDirectory: &isDir), isDir.boolValue else {
            throw ToolError("The save folder \(saveFolder) doesn't exist or isn't reachable.")
        }
    }

    /// Writes sysconfig.cfg, backing up any existing file first. Returns the backup URL if one was made.
    func save() throws -> URL? {
        try validateSaveFolder()
        let json = makeJSON()
        _ = try JSONSerialization.jsonObject(with: Data(json.utf8)) // sanity check before touching disk

        let fm = FileManager.default
        let dest = destinationURL
        var backup: URL?
        if fm.fileExists(atPath: dest.path) {
            let url = dest.deletingLastPathComponent()
                .appendingPathComponent("sysconfig.cfg.bak_\(timestamp())")
            try fm.copyItem(at: dest, to: url)
            backup = url
        }
        try json.write(to: dest, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(dest.path, forKey: Self.lastFileKey)
        return backup
    }

    func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = root["configuration"] as? [String: Any] else {
            throw ToolError("\(url.lastPathComponent) has no \"configuration\" section.")
        }
        guard let settings = config["settings"] as? [String: Any], !settings.isEmpty else {
            let versions = (config["versions"] as? [String: Any])?.values.compactMap { $0 as? String } ?? []
            if let target = versions.first {
                throw ToolError("This file has no settings. It only redirects Flame to \(target). Load that file instead.")
            }
            throw ToolError("\(url.lastPathComponent) has no \"settings\" section.")
        }

        resetAll()
        var newSections = sections
        var kept: [PreservedEntry] = []
        var overrides: [SharedOverride] = []
        var loaded: [String: String] = [:]

        for (sectionKey, sectionValue) in settings.sorted(by: { $0.key < $1.key }) {
            guard let dict = sectionValue as? [String: Any] else {
                kept.append(PreservedEntry(section: sectionKey, key: nil, json: rawJSON(sectionValue)))
                continue
            }
            Self.ensureSection(sectionKey, in: &newSections)
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                guard let path = value as? String else {
                    kept.append(PreservedEntry(section: sectionKey, key: key, json: rawJSON(value)))
                    continue
                }
                if sectionKey == "shared_folders" && key != "default" {
                    overrides.append(SharedOverride(name: key, path: path))
                    continue
                }
                Self.merge(into: &newSections, section: sectionKey, key: key, value: path,
                           since: versions.first ?? .v2025, origin: .loadedFile)
                loaded["\(sectionKey).\(key)"] = path
            }
        }

        sections = newSections
        for item in allItems {
            values[item.id] = loaded[item.id] ?? values[item.id] ?? item.defaultValue
            if loaded[item.id] != nil, item.since > target, versions.contains(item.since) { target = item.since }
        }
        if let cfgSection = sections.first(where: { $0.key == "configuration_files" }) {
            adoptConfigPaths(cfgSection.items.filter { loaded[$0.id] != nil })
        }
        sharedOverrides = overrides
        preserved = kept
        saveFolder = url.deletingLastPathComponent().path
        UserDefaults.standard.set(url.path, forKey: Self.lastFileKey)
    }

    /// Reopens the file from the previous session, if it's still there.
    func restoreLastSession() {
        guard let path = UserDefaults.standard.string(forKey: Self.lastFileKey),
              FileManager.default.fileExists(atPath: path) else { return }
        do {
            try load(from: URL(fileURLWithPath: path))
        } catch {
            saveFolder = URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
    }

    /// After loading, pick the folder most config files share and treat the rest as overrides.
    private func adoptConfigPaths(_ items: [SettingItem]) {
        let paths = items.compactMap { item in values[item.id].map { (item, cleanPath($0)) } }
        let folders = paths.map { URL(fileURLWithPath: $0.1).deletingLastPathComponent().path }
        let counts = Dictionary(folders.map { ($0, 1) }, uniquingKeysWith: +)
        if let common = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key {
            configFolder = common
        }
        configOverrides = [:]
        for (item, path) in paths where path != folderPath(item) {
            configOverrides[item.id] = path
        }
    }

    // MARK: Review before saving

    func reviewIssues() -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let save = cleanPath(saveFolder)
        if isLocalPath(save) {
            issues.append(ReviewIssue(
                title: "The save location is on this Mac's own disk",
                detail: "Other workstations can't read \(save). Choose a folder on shared storage.",
                items: []))
        }

        var local: [String] = []
        var missing: [String] = []
        for section in sections where section.key != "project_folders" {
            for item in section.items where isIncluded(item) {
                let v = outputValue(item)
                if isLocalPath(v) { local.append("\(item.key): \(v)") }
                if status(ofPath: v, kind: item.kind) == .missing { missing.append("\(item.key): \(v)") }
            }
        }
        for o in sharedOverrides where !cleanPath(o.path).isEmpty {
            let v = cleanPath(o.path)
            if isLocalPath(v) { local.append("shared \(o.name): \(v)") }
            if status(ofPath: v, kind: .folder) == .missing { missing.append("shared \(o.name): \(v)") }
        }
        if !local.isEmpty {
            issues.append(ReviewIssue(
                title: "Paths that are local to each workstation",
                detail: "Each Flame reads its own copy of these, so they won't be shared. That's fine if intended, for example factory presets.",
                items: local))
        }
        if !missing.isEmpty {
            issues.append(ReviewIssue(
                title: "Paths that don't exist",
                detail: "Flame tries to create missing folders at launch. Check these are spelled correctly.",
                items: missing))
        }

        if let rootItem = allItems.first(where: { $0.id == "shared_folders.default" }) {
            let root = outputValue(rootItem)
            if root != "/opt/Autodesk/shared", status(ofPath: root, kind: .folder) == .found {
                let rerouted = Set(sharedOverrides.map(\.name))
                let absent = sharedSubfolderNames.filter { name in
                    var isDir: ObjCBool = false
                    return !rerouted.contains(name)
                        && !(FileManager.default.fileExists(atPath: root + "/" + name, isDirectory: &isDir) && isDir.boolValue)
                }
                if !absent.isEmpty {
                    issues.append(ReviewIssue(
                        title: "The shared folder root is missing standard subfolders",
                        detail: "Flame expects the same layout as /opt/Autodesk/shared inside \(root).",
                        items: absent))
                }
            }
        }
        return issues
    }

    /// Differences between the file on disk and what would be saved; nil if there's no readable file.
    func changesFromExisting() -> [DiffLine]? {
        guard let data = try? Data(contentsOf: destinationURL),
              let old = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let new = try? JSONSerialization.jsonObject(with: Data(makeJSON().utf8)) else { return nil }
        let a = flatten(old), b = flatten(new)
        return Set(a.keys).union(b.keys).sorted()
            .filter { a[$0] != b[$0] }
            .map { DiffLine(key: $0, old: a[$0], new: b[$0]) }
    }

    private func flatten(_ json: Any) -> [String: String] {
        guard let config = (json as? [String: Any])?["configuration"] as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (part, value) in config {
            guard let dict = value as? [String: Any] else { out[part] = describe(value); continue }
            for (section, sectionValue) in dict {
                if part == "settings", let inner = sectionValue as? [String: Any] {
                    for (key, v) in inner { out["\(section) › \(key)"] = describe(v) }
                } else {
                    out["\(part) › \(section)"] = describe(sectionValue)
                }
            }
        }
        return out
    }

    private func describe(_ value: Any) -> String {
        (value as? String) ?? rawJSON(value)
    }

    // MARK: Pointer

    func pointerState(for target: URL) -> PointerState {
        guard let data = try? Data(contentsOf: Self.pointerURL) else { return .none }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = root["configuration"] as? [String: Any] else { return .invalid }
        let settings = (config["settings"] as? [String: Any]) ?? [:]
        if !settings.isEmpty { return .ownSettings }
        let targets = ((config["versions"] as? [String: Any]) ?? [:]).values.compactMap { $0 as? String }
        return targets == [target.path] ? .pointsHere : .pointsElsewhere(targets)
    }

    func pointerDescription(_ state: PointerState) -> String {
        let p = Self.pointerURL.path
        switch state {
        case .none: return "No \(p) yet, so Flame uses each version's own settings."
        case .pointsHere: return "\(p) points to this file, so Flame on this Mac uses it."
        case .pointsElsewhere(let t): return "\(p) points to \(t.joined(separator: ", "))."
        case .ownSettings: return "\(p) has its own settings, so Flame on this Mac ignores the shared file."
        case .invalid: return "\(p) isn't valid JSON."
        }
    }

    /// Writes the pointer file with administrator privileges. Returns false if the user cancelled the password prompt.
    func installPointer(to target: URL) throws -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sysconfig_pointer_\(UUID().uuidString).cfg")
        try pointerJSON(to: target).write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dest = shellQuote(Self.pointerURL.path)
        let backup = shellQuote(Self.pointerURL.path + ".bak_" + timestamp())
        let script = [
            "set -e",
            "mkdir -p \(shellQuote(Self.pointerURL.deletingLastPathComponent().path))",
            "if [ -e \(dest) ]; then cp -p \(dest) \(backup); fi",
            "cp \(shellQuote(tmp.path)) \(dest)",
            "chown root:wheel \(dest)",
            "chmod 644 \(dest)",
        ].joined(separator: "; ")

        let source = "do shell script \(appleScriptString(script)) with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        refresh()
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { return false }
            throw ToolError("Couldn't install the pointer: \(error[NSAppleScript.errorMessage] as? String ?? "unknown error")")
        }
        return true
    }

    // MARK: Status

    func status(ofPath raw: String, kind: PathKind) -> PathStatus {
        let path = cleanPath(raw)
        if path.contains("<") { return .tokens }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return .missing }
        if case .file = kind { return isDir.boolValue ? .missing : .found }
        return isDir.boolValue ? .found : .missing
    }
}
