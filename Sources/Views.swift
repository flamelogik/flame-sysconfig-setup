// The main window and its sheets.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Rows

struct RowButton {
    let title: String
    let help: String
    let action: () -> Void
}

struct PathRow: View {
    let title: String
    var key: String?
    let summary: String
    @Binding var path: String
    var placeholder = ""
    var badge: String?
    var badgeTint: Color = .secondary
    var status: PathStatus?
    let choose: () -> Void
    var extra: RowButton?
    var reset: (() -> Void)?
    var resetHelp = "Reset to the Autodesk default"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline)
                if let key { Text(key).font(.caption.monospaced()).foregroundStyle(.secondary) }
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(badgeTint.opacity(0.18)))
                        .foregroundStyle(badgeTint)
                }
                Spacer()
                if let status { StatusLabel(status: status) }
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("", text: $path, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                if let extra {
                    Button(extra.title, action: extra.action).help(extra.help)
                }
                Button("Choose…", action: choose)
                if let reset {
                    Button(action: reset) { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless)
                        .help(resetHelp)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusLabel: View {
    let status: PathStatus

    var body: some View {
        switch status {
        case .found:
            Label("Found", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .missing:
            Label("Not found", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                .help("Nothing exists at this path yet. Flame creates missing folders at launch if it has permission.")
        case .tokens:
            Label("Uses tokens", systemImage: "curlybraces").foregroundStyle(.blue).font(.caption)
                .help("Resolved by Flame at runtime, so it can't be checked here.")
        }
    }
}

// MARK: - Main window

struct InfoAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct SaveResult: Identifiable {
    let id = UUID()
    let url: URL
    let backup: URL?
}

struct ReviewData {
    let issues: [ReviewIssue]
    /// nil when there's no existing file to compare with.
    let changes: [DiffLine]?
}

enum ActiveSheet: Identifiable {
    case preview
    case profile
    case review(ReviewData)
    case log(FlameLogReport)

    var id: String {
        switch self {
        case .preview: return "preview"
        case .profile: return "profile"
        case .review: return "review"
        case .log: return "log"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ConfigModel
    @State private var sheet: ActiveSheet?
    @State private var saveResult: SaveResult?
    @State private var errorMessage: String?
    @State private var pointerPrompt: String?
    @State private var info: InfoAlert?
    @State private var confirmFill = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                setupSection
                ForEach(model.sections) { sectionView($0) }
                if !model.preserved.isEmpty { preservedSection }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Load Existing…", action: loadExisting)
                Button("Reset to Defaults") { model.resetAll() }
                Spacer()
                Button("Check Flame Log…", action: checkLog)
                    .help("Show which sysconfig.cfg and settings Flame used at its last launch on this Mac")
                Button("Preview…") { sheet = .preview }
                Button("Save sysconfig.cfg", action: startSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanPath(model.saveFolder).isEmpty)
            }
            .padding(12)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .preview:
                PreviewSheet(json: model.makeJSON())
            case .profile:
                ProfileSheet().environmentObject(model)
            case .review(let data):
                ReviewSheet(data: data, destination: model.destinationURL.path) {
                    self.sheet = nil
                    DispatchQueue.main.async(execute: performSave)
                }
            case .log(let report):
                LogReportSheet(report: report).environmentObject(model)
            }
        }
        .onChange(of: model.showProfileEditor) { show in
            guard show else { return }
            model.showProfileEditor = false
            sheet = .profile
        }
        .alert("Fill Paths from \(model.profile.displayName)?", isPresented: $confirmFill) {
            Button("Fill") { model.fillFromProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sets \(model.profileFillCount) paths under \(cleanPath(model.profile.sharedRoot)). Paths the profile leaves blank are unchanged, and nothing is saved until you click Save.")
        }
        .alert("sysconfig.cfg Saved",
               isPresented: Binding(get: { saveResult != nil }, set: { if !$0 { saveResult = nil } }),
               presenting: saveResult) { result in
            if model.pointerState(for: result.url) != .pointsHere {
                Button("Install Pointer on This Mac…") { DispatchQueue.main.async(execute: startInstallPointer) }
            }
            Button("Copy Pointer Text") { copyToPasteboard(model.pointerJSON(to: result.url)) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result.url]) }
            Button("OK", role: .cancel) {}
        } message: { result in
            Text(savedMessage(result))
        }
        .alert("Install Pointer on This Mac?",
               isPresented: Binding(get: { pointerPrompt != nil }, set: { if !$0 { pointerPrompt = nil } }),
               presenting: pointerPrompt) { _ in
            Button("Install") { DispatchQueue.main.async(execute: performInstallPointer) }
            Button("Cancel", role: .cancel) {}
        } message: { Text($0) }
        .alert(info?.title ?? "",
               isPresented: Binding(get: { info != nil }, set: { if !$0 { info = nil } }),
               presenting: info) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0.message) }
        .alert("Couldn't Continue",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
               presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    // MARK: Sections

    private var setupSection: some View {
        Section {
            profileRow
            PathRow(
                title: "Save Location",
                summary: "Folder on shared storage that every Flame workstation can reach. The file is saved here as sysconfig.cfg, and its versions entry points back to itself.",
                path: $model.saveFolder,
                placeholder: model.profile.resolve(FacilityProfile.saveKey) ?? "/Volumes/YourShare/flame/cfg",
                status: cleanPath(model.saveFolder).isEmpty ? nil : model.status(ofPath: model.saveFolder, kind: .folder),
                choose: {
                    if let p = chooseFolder(message: "Choose where sysconfig.cfg will be saved", startingAt: model.saveFolder) {
                        model.saveFolder = p
                    }
                })
            VStack(alignment: .leading, spacing: 4) {
                Picker("Oldest Flame version that will read this file", selection: $model.target) {
                    ForEach(model.versions) { Text($0.label).tag($0) }
                }
                Text("Settings added in later releases are dimmed and left out of the file, so older versions don't see keys they don't recognise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            pointerRow
        } header: {
            Text("Setup")
        }
    }

    private var profileRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Facility Profile").font(.headline)
                Text(model.profile.isSet
                     ? "\(model.profile.displayName): \(cleanPath(model.profile.sharedRoot))"
                     : "Not set up. Describe where your facility keeps its shared Flame files once, then fill every path below in one click.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.profile.isSet {
                Button("Fill Paths…") { confirmFill = true }
                    .disabled(model.profileFillCount == 0)
            }
            Button(model.profile.isSet ? "Edit…" : "Set Up…") { sheet = .profile }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var pointerRow: some View {
        let hasTarget = !cleanPath(model.saveFolder).isEmpty
        let state = model.pointerState(for: model.destinationURL)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pointer on This Mac").font(.headline)
                Text(hasTarget ? model.pointerDescription(state) : "Choose a save location to check this Mac's pointer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if hasTarget && state == .pointsHere {
                Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            } else {
                Button("Install Pointer…", action: startInstallPointer)
                    .disabled(!hasTarget)
                    .help("Creates \(ConfigModel.pointerURL.path) so every Flame version on this Mac reads the saved file. Needs an administrator password.")
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionView(_ section: SettingSection) -> some View {
        Section {
            if section.key == "configuration_files" {
                configFileRows(section)
            } else {
                standardRows(section)
            }
            if section.key == "shared_folders" { sharedOverrideRows }
        } header: {
            Text(section.title)
        } footer: {
            if !section.footer.isEmpty {
                Text(section.footer).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func badge(for item: SettingItem) -> (String, Color) {
        guard model.isIncluded(item) else { return ("Needs \(item.since.label)", .secondary) }
        switch item.origin {
        case .builtIn: return ("\(item.since.label)+", .secondary)
        case .installed: return ("New in \(item.since.label)", .purple)
        case .loadedFile: return ("From loaded file", .purple)
        }
    }

    private func standardRows(_ section: SettingSection) -> some View {
        ForEach(section.items) { item in
            let included = model.isIncluded(item)
            let (badge, tint) = badge(for: item)
            PathRow(
                title: item.title,
                key: item.key,
                summary: item.summary,
                path: model.binding(item),
                placeholder: item.defaultValue,
                badge: badge,
                badgeTint: tint,
                status: included ? model.status(ofPath: model.outputValue(item), kind: item.kind) : nil,
                choose: { choose(item) },
                reset: { model.values[item.id] = item.defaultValue })
            .disabled(!included)
            .opacity(included ? 1 : 0.45)
        }
    }

    /// One folder for all .cfg files; only files missing from it, or overridden, get their own row.
    @ViewBuilder private func configFileRows(_ section: SettingSection) -> some View {
        let included = section.items.filter(model.isIncluded)
        let found = included.filter { !model.isOverridden($0) && model.existsInConfigFolder($0) }
        let separate = included.filter { model.isOverridden($0) || !model.existsInConfigFolder($0) }
        let copyable = separate.filter { !model.isOverridden($0) && model.copySource(for: $0) != nil }
        let excluded = section.items.filter { !model.isIncluded($0) }

        PathRow(
            title: "Configuration Files Folder",
            summary: "Folder holding Flame's .cfg files (batch.cfg, tags.cfg, colour_coding.cfg…). Every file is read from here unless you override it. Files missing from this folder are listed below so you can point to them.",
            path: $model.configFolder,
            placeholder: ConfigModel.defaultConfigFolder,
            status: model.status(ofPath: model.configFolder, kind: .folder),
            choose: {
                if let p = chooseFolder(message: "Choose the folder that holds the .cfg files", startingAt: model.configFolder) {
                    model.configFolder = p
                }
            },
            reset: { model.configFolder = ConfigModel.defaultConfigFolder })

        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Found in This Folder").font(.headline)
                    Spacer()
                    Text("\(found.count) of \(included.count)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(found) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(fileName(item)).font(.body.monospaced())
                        Text(item.title).foregroundStyle(.secondary)
                        Spacer()
                        Button("Override…") { chooseConfigOverride(item) }
                            .controlSize(.small)
                            .help(item.summary)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        if copyable.count > 1 {
            HStack {
                Text("\(copyable.count) missing files can be copied from this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy All Missing") { copyMissing(copyable) }
                    .help("Copies each file from /opt/Autodesk/cfg, or Autodesk's sample if there's no local copy. Existing files are never overwritten.")
            }
        }

        ForEach(separate) { item in
            let overridden = model.isOverridden(item)
            let source = overridden ? nil : model.copySource(for: item)
            let (badge, tint) = badge(for: item)
            PathRow(
                title: item.title,
                key: item.key,
                summary: overridden ? item.summary : "Not in the folder above. \(item.summary)",
                path: model.overrideBinding(item),
                placeholder: model.folderPath(item),
                badge: badge,
                badgeTint: tint,
                status: model.status(ofPath: model.outputValue(item), kind: item.kind),
                choose: { chooseConfigOverride(item) },
                extra: source.map { src in
                    RowButton(title: "Copy from This Mac",
                              help: "Copies \(src.path) into the Configuration Files Folder.",
                              action: { copyMissing([item]) })
                },
                reset: overridden ? { model.configOverrides[item.id] = nil } : nil,
                resetHelp: "Read this file from the Configuration Files Folder again")
        }

        if !excluded.isEmpty {
            Text("Left out for Flame \(model.target.label): " +
                 excluded.map { "\(fileName($0)) (\($0.since.label)+)" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var sharedOverrideRows: some View {
        ForEach($model.sharedOverrides) { $override in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Subfolder Override").font(.headline)
                    TextField("", text: $override.name, prompt: Text("subfolder"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .labelsHidden()
                        .frame(width: 160)
                    Spacer()
                    Button { model.removeOverride(override.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove this override")
                }
                Text("Reroutes only the \(override.name.isEmpty ? "chosen" : override.name) subfolder of the shared tree. Keep the same folder structure inside it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("", text: $override.path, prompt: Text("/path/to/folder"))
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    Button("Choose…") {
                        if let p = chooseFolder(message: "Choose the folder for shared/\(override.name)", startingAt: override.path) {
                            override.path = p
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Menu("Add Subfolder Override") {
            ForEach(model.availableOverrideNames, id: \.self) { name in
                Button(name) { model.addOverride(name) }
            }
        }
        .fixedSize()
        .disabled(model.availableOverrideNames.isEmpty)
    }

    private var preservedSection: some View {
        Section {
            ForEach(model.preserved) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.key.map { "\(entry.section) › \($0)" } ?? entry.section).font(.headline)
                    Text(entry.json)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Kept As-Is")
        } footer: {
            Text("These values in the loaded file aren't plain paths, so this tool can't edit them. They're saved unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func fileName(_ item: SettingItem) -> String {
        if case .file(let name) = item.kind { return name }
        return item.key
    }

    // MARK: Actions

    private func choose(_ item: SettingItem) {
        guard let folder = chooseFolder(message: "Choose the folder for \(item.title)",
                                        startingAt: model.outputValue(item)) else { return }
        model.values[item.id] = item.kind.path(inFolder: folder)
    }

    private func chooseConfigOverride(_ item: SettingItem) {
        guard let folder = chooseFolder(message: "Choose the folder that holds \(fileName(item))",
                                        startingAt: model.outputValue(item)) else { return }
        let path = item.kind.path(inFolder: folder)
        model.configOverrides[item.id] = path == model.folderPath(item) ? nil : path
    }

    private func copyMissing(_ items: [SettingItem]) {
        var failed: [String] = []
        for item in items {
            do { try model.copyMissing(item) } catch { failed.append("\(fileName(item)): \(error.localizedDescription)") }
        }
        if !failed.isEmpty { errorMessage = failed.joined(separator: "\n") }
    }

    private func loadExisting() {
        guard let url = chooseFile(message: "Choose an existing sysconfig.cfg to edit",
                                   startingAt: model.saveFolder) else { return }
        do { try model.load(from: url) } catch { errorMessage = error.localizedDescription }
    }

    private func checkLog() {
        guard let url = FlameLog.newestAppLog() else {
            errorMessage = "No Flame app log was found in \(FlameLog.logDir.path). Launch Flame on this Mac first."
            return
        }
        do { sheet = .log(try FlameLog.parse(url)) } catch { errorMessage = error.localizedDescription }
    }

    private func startSave() {
        do {
            try model.validateSaveFolder()
            let data = ReviewData(issues: model.reviewIssues(), changes: model.changesFromExisting())
            if data.issues.isEmpty && data.changes == nil {
                performSave()
            } else {
                sheet = .review(data)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performSave() {
        do {
            let backup = try model.save()
            saveResult = SaveResult(url: model.destinationURL, backup: backup)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startInstallPointer() {
        let target = model.destinationURL
        guard FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "Save sysconfig.cfg first. The pointer must point to a file that exists (\(target.path))."
            return
        }
        let state = model.pointerState(for: target)
        if state == .pointsHere {
            info = InfoAlert(title: "Already Installed", message: model.pointerDescription(state))
            return
        }
        let replacing = state == .none ? "" : "\(model.pointerDescription(state)) It will be backed up and replaced.\n\n"
        pointerPrompt = "\(replacing)Every Flame version on this Mac will then read its settings from \(target.path).\n\nYou'll be asked for an administrator password."
    }

    private func performInstallPointer() {
        let target = model.destinationURL
        do {
            if try model.installPointer(to: target) {
                info = InfoAlert(title: "Pointer Installed",
                                 message: "\(ConfigModel.pointerURL.path) now points to \(target.path). Restart Flame, then use Check Flame Log to confirm. Repeat this on each Flame workstation.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savedMessage(_ result: SaveResult) -> String {
        var msg = "Saved to \(result.url.path)."
        if let backup = result.backup { msg += "\n\nThe previous file was backed up as \(backup.lastPathComponent)." }
        if model.pointerState(for: result.url) == .pointsHere {
            msg += "\n\nThis Mac already points to it. Restart Flame to pick up the changes, and install the same pointer on each other workstation."
        } else {
            msg += "\n\nEach Flame workstation needs a pointer at \(ConfigModel.pointerURL.path) that redirects Flame here. Use Install Pointer on This Mac, or Copy Pointer Text to create it by hand."
        }
        return msg
    }
}

// MARK: - Sheets

struct ProfileSheet: View {
    @EnvironmentObject var model: ConfigModel
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Facility name", text: $model.profile.name, prompt: Text("e.g. your studio's name"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shared Root").font(.headline)
                        Text("The folder on shared storage where your facility keeps Flame's shared files. Every path below is relative to it.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            TextField("", text: $model.profile.sharedRoot, prompt: Text("/Volumes/YourShare/flame"))
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            Button("Choose…") {
                                if let p = chooseFolder(message: "Choose your facility's shared root", startingAt: model.profile.sharedRoot) {
                                    model.profile.sharedRoot = p
                                }
                            }
                            if model.profile.isSet {
                                StatusLabel(status: model.status(ofPath: model.profile.sharedRoot, kind: .folder))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Facility")
                }

                Section {
                    ForEach(model.profileKeys, id: \.key) { entry in
                        layoutRow(key: entry.key, title: entry.title)
                    }
                } header: {
                    Text("Layout Inside the Shared Root")
                } footer: {
                    Text("\".\" is the shared root itself. A path starting with / is used as-is. Leave a row blank to keep whatever the main window has. Configuration files follow the Configuration Files Folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Import…", action: importProfile)
                    .help("Load a profile exported from another workstation")
                Button("Export…", action: exportProfile)
                    .help("Save this profile as a file other workstations can import")
                Button("Suggested Layout") { model.profile.paths = FacilityProfile.suggestedLayout }
                    .help("Replace the layout with the app's suggested one")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 640)
        .alert("Couldn't Continue",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
               presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func layoutRow(key: String, title: String) -> some View {
        let binding = Binding(get: { model.profile.paths[key] ?? "" },
                              set: { model.profile.paths[key] = $0 })
        let resolved = model.profile.resolve(key)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).frame(width: 230, alignment: .leading)
                TextField("", text: binding, prompt: Text("blank: leave unchanged"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .labelsHidden()
            }
            if let resolved {
                HStack(spacing: 6) {
                    Text(resolved).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    Spacer()
                    if !resolved.contains("<") {
                        StatusLabel(status: model.status(ofPath: resolved, kind: .folder))
                    }
                }
                .padding(.leading, 238)
            }
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(model.profile.displayName) Flame Profile.json"
        panel.message = "Export this facility profile so other workstations can import it"
        panel.directoryURL = existingAncestor(of: model.profile.sharedRoot)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.profile.export(to: url) } catch { errorMessage = error.localizedDescription }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a facility profile exported from Flame Sysconfig Setup"
        panel.directoryURL = existingAncestor(of: model.profile.sharedRoot)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.profile = try FacilityProfile.importing(from: url) } catch { errorMessage = error.localizedDescription }
    }
}

struct ReviewSheet: View {
    let data: ReviewData
    let destination: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Before Saving").font(.title3.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(data.issues) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text(issue.detail).font(.callout).foregroundStyle(.secondary)
                            ForEach(issue.items, id: \.self) {
                                Text("• \($0)").font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                    if let changes = data.changes {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Changes to the existing file", systemImage: "arrow.left.arrow.right")
                                .font(.headline)
                            Text("\(destination) will be backed up, then replaced.")
                                .font(.callout).foregroundStyle(.secondary)
                            if changes.isEmpty {
                                Text("No setting changes.").font(.callout)
                            }
                            ForEach(changes) { change in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(change.key).font(.callout.bold())
                                    if let old = change.old {
                                        Text("− \(old)").font(.caption.monospaced()).foregroundStyle(.red)
                                    }
                                    if let new = change.new {
                                        Text("+ \(new)").font(.caption.monospaced()).foregroundStyle(.green)
                                    }
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(data.issues.isEmpty ? "Save" : "Save Anyway", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 700, height: 560)
    }
}

struct LogReportSheet: View {
    let report: FlameLogReport
    @EnvironmentObject var model: ConfigModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let comparison = model.compare(with: report)
        let usesThisFile = report.sysconfigUsed == model.destinationURL.path
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Flame Launch on This Mac").font(.title3.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text("Log: \(report.logURL.path)").font(.caption.monospaced()).foregroundStyle(.secondary)
                if let launched = report.launched {
                    Text("Launched: \(launched)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let used = report.sysconfigUsed {
                Label {
                    Text("Flame used \(used)").textSelection(.enabled)
                } icon: {
                    Image(systemName: usesThisFile ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(usesThisFile ? .green : .orange)
                }
                .font(.headline)
                if !usesThisFile {
                    Text("That isn't the file in this window's save location (\(model.destinationURL.path)).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Label("The log doesn't say which sysconfig.cfg Flame used.", systemImage: "questionmark.circle")
                    .font(.headline)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(comparison.matches) settings match the values in this window.")
                        .font(.callout)
                    ForEach(report.problems, id: \.self) {
                        Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption.monospaced())
                    }
                    ForEach(comparison.differences) { diff in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(diff.key).font(.callout.bold())
                            switch diff.kind {
                            case .differs:
                                Text("Flame used:  \(diff.flame ?? "")").font(.caption.monospaced()).foregroundStyle(.orange)
                                Text("This window: \(diff.tool ?? "")").font(.caption.monospaced())
                            case .notInLog:
                                Text("Not in the log, so Flame used its built-in default. Saving and restarting Flame will apply \(diff.tool ?? "").")
                                    .font(.caption).foregroundStyle(.secondary)
                            case .unknownToTool:
                                Text("Flame used \(diff.flame ?? ""), but this window doesn't set it.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                    }
                    if comparison.differences.isEmpty {
                        Text("Flame is running with exactly these settings.").font(.callout).foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            Text("Compared with the values currently in this window, including unsaved changes. Flame only reads sysconfig.cfg at launch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show Log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([report.logURL]) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 700, height: 580)
    }
}

struct PreviewSheet: View {
    let json: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("sysconfig.cfg Preview").font(.headline)
            ScrollView {
                Text(json)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Spacer()
                Button("Copy") { copyToPasteboard(json) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 680, height: 560)
    }
}
