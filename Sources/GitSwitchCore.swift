import Foundation

// All filesystem paths in this file are local. GitSwitch never stores private-key bytes.
struct SSHIdentity: Identifiable, Hashable {
    let path: String
    let publicPath: String
    let fingerprint: String
    let comment: String
    let login: String?
    let label: String
    var id: String { path }
    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
    var title: String { login ?? (label.isEmpty ? fileName : label) }
}

struct GitSwitchSnapshot {
    var emails: [String] = []
    var keys: [SSHIdentity] = []
    var currentEmail: String = ""
    var currentKeyPath: String? = nil
    var sshConfigDescription: String = ""
}

struct SavedRegistry: Codable {
    var emails: [String] = []
    var additionalKeyPaths: [String] = []
    var verifiedGitHubAccounts: [String: String] = [:]
    var customLabels: [String: String] = [:]
}

struct ShellOutput {
    let exitCode: Int32
    let text: String
}

enum GitSwitchError: LocalizedError {
    case invalidEmail
    case missingKey(String)
    case missingPublicKey(String)
    case invalidKeyName
    case duplicateKey(String)
    case existingUnmanagedHost
    case incompleteMarker
    case invalidEffectiveConfig(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return "Enter a valid commit email."
        case .missingKey(let path): return "SSH private key not found: \(path)"
        case .missingPublicKey(let path): return "No matching .pub file exists for \(path). Only key pairs with public keys can be registered."
        case .invalidKeyName: return "Use letters, numbers, underscore or hyphen for the key name."
        case .duplicateKey(let path): return "File already exists: \(path). No key was overwritten."
        case .existingUnmanagedHost: return "An unmanaged 'Host github.com' block exists. GitSwitch will not overwrite it. Resolve it in ~/.ssh/config first."
        case .incompleteMarker: return "The existing GitSwitch managed SSH block has an incomplete or duplicate marker. Restore your SSH config backup before changing it."
        case .invalidEffectiveConfig(let text): return "SSH config validation failed. Previous SSH config restored. \(text)"
        case .failed(let message): return message
        }
    }
}

struct GitSwitchCore {
    static let markerStart = "# >>> Git Identity Switcher (managed) >>>"
    static let markerEnd = "# <<< Git Identity Switcher (managed) <<<"
    let home: URL
    let gitPath: String
    let sshPath: String
    let keygenPath: String

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         gitPath: String = "/usr/bin/git", sshPath: String = "/usr/bin/ssh",
         keygenPath: String = "/usr/bin/ssh-keygen") {
        self.home = home
        self.gitPath = gitPath
        self.sshPath = sshPath
        self.keygenPath = keygenPath
    }

    var sshDirectory: URL { home.appendingPathComponent(".ssh", isDirectory: true) }
    var configURL: URL { sshDirectory.appendingPathComponent("config") }
    var registryURL: URL { home.appendingPathComponent("Library/Application Support/GitSwitch/profiles.json") }

    func expandPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" { return home.path }
        if trimmed.hasPrefix("~/") { return home.appendingPathComponent(String(trimmed.dropFirst(2))).standardizedFileURL.path }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    @discardableResult
    func run(_ executable: String, _ arguments: [String]) throws -> ShellOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() }
        catch { throw GitSwitchError.failed("Unable to run \(URL(fileURLWithPath: executable).lastPathComponent): \(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellOutput(exitCode: process.terminationStatus,
                           text: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func loadRegistry() -> SavedRegistry {
        guard let data = try? Data(contentsOf: registryURL),
              let saved = try? JSONDecoder().decode(SavedRegistry.self, from: data) else { return SavedRegistry() }
        return saved
    }

    func saveRegistry(_ registry: SavedRegistry) throws {
        let parent = registryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        try data.write(to: registryURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: registryURL.path)
    }

    func addEmail(_ email: String) throws {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isEmail(value) else { throw GitSwitchError.invalidEmail }
        var registry = loadRegistry()
        if !registry.emails.contains(value) { registry.emails.append(value) }
        try saveRegistry(registry)
    }

    static func isEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") &&
               !value.contains(" ") && !value.contains("\n") && value.count <= 254
    }

    func registerExistingKey(_ path: String) throws {
        let normalized = expandPath(path.hasSuffix(".pub") ? String(path.dropLast(4)) : path)
        guard FileManager.default.fileExists(atPath: normalized) else { throw GitSwitchError.missingKey(normalized) }
        guard FileManager.default.fileExists(atPath: normalized + ".pub") else { throw GitSwitchError.missingPublicKey(normalized) }
        // Validate that the companion public key is readable; never open or copy the private key.
        guard let text = try? String(contentsOfFile: normalized + ".pub", encoding: .utf8),
              Self.looksLikePublicKey(text) else {
            throw GitSwitchError.failed("The selected .pub file is not a valid OpenSSH public key.")
        }
        var registry = loadRegistry()
        if !registry.additionalKeyPaths.contains(normalized) { registry.additionalKeyPaths.append(normalized) }
        try saveRegistry(registry)
    }

    func createUnencryptedKey(fileName: String, comment: String) throws -> String {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.range(of: "^[a-zA-Z0-9_-]{1,60}$", options: .regularExpression) != nil else {
            throw GitSwitchError.invalidKeyName
        }
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let path = sshDirectory.appendingPathComponent(name).path
        guard !FileManager.default.fileExists(atPath: path) && !FileManager.default.fileExists(atPath: path + ".pub") else {
            throw GitSwitchError.duplicateKey(path)
        }
        // This action is explicitly labeled "without passphrase" in the UI.
        let result = try run(keygenPath, ["-q", "-t", "ed25519", "-f", path, "-C", comment, "-N", ""])
        guard result.exitCode == 0 else { throw GitSwitchError.failed("ssh-keygen: " + result.text) }
        try registerExistingKey(path)
        return path
    }

    static func looksLikePublicKey(_ text: String) -> Bool {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return false }
        let algorithm = String(parts[0])
        return (algorithm.hasPrefix("ssh-") || algorithm.hasPrefix("ecdsa-") || algorithm.hasPrefix("sk-")) &&
            Data(base64Encoded: String(parts[1])) != nil
    }

    func readPublicKey(_ key: SSHIdentity) throws -> String {
        let text = try String(contentsOfFile: key.publicPath, encoding: .utf8)
        guard Self.looksLikePublicKey(text) else { throw GitSwitchError.failed("Invalid public key: \(key.publicPath)") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func discover() -> GitSwitchSnapshot {
        let fm = FileManager.default
        let registry = loadRegistry()
        let status = readGlobalEmail()
        let configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let managed = Self.getManagedKeyPath(configText).map(expandPath)
        var paths = registry.additionalKeyPaths
        if let contents = try? fm.contentsOfDirectory(at: sshDirectory, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) {
            paths += contents.filter { $0.lastPathComponent.hasSuffix(".pub") }
                .map { String($0.path.dropLast(4)) }
        }
        // A currently selected key might live outside ~/.ssh.
        if let current = managed { paths.append(current) }
        var keys: [SSHIdentity] = []
        for path in Array(Set(paths.map(expandPath))).sorted() {
            guard fm.fileExists(atPath: path), fm.fileExists(atPath: path + ".pub"),
                  let publicText = try? String(contentsOfFile: path + ".pub", encoding: .utf8),
                  Self.looksLikePublicKey(publicText) else { continue }
            let parts = publicText.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true)
            let comment = parts.count > 2 ? parts.dropFirst(2).joined(separator: " ") : ""
            let fp = (try? run(keygenPath, ["-lf", path + ".pub"]).text) ?? ""
            let fingerprint = fp.split(separator: " ").first(where: { $0.hasPrefix("SHA256:") }).map(String.init) ?? "Not available"
            let label = registry.customLabels[path] ?? URL(fileURLWithPath: path).lastPathComponent
            // Tie the cached GitHub login to the actual public-key fingerprint, not just the filename.
            let accountKey = path + "#" + fingerprint
            keys.append(SSHIdentity(path: path, publicPath: path + ".pub",
                                    fingerprint: fingerprint, comment: comment,
                                    login: registry.verifiedGitHubAccounts[accountKey], label: label))
        }

        var emails: [String] = registry.emails
        if Self.isEmail(status) { emails.append(status) }
        if let gitEmails = try? run(gitPath, ["config", "--global", "--includes", "--get-all", "user.email"]).text {
            for email in gitEmails.split(separator: "\n") {
                let value = String(email).trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.isEmail(value) { emails.append(value) }
            }
        }
        // SSH key comments are suggestions only; never equate a comment to a GitHub account.
        for key in keys where Self.isEmail(key.comment) { emails.append(key.comment) }
        emails = Array(Set(emails)).sorted()
        if let i = emails.firstIndex(of: status) { emails.remove(at: i); emails.insert(status, at: 0) }
        return GitSwitchSnapshot(emails: emails, keys: keys,
                                 currentEmail: status.isEmpty ? "Not configured" : status,
                                 currentKeyPath: managed,
                                 sshConfigDescription: managed == nil ? "No GitSwitch default selected" : "Managed by GitSwitch")
    }

    func readGlobalEmail() -> String {
        guard let result = try? run(gitPath, ["config", "--global", "--get", "user.email"]), result.exitCode == 0 else { return "" }
        return result.text
    }

    static func getManagedKeyPath(_ text: String) -> String? {
        guard let begin = text.range(of: markerStart),
              let end = text.range(of: markerEnd, range: begin.upperBound..<text.endIndex) else { return nil }
        let block = String(text[begin.upperBound..<end.lowerBound])
        for raw in block.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("identityfile ") {
                var value = String(line.dropFirst("IdentityFile ".count)).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                return value
            }
        }
        return nil
    }

    static func editSSHConfig(_ existing: String, selectedPath: String) throws -> String {
        guard !selectedPath.contains("\n") && !selectedPath.contains("\r") && !selectedPath.contains("\"") else {
            throw GitSwitchError.failed("The key path contains characters unsupported by the SSH config writer.")
        }
        var remaining = existing
        let startCount = remaining.components(separatedBy: markerStart).count - 1
        let endCount = remaining.components(separatedBy: markerEnd).count - 1
        guard startCount == endCount && startCount <= 1 else { throw GitSwitchError.incompleteMarker }
        if startCount == 1, let begin = remaining.range(of: markerStart),
           let end = remaining.range(of: markerEnd, range: begin.upperBound..<remaining.endIndex) {
            remaining.removeSubrange(begin.lowerBound..<end.upperBound)
        }
        // Fail closed on an explicit unmanaged github.com host; do not destroy user config.
        // Wildcards and includes are checked later with ssh -G and rolled back if conflicting.
        for raw in remaining.split(separator: "\n") {
            let beforeComment = raw.split(separator: "#", maxSplits: 1).first ?? ""
            let tokens = beforeComment.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if tokens.count > 1 && tokens[0].lowercased() == "host" &&
                tokens.dropFirst().contains(where: { $0.lowercased() == "github.com" }) {
                throw GitSwitchError.existingUnmanagedHost
            }
        }
        let managed = """
        \(markerStart)
        Host github.com
          HostName github.com
          User git
          IdentityFile "\(selectedPath)"
          IdentitiesOnly yes
        \(markerEnd)
        """
        let residual = remaining.trimmingCharacters(in: .newlines)
        return managed + "\n" + (residual.isEmpty ? "" : "\n" + residual + "\n")
    }

    private func writeConfig(_ text: String) throws {
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data(text.utf8).write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func verifyEffectiveConfiguration(_ expected: String) throws {
        let result = try run(sshPath, ["-G", "github.com"])
        guard result.exitCode == 0 else { throw GitSwitchError.invalidEffectiveConfig(result.text) }
        var identityFiles: [String] = []
        var only = false
        for raw in result.text.split(separator: "\n") {
            let words = raw.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if words.count > 1 {
                if words[0].lowercased() == "identityfile" { identityFiles.append(expandPath(String(words[1]))) }
                if words[0].lowercased() == "identitiesonly" { only = words[1].lowercased() == "yes" }
            }
        }
        guard only && identityFiles.count == 1 && identityFiles[0] == expandPath(expected) else {
            throw GitSwitchError.invalidEffectiveConfig("Effective SSH identities: \(identityFiles.joined(separator: ", ")). An Include, Match, or wildcard Host rule may conflict.")
        }
    }

    @discardableResult
    func apply(email: String, keyPath: String) throws -> URL? {
        guard Self.isEmail(email) else { throw GitSwitchError.invalidEmail }
        let path = expandPath(keyPath)
        guard FileManager.default.fileExists(atPath: path) else { throw GitSwitchError.missingKey(path) }
        guard FileManager.default.fileExists(atPath: path + ".pub") else { throw GitSwitchError.missingPublicKey(path) }
        let existingData = try? Data(contentsOf: configURL)
        if let data = existingData, String(data: data, encoding: .utf8) == nil {
            throw GitSwitchError.failed("Existing ~/.ssh/config is not UTF-8; refusing to modify it.")
        }
        let existing = existingData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let changed = try Self.editSSHConfig(existing, selectedPath: path)
        var backup: URL? = nil
        if FileManager.default.fileExists(atPath: configURL.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = sshDirectory.appendingPathComponent("config.backup-GitSwitch-\(stamp)-\(UUID().uuidString.prefix(6))")
            try FileManager.default.copyItem(at: configURL, to: target)
            backup = target
        }
        do {
            try writeConfig(changed)
            try verifyEffectiveConfiguration(path)
            let gitResult = try run(gitPath, ["config", "--global", "user.email", email])
            guard gitResult.exitCode == 0 else { throw GitSwitchError.failed("Git email update failed: " + gitResult.text) }
        } catch {
            if let data = existingData { try? writeConfig(String(decoding: data, as: UTF8.self)) }
            else { try? FileManager.default.removeItem(at: configURL) }
            throw error
        }
        // A successfully applied email becomes an explicit saved choice.
        try? addEmail(email)
        return backup
    }

    // Read GitHub's greeting ONLY when a key is accepted. Don't infer from comments or filenames.
    static func loginFromAuthentication(_ output: String) -> String? {
        guard output.contains("You've successfully authenticated"),
              let start = output.range(of: "Hi ") else { return nil }
        let tail = output[start.upperBound...]
        guard let end = tail.range(of: "! You've successfully authenticated") else { return nil }
        let name = String(tail[..<end.lowerBound])
        guard !name.isEmpty && name.count <= 39 &&
              name.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$", options: .regularExpression) != nil else { return nil }
        return name
    }

    func verifyGitHubAccount(for keyPath: String) throws -> String {
        let path = expandPath(keyPath)
        guard FileManager.default.fileExists(atPath: path) else { throw GitSwitchError.missingKey(path) }
        // -F /dev/null isolates this one key from the user's potentially overlapping SSH aliases.
        // BatchMode avoids interactive password prompts; we never modify known_hosts or accept unknown hosts.
        let result = try run(sshPath, ["-F", "/dev/null", "-T", "-o", "BatchMode=yes",
                                       "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes",
                                       "-o", "ConnectTimeout=8", "-i", path, "git@github.com"])
        guard let login = Self.loginFromAuthentication(result.text) else {
            throw GitSwitchError.failed("GitHub did not authenticate this key. \(result.text.isEmpty ? "Check GitHub SSH keys and known_hosts." : result.text)")
        }
        let fpText = (try? run(keygenPath, ["-lf", path + ".pub"]).text) ?? ""
        guard let fingerprint = fpText.split(separator: " ").first(where: { $0.hasPrefix("SHA256:") }) else {
            throw GitSwitchError.failed("GitHub authenticated, but the public-key fingerprint couldn't be read.")
        }
        var registry = loadRegistry()
        registry.verifiedGitHubAccounts[path + "#" + fingerprint] = login
        try saveRegistry(registry)
        return login
    }
}
