// Facility profile: where a facility keeps its shared Flame files, so every path can be filled in one click.

import Foundation

struct FacilityProfile: Codable, Equatable {
    var format = 1
    var name = ""
    /// Shared storage folder the layout is relative to, e.g. /Volumes/Studio/flame.
    var sharedRoot = ""
    /// Setting id (or `saveKey` / `configKey`) → path relative to `sharedRoot`.
    /// "." is the root itself, a leading "/" is used as-is, and blank leaves the window's value alone.
    var paths: [String: String] = FacilityProfile.suggestedLayout

    static let saveKey = "saveFolder"
    static let configKey = "configFolder"

    /// A starting layout for facilities that don't have one yet.
    static let suggestedLayout: [String: String] = [
        saveKey: "cfg",
        configKey: "cfg",
        "shared_folders.default": ".",
        "nodebin_folders.action_import_geometry": "models",
        "nodebin_folders.action_lightbox": "lightbox",
        "nodebin_folders.action_matchbox": "matchbox/shaders",
        "nodebin_folders.matchbox": "matchbox/shaders",
        "nodebin_folders.pybox": "pybox",
        "configuration_folders.font": "fonts",
    ]

    var isSet: Bool { !cleanPath(sharedRoot).isEmpty }

    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unnamed facility" : name }

    /// Full path for a key, or nil when the profile leaves it blank.
    func resolve(_ key: String) -> String? {
        guard isSet, let raw = paths[key] else { return nil }
        var rel = cleanPath(raw)
        if rel.isEmpty { return nil }
        if rel.hasPrefix("/") { return rel }
        let root = cleanPath(sharedRoot)
        if rel == "." { return root }
        if rel.hasPrefix("./") { rel.removeFirst(2) }
        return root + "/" + rel
    }

    // MARK: Storage

    private static let defaultsKey = "facilityProfile"

    static func loadSaved() -> FacilityProfile {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let profile = try? JSONDecoder().decode(FacilityProfile.self, from: data) else { return FacilityProfile() }
        return profile
    }

    func saveToDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func importing(from url: URL) throws -> FacilityProfile {
        do {
            return try JSONDecoder().decode(FacilityProfile.self, from: Data(contentsOf: url))
        } catch is DecodingError {
            throw ToolError("\(url.lastPathComponent) isn't a facility profile exported from this app.")
        }
    }
}

extension ConfigModel {
    /// Rows shown in the profile editor: save and config folders, then every non-.cfg setting.
    var profileKeys: [(key: String, title: String)] {
        [(FacilityProfile.saveKey, "Save Location"), (FacilityProfile.configKey, "Configuration Files Folder")]
            + sections.filter { $0.key != "configuration_files" }
                .flatMap(\.items)
                .map { ($0.id, "\($0.title)") }
    }

    /// Number of paths the profile would set.
    var profileFillCount: Int {
        profileKeys.filter { profile.resolve($0.key) != nil }.count
    }

    /// Sets every path the profile defines; paths it leaves blank are unchanged.
    func fillFromProfile() {
        if let p = profile.resolve(FacilityProfile.saveKey) { saveFolder = p }
        if let p = profile.resolve(FacilityProfile.configKey) {
            configFolder = p
            configOverrides = [:]
        }
        for item in allItems where !Self.isConfigFile(item) {
            if let p = profile.resolve(item.id) { values[item.id] = p }
        }
    }
}
