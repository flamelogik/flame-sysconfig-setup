// Small shared utilities: path cleanup, quoting, file panels.

import AppKit

func cleanPath(_ s: String) -> String {
    var p = s.trimmingCharacters(in: .whitespacesAndNewlines)
    while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
    return p
}

/// Paths on this Mac's own disk, which other workstations can't see.
func isLocalPath(_ p: String) -> Bool {
    let prefixes = ["/opt/", "/var/", "/usr/", "/etc/", "/tmp/", "/private/", "/Users/", "/Applications/", "/Library/", "/System/"]
    return prefixes.contains { p.hasPrefix($0) || p + "/" == $0 }
}

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: Date())
}

func jsonString(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
        }
    }
    return out + "\""
}

/// Compact JSON for a value this tool doesn't edit.
func rawJSON(_ value: Any) -> String {
    let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
}

func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptString(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

/// Nearest existing folder at or above a path, ignoring anything from the first token onward.
func existingAncestor(of path: String) -> URL? {
    var p = cleanPath(path)
    if let r = p.range(of: "<") { p = String(p[..<r.lowerBound]) }
    guard p.hasPrefix("/") else { return nil }
    var url = URL(fileURLWithPath: p)
    while url.path != "/" {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        url.deleteLastPathComponent()
    }
    return nil
}

@MainActor
func chooseFolder(message: String, startingAt path: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = message
    panel.prompt = "Choose"
    panel.directoryURL = existingAncestor(of: path)
    return panel.runModal() == .OK ? panel.url?.path : nil
}

@MainActor
func chooseFile(message: String, startingAt path: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.message = message
    panel.prompt = "Load"
    panel.directoryURL = existingAncestor(of: path)
    return panel.runModal() == .OK ? panel.url : nil
}

func copyToPasteboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
