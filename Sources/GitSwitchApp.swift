import SwiftUI
import AppKit

private enum Design {
    static let background = Color(red: 0.038, green: 0.044, blue: 0.049)
    static let sidebar = Color(red: 0.055, green: 0.060, blue: 0.066)
    static let surface = Color(red: 0.078, green: 0.084, blue: 0.089)
    static let stroke = Color(red: 0.205, green: 0.215, blue: 0.220)
    static let ink = Color(red: 0.952, green: 0.951, blue: 0.933)
    static let muted = Color(red: 0.59, green: 0.61, blue: 0.60)
    static let orange = Color(red: 0.83, green: 0.47, blue: 0.22)
    static let green = Color(red: 0.63, green: 0.74, blue: 0.57)
    static let danger = Color(red: 0.93, green: 0.49, blue: 0.42)
}

private extension View {
    func technicalPanel() -> some View {
        self.background(Design.surface)
            .overlay(Rectangle().stroke(Design.stroke, lineWidth: 1))
    }
}

private struct StandardTitlebar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }
    private func configure(_ window: NSWindow?) {
        guard let window = window else { return }
        window.title = "GitSwitch"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }
}

@main
struct GitSwitchApp: App {
    var body: some Scene {
        WindowGroup("GitSwitch") {
            Switchboard()
                .frame(minWidth: 940, minHeight: 640)
                .background(Design.background)
                .preferredColorScheme(.dark)
                .background(StandardTitlebar().frame(width: 0, height: 0))
        }
    }
}

private enum Screen: String, CaseIterable, Identifiable {
    case switcher = "SWITCH"
    case keyring = "KEYRING"
    case activity = "ACTIVITY"
    var id: String { rawValue }
    var systemIcon: String {
        switch self {
        case .switcher: return "arrow.left.arrow.right"
        case .keyring: return "key.horizontal"
        case .activity: return "terminal"
        }
    }
}

struct Switchboard: View {
    @State private var snapshot = GitSwitchSnapshot()
    @State private var selectedEmail = ""
    @State private var selectedKey = ""
    @State private var screen: Screen = .switcher
    @State private var isBusy = false
    @State private var information = "Ready. Select an email and a key, then apply."
    @State private var isError = false
    @State private var history: [String] = ["GitSwitch initialized. Changes are local to this Mac."]
    @State private var inspectKey: SSHIdentity?
    @State private var showEmailSheet = false
    @State private var showGenerateSheet = false

    private let core = GitSwitchCore()

    private var selectedIdentity: SSHIdentity? { snapshot.keys.first(where: { $0.path == selectedKey }) }
    private var currentIdentity: SSHIdentity? { snapshot.keys.first(where: { $0.path == snapshot.currentKeyPath }) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 197)
            Rectangle().fill(Design.stroke).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    heading
                    switch screen {
                    case .switcher: switchScreen
                    case .keyring: keyringScreen
                    case .activity: activityScreen
                    }
                    footer
                }
                .padding(.horizontal, 32)
                .padding(.top, 26)
                .padding(.bottom, 35)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Design.background)
        }
        .background(Design.background)
        .onAppear(perform: refresh)
        .sheet(item: $inspectKey) { key in
            PublicKeyWindow(key: key, keyText: (try? core.readPublicKey(key)) ?? "Unable to read public key")
        }
        .sheet(isPresented: $showEmailSheet) {
            NewEmailWindow { email in
                work("Add email") {
                    try core.addEmail(email)
                    return "Saved email: \(email)"
                }
            }
        }
        .sheet(isPresented: $showGenerateSheet) {
            NewKeyWindow { name, comment in
                work("Generate SSH key") {
                    let path = try core.createUnencryptedKey(fileName: name, comment: comment)
                    return "Created key pair: \(path). Copy the .pub key to GitHub, then verify it here."
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 43, height: 43)
                VStack(alignment: .leading, spacing: 4) {
                    Text("GITSWITCH")
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .tracking(-0.4)
                        .foregroundStyle(Design.ink)
                    Text("WORKSTATION / 03")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Design.muted)
                }
            }
            .padding(.horizontal, 17)
            .padding(.top, 27)
            .padding(.bottom, 30)

            thinLine
                .padding(.horizontal, 17)
            Text("CONTROL")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Design.muted)
                .padding(.horizontal, 18)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ForEach(Screen.allCases) { item in
                Button { screen = item } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.systemIcon).frame(width: 16)
                        Text(item.rawValue).tracking(0.7)
                        Spacer(minLength: 2)
                        if screen == item { Rectangle().fill(Design.orange).frame(width: 3, height: 16) }
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(screen == item ? Design.ink : Design.muted)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(screen == item ? Design.surface : Design.sidebar)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 24)
            thinLine.padding(.horizontal, 17)
            VStack(alignment: .leading, spacing: 8) {
                Text("LOCAL / MACOS")
                    .foregroundStyle(Design.ink)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("No cloud account required. Private keys stay on this machine.")
                    .font(.system(size: 10))
                    .foregroundStyle(Design.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .background(Design.sidebar)
    }

    private var thinLine: some View { Rectangle().fill(Design.stroke).frame(height: 1) }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Rectangle().fill(Design.orange).frame(width: 7, height: 7)
                Text("SYSTEM / GIT + GITHUB / V03")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(Design.muted)
                Spacer()
                Button { refresh() } label: {
                    Label("RESCAN", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Design.ink)
                .disabled(isBusy)
            }
            Text(screen == .switcher ? "Identity control." : screen == .keyring ? "SSH keyring." : "Activity log.")
                .font(.system(size: 37, weight: .bold, design: .default))
                .tracking(-1.2)
                .foregroundStyle(Design.ink)
                .lineLimit(1)
            Text(screen == .switcher
                 ? "Switch your commit identity and GitHub SSH authentication independently."
                 : screen == .keyring
                 ? "Discover, inspect, register and verify SSH identities."
                 : "Operations from this session. No credentials are logged.")
                .font(.system(size: 13))
                .foregroundStyle(Design.muted)
            thinLine
        }
    }

    private var switchScreen: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 0) {
                miniStatistic(number: "01", title: "GLOBAL GIT EMAIL", detail: snapshot.currentEmail)
                Rectangle().fill(Design.stroke).frame(width: 1)
                miniStatistic(number: "02", title: "DEFAULT GITHUB SSH",
                              detail: currentIdentity?.title ?? snapshot.sshConfigDescription)
                Rectangle().fill(Design.stroke).frame(width: 1)
                miniStatistic(number: "03", title: "DISCOVERED KEYS", detail: "\(snapshot.keys.count) local key pairs")
            }
            .frame(height: 90)
            .overlay(Rectangle().stroke(Design.stroke, lineWidth: 1))

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeading("01", title: "COMMIT EMAIL") {
                        showEmailSheet = true
                    } actionName: { "ADD" }
                    ForEach(snapshot.emails, id: \.self) { email in
                        choiceRow(title: email, subtitle: email == snapshot.currentEmail ? "CURRENT GLOBAL EMAIL" : "AVAILABLE EMAIL",
                                  selected: selectedEmail == email, icon: "at") {
                            selectedEmail = email
                        }
                    }
                    if snapshot.emails.isEmpty {
                        emptyMessage("No emails found. Add one to begin.")
                    }
                    Text("Used for future Git commits. Does not authenticate your push.")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.muted)
                        .padding(.top, 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 0) {
                    sectionHeading("02", title: "GITHUB SSH") {
                        screen = .keyring
                    } actionName: { "MANAGE" }
                    ForEach(snapshot.keys) { key in
                        choiceRow(title: key.title,
                                  subtitle: "\(key.fileName)  /  \(key.login == nil ? "UNVERIFIED" : "GITHUB: \(key.login!)")",
                                  selected: selectedKey == key.path,
                                  icon: "key.horizontal") {
                            selectedKey = key.path
                        }
                    }
                    if snapshot.keys.isEmpty {
                        emptyMessage("No SSH pairs found. Add a key in Keyring.")
                    }
                    Text("This key will be used by direct git@github.com remotes.")
                        .font(.system(size: 10))
                        .foregroundStyle(Design.muted)
                        .padding(.top, 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    microLabel("PENDING CONFIGURATION")
                    Text(selectedEmail.isEmpty ? "Select an email" : selectedEmail)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Design.ink)
                        .lineLimit(1)
                    Text("SSH  /  \(selectedIdentity?.title ?? "Select a key")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Design.muted)
                }
                Spacer()
                Button { testSelectedKey() } label: { Label("VERIFY KEY", systemImage: "checkmark.shield") }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(selectedIdentity == nil || isBusy)
                Button { applySelected() } label: {
                    Label(isBusy ? "WORKING…" : "APPLY CONFIGURATION", systemImage: "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedEmail.isEmpty || selectedIdentity == nil || isBusy)
            }
            .padding(18)
            .technicalPanel()

            if let identity = selectedIdentity {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        microLabel("SELECTED KEY / PUBLIC FINGERPRINT")
                        Text(identity.fingerprint)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Design.ink)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("SHOW PUBLIC KEY") { inspectKey = identity }
                        .buttonStyle(.plain)
                        .foregroundStyle(Design.orange)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
            }
            notification
        }
    }

    private var keyringScreen: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("\(snapshot.keys.count) KEY PAIRS DISCOVERED")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Design.muted)
                Spacer()
                Button { verifyAllKeys() } label: { Label("VERIFY ALL", systemImage: "checkmark.shield") }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isBusy || snapshot.keys.isEmpty)
                Button { chooseExistingKey() } label: { Label("REGISTER EXISTING", systemImage: "plus") }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isBusy)
                Button { showGenerateSheet = true } label: { Label("GENERATE NEW", systemImage: "key") }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(isBusy)
            }
            VStack(spacing: 0) {
                ForEach(snapshot.keys) { key in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: "key.horizontal")
                                .font(.system(size: 16)).foregroundStyle(Design.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Design.ink)
                                Text(key.path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Design.muted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Text(key.fingerprint)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Design.muted)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 8)
                            Text(key.login == nil ? "UNVERIFIED" : "GITHUB / \(key.login!)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(key.login == nil ? Design.muted : Design.green)
                        }
                        HStack(spacing: 19) {
                            Button("VIEW PUBLIC KEY") { inspectKey = key }
                            Button("VERIFY WITH GITHUB") { testKey(key) }
                            Button("USE FOR SWITCH") { selectedKey = key.path; screen = .switcher }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Design.orange)
                        .disabled(isBusy)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .overlay(alignment: .bottom) { Rectangle().fill(Design.stroke).frame(height: 1) }
                }
                if snapshot.keys.isEmpty { emptyMessage("No SSH key pairs found in ~/.ssh or registered paths.") }
            }
            .background(Design.surface)
            .overlay(Rectangle().stroke(Design.stroke, lineWidth: 1))
            HStack(alignment: .firstTextBaseline) {
                Text("GITHUB LINKING")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Design.muted)
                Text("Create or import the key pair, add its public key to GitHub Settings, then click Verify. Key comments never prove account ownership.")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.muted)
            }
            Button("OPEN GITHUB SSH SETTINGS  ↗") {
                if let url = URL(string: "https://github.com/settings/keys") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Design.orange)
            notification
        }
    }

    private var activityScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                microLabel("SESSION EVENTS")
                Spacer()
                Button("CLEAR") { history = [] }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Design.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(history.indices.reversed()), id: \.self) { index in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", history.count - index))
                            .foregroundStyle(Design.orange)
                        Text(history[index])
                            .foregroundStyle(Design.ink)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(14)
                    .overlay(alignment: .bottom) { Rectangle().fill(Design.stroke).frame(height: 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .technicalPanel()
            notification
        }
    }

    private func microLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(Design.muted)
    }

    private func miniStatistic(number: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Design.orange)
            microLabel(title)
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Design.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func sectionHeading(_ number: String, title: String,
                                action: @escaping () -> Void,
                                actionName: () -> String) -> some View {
        HStack(spacing: 7) {
            Text(number).foregroundStyle(Design.orange)
            Text("/ " + title).foregroundStyle(Design.ink)
            Spacer()
            Button(actionName(), action: action)
                .foregroundStyle(Design.muted)
                .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .frame(height: 34)
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool, icon: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Rectangle().fill(selected ? Design.orange : .clear).frame(width: 3)
                Image(systemName: icon).foregroundStyle(selected ? Design.orange : Design.muted).frame(width: 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Design.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 2)
                Image(systemName: selected ? "record.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Design.orange : Design.muted)
            }
            .frame(height: 67)
            .padding(.trailing, 12)
            .background(selected ? Design.surface : Design.background)
            .overlay(Rectangle().stroke(selected ? Design.orange.opacity(0.7) : Design.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private func emptyMessage(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11))
            .foregroundStyle(Design.muted)
            .frame(maxWidth: .infinity, minHeight: 80)
            .technicalPanel()
    }

    private var notification: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(isError ? Design.danger : Design.orange)
            Text(information)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isError ? Design.danger : Design.muted)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().stroke(Design.stroke, lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Text("GITSWITCH / SYSTEM UTILITY")
            Spacer()
            Text("LOCAL FILES  ·  NO PRIVATE KEY CONTENT STORED")
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(Design.muted)
        .padding(.top, 7)
    }

    private func refresh() {
        let previousEmail = selectedEmail
        let previousKey = selectedKey
        snapshot = core.discover()
        selectedEmail = snapshot.emails.contains(previousEmail) ? previousEmail : (snapshot.emails.first ?? "")
        if snapshot.keys.contains(where: { $0.path == previousKey }) { selectedKey = previousKey }
        else { selectedKey = snapshot.currentKeyPath ?? snapshot.keys.first?.path ?? "" }
    }

    private func appendMessage(_ value: String, error: Bool = false) {
        information = value
        isError = error
        history.append("\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))  /  \(value)")
    }

    private func work(_ title: String, operation: @escaping () throws -> String) {
        guard !isBusy else { return }
        isBusy = true
        information = "\(title)…"
        isError = false
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try operation() }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let detail): appendMessage(detail)
                case .failure(let error): appendMessage(error.localizedDescription, error: true)
                }
                refresh()
            }
        }
    }

    private func applySelected() {
        let email = selectedEmail
        let path = selectedKey
        work("Apply configuration") {
            let backup = try core.apply(email: email, keyPath: path)
            return "Applied \(email) with \(URL(fileURLWithPath: path).lastPathComponent). SSH backup: \(backup?.lastPathComponent ?? "new config")"
        }
    }

    private func testSelectedKey() {
        guard let key = selectedIdentity else { return }
        testKey(key)
    }

    private func testKey(_ key: SSHIdentity) {
        work("Verify \(key.fileName)") {
            let username = try core.verifyGitHubAccount(for: key.path)
            return "GitHub verified this key as @\(username)."
        }
    }

    private func verifyAllKeys() {
        let keys = snapshot.keys
        work("Verify discovered keys with GitHub") {
            var matched: [String] = []
            var failed = 0
            for key in keys {
                do {
                    let login = try core.verifyGitHubAccount(for: key.path)
                    matched.append("\(key.fileName) → @\(login)")
                } catch {
                    failed += 1
                }
            }
            let summary = matched.isEmpty ? "No GitHub identities authenticated." : matched.joined(separator: "; ")
            return summary + "  /  \(failed) unverified. Keys for other machines may legitimately be unverified."
        }
    }

    private func chooseExistingKey() {
        let panel = NSOpenPanel()
        panel.title = "Select a private SSH key (its matching .pub must exist)"
        panel.message = "The private key will not be copied or displayed."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.begin { response in
            guard response == .OK, let selected = panel.url else { return }
            work("Register existing SSH key") {
                try core.registerExistingKey(selected.path)
                return "Registered \(selected.lastPathComponent). Private-key contents were not read."
            }
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Design.background)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Design.orange.opacity(configuration.isPressed ? 0.76 : 1))
            .contentShape(Rectangle())
    }
}

private struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Design.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(configuration.isPressed ? Design.surface : Design.background)
            .overlay(Rectangle().stroke(Design.stroke, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

private struct PublicKeyWindow: View {
    let key: SSHIdentity
    let keyText: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PUBLIC KEY / \(key.title.uppercased())")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Design.ink)
            Text("Only the .pub file is shown. Never paste a private key into GitHub.")
                .font(.system(size: 11)).foregroundStyle(Design.muted)
            ScrollView {
                Text(keyText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Design.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: 135)
            .technicalPanel()
            HStack {
                Text(key.fingerprint)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Design.muted)
                Spacer()
                Button("CLOSE") { dismiss() }.buttonStyle(OutlineButtonStyle())
                Button("COPY PUBLIC KEY") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(keyText, forType: .string) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Design.background)
    }
}

private struct NewEmailWindow: View {
    let onSave: (String) -> Void
    @State private var email = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ADD COMMIT EMAIL")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text("Stored as a selectable Git identity. This does not connect a GitHub account.")
                .font(.system(size: 12)).foregroundStyle(Design.muted)
            TextField("name@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("CANCEL") { dismiss() }.buttonStyle(OutlineButtonStyle())
                Button("SAVE EMAIL") { onSave(email); dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!GitSwitchCore.isEmail(email))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Design.background)
    }
}

private struct NewKeyWindow: View {
    let onGenerate: (String, String) -> Void
    @State private var name = "id_git_"
    @State private var comment = ""
    @State private var confirmed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("GENERATE SSH KEY PAIR")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Text("Creates a new ed25519 key pair in ~/.ssh. It will not register itself with GitHub.")
                .font(.system(size: 12)).foregroundStyle(Design.muted)
            Text("KEY FILE NAME (NO SPACES)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            TextField("id_git_account", text: $name).textFieldStyle(.roundedBorder)
            Text("PUBLIC KEY COMMENT (OPTIONAL)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            TextField("name@example.com", text: $comment).textFieldStyle(.roundedBorder)
            Toggle("I understand this creates a key without a passphrase.", isOn: $confirmed)
                .font(.system(size: 11))
                .foregroundStyle(Design.muted)
            Text("For a passphrase-protected key, generate it with ssh-keygen in Terminal and use Register Existing instead.")
                .font(.system(size: 11))
                .foregroundStyle(Design.muted)
            HStack {
                Spacer()
                Button("CANCEL") { dismiss() }.buttonStyle(OutlineButtonStyle())
                Button("GENERATE KEY") { onGenerate(name, comment); dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!confirmed || name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 510)
        .background(Design.background)
    }
}
