# SessionDock

SessionDock is a native macOS application for organizing remote connection configurations. It is an independent open-source project and is not affiliated with Royal Apps.

## Features

- Nested folders, favorites, and search by name, host, or tag.
- Configuration editor for SSH, RDP, VNC, HTTP(S), and SFTP profiles.
- Inspector, environment labels, and configuration tabs.
- Local JSON workspaces with atomic saves and external-change detection.
- Import preview and export with optional host and username redaction.
- Native menus, keyboard shortcuts, and prompts for unsaved changes.

Remote connections are not available in this version. The Connect button is disabled; tabs display configuration details only.

## Build and run

Requires macOS 14 or later, Swift 6 or later, and Apple Command Line Tools or Xcode.

```sh
bash scripts/build-app.sh
open "dist/Connection Workbench.app"
```

The current executable and application bundle use the name Connection Workbench. The local build is not signed or notarized for public distribution.

## Tests

```sh
bash scripts/test.sh
```

The tests cover document validation, file conflicts, collection changes, export redaction, and workspace state. Build scripts use project-local compiler caches.

## Data and security

Workspace files are not encrypted. Do not store passwords, private keys, or access tokens in configuration fields or notes. Keep real workspace files outside the checkout or in the ignored `local-data/` directory.

Exports always remove credential references, notes, and tags. Hostnames and usernames can also be removed. Workspace, folder, and connection names remain; review the export before sharing.

Only the application's own JSON format is supported. Documents from other connection managers cannot currently be imported.

## License

[MIT](LICENSE).
