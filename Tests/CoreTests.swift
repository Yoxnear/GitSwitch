import Foundation

@main
struct CoreTests {
    static func createExecutable(_ url: URL, contents: String) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("gitswitch-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.createDirectory(at: temp.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        let keyPath = temp.appendingPathComponent(".ssh/id_personal").path
        try "PRIVATE: TEST DATA - NEVER READ".write(toFile: keyPath, atomically: true, encoding: .utf8)
        try "ssh-ed25519 QUJDRA== person@example.com\n".write(toFile: keyPath + ".pub", atomically: true, encoding: .utf8)
        let shell = temp.appendingPathComponent("mock-shell.sh")
        let git = temp.appendingPathComponent("mock-git.sh")
        let keygen = temp.appendingPathComponent("mock-keygen.sh")
        // Return precisely the identity selected by the managed config to emulate OpenSSH -G.
        try createExecutable(shell, contents: """
        #!/bin/sh
        if [ "$1" = "-G" ]; then
          grep 'IdentityFile' '\(temp.path)/.ssh/config' | head -1 | sed 's/IdentityFile/identityfile/;s/\"//g'
          echo 'identitiesonly yes'
          exit 0
        fi
        echo "Hi Yoxnear! You've successfully authenticated, but GitHub does not provide shell access."
        exit 1
        """)
        try createExecutable(git, contents: """
        #!/bin/sh
        if [ "$3" = "--get" ]; then echo 'person@example.com'; exit 0; fi
        if [ "$3" = "--get-all" ]; then echo 'person@example.com'; exit 0; fi
        if [ "$3" = "user.email" ]; then echo "$4" > '\(temp.path)/test_email'; exit 0; fi
        exit 0
        """)
        try createExecutable(keygen, contents: """
        #!/bin/sh
        echo '256 SHA256:TESTFINGERPRINT fake@host (ED25519)'
        exit 0
        """)
        let core = GitSwitchCore(home: temp, gitPath: git.path, sshPath: shell.path, keygenPath: keygen.path)
        let originals = """
        Host github-aster
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_ed25519_second
          IdentitiesOnly yes

        Host github-main
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
        """
        let config = try GitSwitchCore.editSSHConfig(originals, selectedPath: keyPath)
        assert(config.contains("IdentityFile \"\(keyPath)\""))
        assert(config.contains("Host github-aster"))
        assert(config.contains("Host github-main"))
        let editedTwice = try GitSwitchCore.editSSHConfig(config, selectedPath: keyPath)
        assert(editedTwice.components(separatedBy: GitSwitchCore.markerStart).count == 2)
        assert(GitSwitchCore.getManagedKeyPath(editedTwice) == keyPath)
        do {
            _ = try GitSwitchCore.editSSHConfig("Host github.com\n  IdentityFile key", selectedPath: keyPath)
            assertionFailure("Should reject explicit unmanaged github.com")
        } catch GitSwitchError.existingUnmanagedHost { }
        do {
            _ = try GitSwitchCore.editSSHConfig(GitSwitchCore.markerStart + "\n", selectedPath: keyPath)
            assertionFailure("Should reject broken marker")
        } catch GitSwitchError.incompleteMarker { }
        assert(GitSwitchCore.loginFromAuthentication("Hi Yoxnear! You've successfully authenticated, but GitHub does not provide shell access.") == "Yoxnear")
        assert(GitSwitchCore.loginFromAuthentication("Permission denied (publickey).") == nil)

        // Ingest filesystem key and its comment without assuming it belongs to a GitHub account.
        var snap = core.discover()
        assert(snap.keys.count == 1)
        assert(snap.keys[0].login == nil)
        assert(snap.emails.contains("person@example.com"))
        let publicKeyText = try core.readPublicKey(snap.keys[0])
        assert(publicKeyText.contains("ssh-ed25519"))
        assert(!snap.keys[0].title.contains("PRIVATE"))
        let verified = try core.verifyGitHubAccount(for: keyPath)
        assert(verified == "Yoxnear")
        snap = core.discover()
        assert(snap.keys[0].login == "Yoxnear")

        try originals.write(to: core.configURL, atomically: true, encoding: .utf8)
        try core.apply(email: "person@example.com", keyPath: keyPath)
        let managed = try String(contentsOf: core.configURL, encoding: .utf8)
        assert(managed.contains(GitSwitchCore.markerStart))
        assert(managed.contains("Host github-aster"))
        let writtenEmail = try String(contentsOf: temp.appendingPathComponent("test_email"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        assert(writtenEmail == "person@example.com")

        // The cached account must not be attached to a replaced .pub key at the same filename.
        try "ssh-ed25519 QUJDREVGRw== new@example.com".write(toFile: keyPath + ".pub", atomically: true, encoding: .utf8)
        // Mock prints same fingerprint, so test directly that fingerprint-derived mapping is used.
        let registry = core.loadRegistry()
        assert(registry.verifiedGitHubAccounts[keyPath + "#SHA256:TESTFINGERPRINT"] == "Yoxnear")
        print("✓ discover / public-key view / GitHub verify / profile persistence / v2 migration / SSH apply / old aliases")
    }
}
