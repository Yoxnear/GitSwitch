# GitSwitch 3.0 · Git identity control for macOS

A real macOS SwiftUI application, not a mockup. Built using GitSwitch 2.0's configuration contract. macOS 13 or newer; requires Xcode Command Line Tools (`xcode-select --install`).

## Install / update from v2

1. Quit the previous GitSwitch application.
2. Unzip `GitSwitch-3.0-macOS.zip` in Downloads.
3. In Terminal:

```bash
cd ~/Downloads/GitSwitch-3.0
bash install.command
```

The script compiles the app locally, backs up the previously installed GitSwitch `.app` to the Desktop (when present), and installs it into `/Applications/Git Identity Switcher.app`. If macOS does not allow writing to `/Applications`, the script opens the folder so you can drag the generated app to **Applications**, then choose **Replace**.

Afterward, launch it by **Command-Space → GitSwitch** or from **Launchpad**. You do not need Terminal to use GitSwitch once it is installed.

To compile but **not** install: `bash build.command`. To run core tests: `bash run-tests.command`.

## Design

An industrial, editorial interface: black matte surfaces, thin ruled separators, oversized header typography, monospaced metadata and subdued orange selection markers. No gradient backgrounds, glowing borders or floating card decoration. A matching black icon has a custom white cat/branch symbol and orange blueprint corner markers. The source SVG and a complete macOS `.iconset` are included.

The window uses a **standard macOS title bar** and a scrolling content pane. This prevents the header from appearing under the traffic-light controls, which happened in v2.

## Identity discovery (no hardcoded accounts)

**Email list:** Reads the global Git email, additional saved email choices, and valid email comments from `.pub` files. Comments are merely suggestions. Enter any new email using **ADD**.

**SSH key list:** Discovers pairs matching `~/.ssh/*.pub` and registers arbitrary existing key paths. Does not read, copy or upload private key contents. With a selected key, **VIEW PUBLIC KEY** displays the exact public `.pub` text and lets you copy it.

**GitHub usernames:** The Keyring's **VERIFY WITH GITHUB** or **VERIFY ALL** runs a non-interactive per-key SSH test, bypassing SSH host aliases. A verified GitHub response identifies the username; unrecognized keys stay unverified. A filename or comment never counts as verified authentication. The result is cached against the key path and fingerprint in `~/Library/Application Support/GitSwitch/profiles.json`. Verification requires network access, a trusted GitHub host key in `known_hosts`, and an unlocked key when passphrase protected.

**Register more:** KEYRING → REGISTER EXISTING selects an existing private key with a matching `.pub` file, without reading the private contents. KEYRING → GENERATE NEW creates an ed25519 pair under `~/.ssh/` after explicit acknowledgement that the generated key has **no passphrase**. For stronger protection, make a passphrase-protected pair with `ssh-keygen` and register it afterward. Upload only the PUBLIC key to GitHub: https://github.com/settings/keys

## Apply behavior

You can independently choose **commit email** and **GitHub SSH key**. Clicking **APPLY CONFIGURATION**:

- Changes `git config --global user.email` (commits in repos with an explicit local email can override it).
- Updates a dedicated **GitSwitch-managed** `Host github.com` block at the top of `~/.ssh/config`, allowing unmodified remote URLs such as `git@github.com:Yoxnear/Strike_Video.git`.
- Does **not** touch `github-main`, `github-aster`, or other custom host aliases; no private keys are modified.
- Backs up the previous `~/.ssh/config` on every SSH change to `~/.ssh/config.backup-GitSwitch-*`.
- Checks the effective `ssh -G github.com` configuration for exactly one identity and `IdentitiesOnly yes`. If the check fails, it restores the previous SSH config.
- Refuses to modify SSH configs with an additional unmanaged `Host github.com` entry, or broken managed markers.

The v2 marker block (`# >>> Git Identity Switcher (managed) >>>`) is deliberately retained, allowing v3 to replace v2's managed block without destroying other SSH aliases.

**Global caveat:** `github.com` affects new SSH connections across all normal repositories using that hostname. Other explicit host aliases continue using their own keys. GitHub repository access still depends on the selected account's permissions. This app is local, is not sandboxed, and needs no sudo to edit files already owned by your user.

## What is saved

`~/Library/Application Support/GitSwitch/profiles.json` contains email choices, extra key *paths*, previously verified GitHub usernames keyed by public-key fingerprints, and optional labels. It contains no SSH private keys or secrets. The application's in-memory Activity tab is not a persistent credential log.

## Build verification

The Foundation core is typechecked and its tests are executed in a Linux Swift environment with simulated Git/SSH processes. The SwiftUI source has been parsed successfully; only your Mac can compile and visually run the native AppKit/SwiftUI bundle. The project is shipped as source, not as a precompiled Mac binary.
