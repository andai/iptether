import IPTetherCore
import SwiftUI

/// The Settings window. Toggles and pickers save at once; text fields save on Return or
/// when they lose focus. Everything lands in config.json, which the engine reads.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralTab(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            CloudsTab(model: model)
                .tabItem { Label("Clouds", systemImage: "cloud") }
            ProductionTab(model: model)
                .tabItem { Label("Production", systemImage: "exclamationmark.shield") }
            AdvancedTab(model: model)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520)
        .safeAreaInset(edge: .bottom) {
            if let error = model.configError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    let model: AppModel
    @State private var loginError: String?

    private let intervals = [60, 180, 300, 900, 1800]

    var body: some View {
        Form {
            Section {
                CommitField("Tag", text: model.config.tag) { value in
                    model.update { $0.tag = value }
                }
                Text("Marks the rules IPTether owns: ssh-autosync:\(model.config.tag) on AWS, ssh-autosync-\(model.config.tag) on Azure. Changing it leaves rules under the old tag behind.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CommitField("SSH port", text: String(model.config.port)) { value in
                    if let port = Int(value) { model.update { $0.port = port } }
                }
            }

            Section("Automatic updates") {
                Toggle("Keep my IP up to date", isOn: Binding(
                    get: { model.config.schedule.automatic },
                    set: { model.setAutomatic($0) }
                ))
                Picker("Check every", selection: Binding(
                    get: { model.config.schedule.intervalSeconds },
                    set: { value in model.update { $0.schedule.intervalSeconds = value } }
                )) {
                    ForEach(intervals, id: \.self) { seconds in
                        Text(seconds < 3600 ? "\(seconds / 60) min" : "1 hour").tag(seconds)
                    }
                }
                Toggle("Sync when the network changes", isOn: Binding(
                    get: { model.config.schedule.syncOnNetworkChange },
                    set: { value in model.update { $0.schedule.syncOnNetworkChange = value } }
                ))
                Toggle("Full sweep once a day", isOn: Binding(
                    get: { model.config.schedule.dailySweep != nil },
                    set: { on in model.update { $0.schedule.dailySweep = on ? "09:30" : nil } }
                ))
                if let sweep = model.config.schedule.dailySweep {
                    CommitField("Sweep at (HH:mm)", text: sweep) { value in
                        model.update { $0.schedule.dailySweep = value }
                    }
                }
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { loginError = model.setLaunchAtLogin($0) }
                ))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Clouds

private struct CloudsTab: View {
    let model: AppModel
    @State private var regions: [String] = []
    @State private var subscriptions: [AzureSubscription] = []
    @State private var awsError: String?
    @State private var azureError: String?
    @State private var loading = false

    var body: some View {
        Form {
            Section("AWS") {
                Toggle("Manage AWS security groups", isOn: Binding(
                    get: { model.config.aws.enabled },
                    set: { value in model.update { $0.aws.enabled = value } }
                ))
                cliStatus("aws")
                Toggle("Every enabled region", isOn: Binding(
                    get: { model.config.aws.regions.isEmpty },
                    set: { all in model.update { $0.aws.regions = all ? [] : regions.prefix(1).map { $0 } } }
                ))
                .disabled(!model.config.aws.enabled)
                if !model.config.aws.regions.isEmpty {
                    if regions.isEmpty {
                        Text("Selected: \(model.config.aws.regions.joined(separator: ", "))")
                            .font(.caption)
                    }
                    ForEach(regions, id: \.self) { region in
                        Toggle(region, isOn: membership(region, in: \.aws.regions))
                    }
                }
                Button("Load Regions") { Task { await loadRegions() } }
                    .disabled(loading || !Discovery.hasCLI("aws"))
                if let awsError { Text(awsError).font(.caption).foregroundStyle(.orange) }
            }

            Section("Azure") {
                Toggle("Manage Azure network security groups", isOn: Binding(
                    get: { model.config.azure.enabled },
                    set: { value in model.update { $0.azure.enabled = value } }
                ))
                cliStatus("az")
                Toggle("Every enabled subscription", isOn: Binding(
                    get: { model.config.azure.subscriptions.isEmpty },
                    set: { all in model.update { $0.azure.subscriptions = all ? [] : subscriptions.prefix(1).map(\.id) } }
                ))
                .disabled(!model.config.azure.enabled)
                if !model.config.azure.subscriptions.isEmpty {
                    if subscriptions.isEmpty {
                        Text("Selected: \(model.config.azure.subscriptions.joined(separator: ", "))")
                            .font(.caption)
                    }
                    ForEach(subscriptions) { sub in
                        Toggle(isOn: membership(sub.id, in: \.azure.subscriptions)) {
                            VStack(alignment: .leading) {
                                Text(sub.name)
                                Text(sub.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Load Subscriptions") { Task { await loadSubscriptions() } }
                    .disabled(loading || !Discovery.hasCLI("az"))
                if let azureError { Text(azureError).font(.caption).foregroundStyle(.orange) }
            }

            Text("IPTether uses the aws and az command-line tools with whatever account they're signed in to. It never sees or stores credentials.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func cliStatus(_ name: String) -> some View {
        if Discovery.hasCLI(name) {
            Label("\(name) found", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        } else {
            Label("\(name) isn't installed (brew install \(name == "aws" ? "awscli" : "azure-cli"))", systemImage: "xmark.circle")
                .foregroundStyle(.orange)
        }
    }

    private func membership(_ item: String, in keyPath: WritableKeyPath<IPTetherConfig, [String]>) -> Binding<Bool> {
        Binding(
            get: { model.config[keyPath: keyPath].contains(item) },
            set: { on in
                model.update { config in
                    var list = config[keyPath: keyPath].filter { $0 != item }
                    if on { list.append(item) }
                    config[keyPath: keyPath] = list
                }
            }
        )
    }

    private func loadRegions() async {
        loading = true
        defer { loading = false }
        do {
            regions = try await Discovery.awsRegions()
            awsError = nil
        } catch {
            awsError = error.localizedDescription
        }
    }

    private func loadSubscriptions() async {
        loading = true
        defer { loading = false }
        do {
            subscriptions = try await Discovery.azureSubscriptions().filter { $0.state == "Enabled" }
            azureError = nil
        } catch {
            azureError = error.localizedDescription
        }
    }
}

// MARK: - Production

private struct ProductionTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Leave production firewalls alone", isOn: Binding(
                    get: { model.config.prod.exclude },
                    set: { value in model.update { $0.prod.exclude = value } }
                ))
                Text("On production firewalls IPTether adds nothing and removes its own rule if it finds one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("A firewall counts as production when") {
                CommitField("Its name matches", text: model.config.prod.namePattern) { value in
                    model.update { $0.prod.namePattern = value }
                }
                CommitField("Or a tag named", text: model.config.prod.tagKeys.joined(separator: ", ")) { value in
                    model.update { $0.prod.tagKeys = splitList(value) }
                }
                CommitField("Is set to", text: model.config.prod.tagValues.joined(separator: ", ")) { value in
                    model.update { $0.prod.tagValues = splitList(value) }
                }
                Text("Names use a regular expression; tags are comma-separated. Matching ignores case.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!model.config.prod.exclude)

            Section("Manage anyway") {
                CommitField("Firewall names or IDs", text: model.config.prod.allow.joined(separator: ", ")) { value in
                    model.update { $0.prod.allow = splitList(value) }
                }
            }
            .disabled(!model.config.prod.exclude)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Finding your public IP") {
                CommitField("Lookup services", text: model.config.ipServices.joined(separator: ", ")) { value in
                    model.update { $0.ipServices = splitList(value) }
                }
                // a new identity resets the field's draft when the saved list changes (e.g. Restore Defaults)
                .id(model.config.ipServices)
                Text("Tried in order until one answers with your IP as plain text. These services see your public IP. Only https:// addresses are allowed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restore Defaults") {
                    model.update { $0.ipServices = IPTetherConfig.defaultIPServices }
                }
                .disabled(model.config.ipServices == IPTetherConfig.defaultIPServices)
            }

            Section("Files") {
                LabeledContent("Settings", value: model.paths.configFile.path)
                LabeledContent("Log", value: model.paths.logFile.path)
                HStack {
                    Button("Show Settings File") { model.openConfigFolder() }
                    Button("Open Log") { model.openLog() }
                }
            }
            Section {
                Text("config.json can also be edited by hand; IPTether reads it again at the next launch. The same file works with the command-line engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Helpers

/// A text field that saves on Return or when it loses focus, not on every keystroke.
private struct CommitField: View {
    let title: String
    let commit: (String) -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(_ title: String, text: String, commit: @escaping (String) -> Void) {
        self.title = title
        self.commit = commit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField(title, text: $draft)
            .focused($focused)
            .onSubmit { commit(draft.trimmingCharacters(in: .whitespaces)) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(draft.trimmingCharacters(in: .whitespaces)) }
            }
    }
}

private func splitList(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}
