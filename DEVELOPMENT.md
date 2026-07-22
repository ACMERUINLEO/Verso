# Verso development baseline

Prologue is the project codename. Verso is the product and application name.

Every product-facing feature batch must prepend an entry to `docs/product/PRODUCT_CHANGELOG.md`. The entry must distinguish user-visible behavior, connected infrastructure, unexposed capabilities, incomplete skeletons, known risks, and verification results.

## Toolchain

- Xcode 27.0 (`27A5228h` at baseline creation)
- Swift 6 language mode with complete concurrency checking
- macOS 15.0 minimum deployment target
- Apple Silicon and Intel Macs (`arm64` and `x86_64` release architectures)

Open `Verso.xcworkspace` with `/Applications/Xcode-beta.app` while macOS 27 requires the beta toolchain. The `.xcodeproj` remains part of the workspace, but the workspace is the canonical entry point because it also resolves local packages.

For command-line builds, either select that Xcode globally:

```sh
sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

or select it for one command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Verso.xcodeproj -scheme Verso -configuration Debug build
```

## Identity and signing

- Application bundle identifier: `com.acmeruin.verso`
- Test bundle identifiers use the same namespace.
- Do not commit a personal Apple Development Team ID. Select the appropriate team locally in Xcode when a signed archive is needed.

Changing the application bundle identifier after distributing Verso creates a different application identity. Confirm the final Apple Developer namespace before the first external release.

## Sandbox baseline

Verso is sandboxed. The initial entitlements allow:

- read/write access to files explicitly selected by the user;
- outbound network requests for model APIs and other approved services.

Persistent access to external files must use security-scoped bookmarks. Add new entitlements only when a shipped feature requires them; the embedded editor must not receive direct filesystem, database, Keychain, or unrestricted network access.

## Workspace lifecycle

- The folder selected during creation is the Workspace root. The display name does not create or rename a child folder.
- User files remain directly in that root. Verso stores its database, backups, recovery journal, and managed data under the hidden `.verso/` directory.
- **Close Workspace** ends the current session but keeps the security-scoped bookmark so the Workspace can be reopened.
- **Forget Workspace** removes the bookmark and never deletes the folder or its contents.
- **Move to Trash** moves the entire Workspace root, including files that existed before it became a Workspace, to the macOS Trash after explicit confirmation.
- Manually deleting `.verso/` deletes Verso's Workspace metadata. It does not remove the saved bookmark or the remaining user files, so the next open enters recovery instead of behaving like **Forget Workspace**.

Legacy Workspaces with root-level `workspace.sqlite`, `Backups/`, `Recovery/`, `ManagedFiles/`, and `Documents/` remain openable. New Workspaces always use the hidden layout.

Regular backups are capacity-checked before writing and retain the newest ten by default. Restore first copies the current database to a uniquely named `pre-restore-*.sqlite` protection backup, including when the current database is corrupt.

## Sync compatibility baseline

Phase 0 defines a provider-neutral `VersoSyncProtocol` but does not connect a remote service. Workspace facts use stable UUID identities, revisions, tombstones, and idempotent `OperationID` values. Local commands append Sync Outbox entries in the same SQLite transaction as their business facts.

The local `DeviceID` is reused across launches. Security-scoped bookmarks, absolute paths, API keys, OAuth tokens, device credentials, job leases, and local execution state must never be encoded into Sync Outbox payloads. See `docs/engineering/SYNC_BASELINE.md` for the executable data classification and invariants.

## Core package

The Phase 0 reliability foundation lives in `Packages/VersoCore`. Verify it independently before building the app:

```sh
bash Scripts/check_dependencies.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/VersoCore
```

See `docs/engineering/PHASE0.md` for module boundaries, failure scenarios, and remaining Phase 0 work.
