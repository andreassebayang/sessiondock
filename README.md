# SessionDock

SessionDock is a native macOS application for organizing remote connection configurations. It is an independent open-source project and is not affiliated with Royal Apps.

## Features

- Nested folders, favorites, and search by name, host, or tag.
- Configuration editor for SSH, RDP, VNC, HTTP(S), and SFTP profiles.
- Inspector, environment labels, and configuration tabs.
- Local JSON workspaces with atomic saves and external-change detection.
- Import preview and export with optional host and username redaction.
- Native menus, keyboard shortcuts, and prompts for unsaved changes.

SSH profiles open an embedded terminal using macOS OpenSSH. HTTP(S) profiles open an embedded browser with temporary website storage. Sessions stay open when switching tabs and stop when closed or disconnected. SFTP adds a two-panel file browser, serial upload queue, cancellation, and downloads published only after completion. Existing host keys must already be verified in `known_hosts`; authentication uses the SSH agent or a saved Keychain password.

RDP and VNC adapters are experimental. RDP uses system TLS certificate trust and requires a username and Keychain password; untrusted certificates are rejected before authentication. Direct VNC transport is unencrypted and requires acknowledgment each session. Clipboard sharing is disabled.

Passwords for RDP, VNC, and SFTP can be saved from Connection Properties. Saved Passwords in the Connection menu lists Keychain metadata and deletes credentials explicitly. Replacing or detaching a password retains the old Keychain entry so another saved workspace can still use it.

## Build and run

Targets macOS 14 or later and requires Swift 6.2 or later, Apple Command Line Tools or Xcode, and libssh2 headers/libraries. On Homebrew, install `libssh2`; builds also accept `SESSIONDOCK_LIBSSH2_PREFIX` for a custom prefix. Intel and minimum-version runtime validation are pending. The current Homebrew libssh2 build requires macOS 27; the local bundle inherits that limit until portable native dependencies are built.

```sh
bash scripts/build-app.sh
open "dist/Connection Workbench.app"
```

The current executable and application bundle use the name Connection Workbench. The local build uses an ad hoc signature and is not signed or notarized for public distribution. Non-system runtime libraries and license notices are copied into the bundle.

## Tests

```sh
bash scripts/test.sh
bash scripts/test-native.sh
```

The tests cover documents, file conflicts, export redaction, session cleanup, disposable Keychain items, transfer paths, a loopback VNC framebuffer, and rejection of untrusted RDP certificates and malformed VNC messages. Build scripts use project-local compiler caches.

The Port field controls the destination port for SSH and web connections, including when a web URL contains a port.

SSH uses the local SSH authentication agent and default identity files. Host-key verification stays enabled. Custom SSH configuration, forwarding, remote-triggered clipboard access, web uploads, downloads, and popup windows are disabled. Passwords entered in the terminal are handled by OpenSSH; the application does not store them.

## Data and security

Workspace files are not encrypted. Do not store passwords, private keys, or access tokens in configuration fields or notes. Keep real workspace files outside the checkout or in the ignored `local-data/` directory.

Exports always remove credential references, notes, and tags. Hostnames and usernames can also be removed. Workspace, folder, and connection names remain; review the export before sharing.

Only the application's own JSON format is supported. Documents from other connection managers cannot currently be imported.

## License

Application code is [MIT](LICENSE). Dependency notices are in `Resources/*-LICENSE.txt`. The adapted VNC source includes its upstream license and revision in `Sources/VNCVendor`.
