// Reads the SYSCFG lines Flame writes to its app log at startup, to confirm which settings it actually used.

import Foundation

struct FlameLogReport {
    let logURL: URL
    /// Timestamp of the startup, as written in the log (e.g. "09/24/26:12:45:50").
    let launched: String?
    /// The sysconfig.cfg whose settings Flame used ("SYS CONFIG" line).
    let sysconfigUsed: String?
    /// "section.key" → value Flame used.
    let values: [String: String]
    let problems: [String]
}

struct LogComparison: Identifiable {
    enum Kind { case differs, notInLog, unknownToTool }
    let id = UUID()
    let key: String
    let kind: Kind
    let flame: String?
    let tool: String?
}

enum FlameLog {
    static let logDir = URL(fileURLWithPath: "/opt/Autodesk/log")

    /// Log wording → sysconfig section. Unrecognised wording falls back to underscores ("new thing" → "new_thing").
    private static let sections = [
        "shared folder": "shared_folders",
        "nodebin folder": "nodebin_folders",
        "cfg file": "configuration_files",
        "configuration folder": "configuration_folders",
        "project folders": "project_folders",
    ]

    /// The most recently written "<version>_<workstation>_app.log".
    static func newestAppLog(in dir: URL = logDir) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls
            .filter { $0.lastPathComponent.hasSuffix("_app.log") }
            .max { modified($0) < modified($1) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    static func parse(_ url: URL) throws -> FlameLogReport {
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        var values: [String: String] = [:]
        var used: String?
        var launched: String?
        var problems: [String] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let r = line.range(of: "SYS CONFIG : ") {
                used = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                launched = line.range(of: #"\d\d/\d\d/\d\d:\d\d:\d\d:\d\d"#, options: .regularExpression).map { String(line[$0]) }
                continue
            }
            guard let r = line.range(of: "SYSCFG: ") else {
                if line.localizedCaseInsensitiveContains("sysconfig"),
                   line.range(of: "error|invalid|fail", options: [.regularExpression, .caseInsensitive]) != nil {
                    problems.append(String(line))
                }
                continue
            }
            let rest = String(line[r.upperBound...])
            if rest.hasPrefix("Reading system config file") || rest.hasPrefix("Ignoring settings") { continue }
            if rest.range(of: "error|invalid|fail|warning", options: [.regularExpression, .caseInsensitive]) != nil {
                problems.append(rest)
                continue
            }
            // "<category words> <key> : <value>"
            guard let sep = rest.range(of: " : ") else { continue }
            let left = rest[..<sep.lowerBound].split(separator: " ")
            guard left.count >= 2, let key = left.last else { continue }
            let category = left.dropLast().joined(separator: " ")
            let section = sections[category] ?? category.replacingOccurrences(of: " ", with: "_")
            values["\(section).\(key)"] = String(rest[sep.upperBound...])
        }
        return FlameLogReport(logURL: url, launched: launched, sysconfigUsed: used, values: values, problems: problems)
    }
}

extension ConfigModel {
    /// Compares what Flame used at its last launch with the values currently in this window.
    func compare(with report: FlameLogReport) -> (matches: Int, differences: [LogComparison]) {
        var tool: [String: String] = [:]
        for item in allItems where isIncluded(item) { tool[item.id] = outputValue(item) }
        for o in sharedOverrides where !cleanPath(o.name).isEmpty && !cleanPath(o.path).isEmpty {
            tool["shared_folders.\(cleanPath(o.name))"] = cleanPath(o.path)
        }

        var matches = 0
        var diffs: [LogComparison] = []
        for key in Set(tool.keys).union(report.values.keys).sorted() {
            let label = key.replacingOccurrences(of: ".", with: " › ")
            switch (report.values[key], tool[key]) {
            case let (f?, t?) where f == t: matches += 1
            case let (f?, t?): diffs.append(LogComparison(key: label, kind: .differs, flame: f, tool: t))
            case let (nil, t?): diffs.append(LogComparison(key: label, kind: .notInLog, flame: nil, tool: t))
            case let (f?, nil): diffs.append(LogComparison(key: label, kind: .unknownToTool, flame: f, tool: nil))
            default: break
            }
        }
        return (matches, diffs)
    }
}
