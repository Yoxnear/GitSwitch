# GitSwitch

**Switch Git commit identities and GitHub SSH accounts from one native macOS app.**

Working with multiple GitHub accounts can mean repeatedly editing Git email settings, SSH configuration, and remote URLs. GitSwitch provides a small, local interface to choose **which email is recorded in new commits** and **which SSH key authenticates to GitHub**—independently, without `sudo` or manually rewriting each repository's remote.

GitSwitch runs locally on your Mac. It is an independent project and is not affiliated with GitHub.

## Features

- **Independent identity selection:** choose any saved Git commit email and any detected SSH key, in any combination.
- **Automatic SSH key discovery:** find key pairs in `~/.ssh` that have corresponding `.pub` files; register keys stored elsewhere.
- **GitHub account verification:** test each key against GitHub to identify the account that accepts it. Unverified keys remain clearly marked as such.
- **Public key management:** inspect fingerprints and view or copy public keys for registration with GitHub. Private key contents are not displayed or copied.
- **Add identities:** add email choices, register an existing key pair, or generate a new Ed25519 key pair.
- **Use GitHub's standard SSH remote URLs:** select a key and use remotes such as `git@github.com:owner/repository.git` without configuring a different hostname alias for each account.
- **Safe SSH updates:** back up `~/.ssh/config`, keep unrelated host aliases, and validate the updated configuration before keeping it.
- **Native interface:** SwiftUI for macOS, with Switch, Keyring, and Activity screens.

## Requirements

- macOS **13 Ventura or later**.
- **Xcode Command Line Tools**, including the Swift compiler. Install them if needed:

  ```bash
  xcode-select --install
  ```

- A GitHub account with an SSH authentication key registered, if you want to push over SSH. GitHub account verification requires network access.

## Install

GitSwitch is currently distributed as **source code**. The install script compiles the app on your own Mac; no prebuilt `.app` download is required.

1. On this repository's GitHub page, select **Code → Download ZIP** (or clone the repository).
2. Extract the ZIP and open **Terminal** in the extracted GitSwitch project folder—the one containing `install.command`.
3. Run:

   ```bash
   bash install.command
   ```

4. If your user can write to `/Applications`, the installer places **Git Identity Switcher.app** there and opens it. If not, the project folder opens: drag the generated **Git Identity Switcher.app** into **Applications** using Finder.
5. Later, launch **GitSwitch** using **Spotlight** (`⌘ Space`) or **Launchpad**. Terminal is not required for normal use.

**Upgrading:** quit GitSwitch before installing a newer version. If the installer replaces a compatible existing installation, it saves a backup copy on the Desktop first.

### Build without installing

```bash
bash build.command
```

This builds **Git Identity Switcher.app** inside the project folder and opens it. To build without launching:

```bash
bash build.command --no-open
```

### Run the core tests

```bash
bash run-tests.command
```

## Getting started

1. Open **Keyring** and inspect the discovered SSH keys.
2. Select **Verify All** to check which keys GitHub accepts. If a key is not yet registered, choose **View Public Key**, copy it, and add it to your GitHub account under [Settings → SSH and GPG keys](https://github.com/settings/keys) as an **Authentication key**.
3. In **Switch**, select the **Git commit email** and **GitHub SSH key** you want to use. These selections are independent.
4. Click **Apply Configuration**. The selected SSH key becomes the default for `github.com`, and the selected email becomes the global Git commit email.
5. Use the normal SSH URL provided by GitHub when adding a remote:

   ```bash
   git remote add origin git@github.com:owner/repository.git
   git push -u origin main
   ```

   If a remote called `origin` already exists, use `git remote set-url origin ...` instead of `git remote add`.

**Important:** GitSwitch does not grant access to repositories. The GitHub account associated with your selected SSH key still needs permission to push to the destination repository.

## How it works

| Setting | What GitSwitch changes | What it affects |
| --- | --- | --- |
| Git commit email | `git config --global user.email` | The email recorded on new commits, unless overridden locally or by higher-priority settings |
| GitHub SSH identity | A GitSwitch-managed `Host github.com` entry in `~/.ssh/config` | Which SSH key is offered for new connections to the standard `git@github.com` hostname |
| Saved choices and verified accounts | `~/Library/Application Support/GitSwitch/profiles.json` | Available email choices, additional key paths, labels, and verified GitHub username mappings |

GitSwitch discovers public keys locally, but **a public-key filename or comment is not proof of GitHub ownership**. Verification runs an SSH authentication test; a successful GitHub response identifies the account. Key verification can fail when a key has not been registered, the network is unavailable, or a passphrase-protected key is locked.

Existing custom SSH host aliases remain in place. GitSwitch refuses to overwrite an unmanaged, conflicting `Host github.com` block rather than silently destroying custom SSH settings. It makes a timestamped SSH configuration backup before applying changes and restores the previous configuration if validation fails.

### Global versus repository-local Git settings

The selected **global** email is only a default. A repository with its own `user.email` setting will continue using that local value. To inspect the active configuration inside any repository:

```bash
git config --show-origin --get user.email
git remote -v
ssh -T git@github.com
```

The **commit author email** and the **GitHub account authorized to push** are separate concepts; they do not have to match.

## Adding SSH keys

In **Keyring**, you can register an existing key pair, inspect and copy its **public** key, or generate a new Ed25519 pair.

**Security note:** GitSwitch's built-in key generator currently creates keys **without a passphrase**. For a passphrase-protected key, generate it with `ssh-keygen` yourself, then register the existing key in GitSwitch. Never upload or publish a private SSH key. Only the `.pub` key belongs in GitHub's SSH key settings.

## Privacy and security

- GitSwitch runs locally and does not require a GitHub personal access token.
- It stores **paths and fingerprints**, not private SSH key bytes, in its preferences file.
- The **Verify** feature connects to GitHub over SSH; switching local settings itself does not require a network connection.
- It edits only user-owned Git and SSH settings, so `sudo` is not needed for normal operation.
- The locally built application is **ad-hoc signed**, not distributed as a notarized release.
- It is wise to review the scripts and source before running any locally built utility that can edit your Git and SSH configuration.

## Project structure

```text
Assets/             Icon source and macOS iconset
Sources/            SwiftUI application and configuration core
Tests/              Core tests
build.command       Compile and open the app
install.command     Compile and install into Applications
run-tests.command   Run core tests
```

## Contributing

Issues and pull requests are welcome. Please do not include private keys, authentication credentials, personal SSH configs, or local profile data in bug reports. If reporting a failure, redact local usernames and home-directory paths from terminal output.
