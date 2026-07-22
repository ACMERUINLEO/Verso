# Verso development baseline

Prologue is the project codename. Verso is the product and application name.

Every product-facing feature batch must prepend an entry to `docs/product/PRODUCT_CHANGELOG.md`. The entry must distinguish user-visible behavior, connected infrastructure, unexposed capabilities, incomplete skeletons, known risks, and verification results.

## Toolchain

- Xcode 26.5 is the compatibility floor used by GitHub CI
- Xcode 26.6 is the current locally verified stable toolchain
- Swift 6 language mode with complete concurrency checking
- macOS 15.0 minimum deployment target
- Apple Silicon and Intel Macs (`arm64` and `x86_64` release architectures)

Open `Verso.xcworkspace`; the workspace is the canonical entry point because it also resolves local packages. Keep `Verso.xcodeproj` at project format `objectVersion = 77`. Xcode 27 may open the project, but do not accept an automatic project-format upgrade that makes it unreadable by stable Xcode 26.

Before committing Xcode project changes, run the compatibility guard:

```sh
bash Scripts/check_project_format.sh
```

For command-line builds with the stable Xcode installation:

```sh
xcodebuild \
  -workspace Verso.xcworkspace \
  -scheme Verso \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Working across Macs

- Use Git branches and pull requests to synchronize source code between development Macs. Do not share `xcuserdata`, DerivedData, build products, or personal signing settings.
- Both Macs should open `Verso.xcworkspace` with stable Xcode 26.5 or newer and run `bash Scripts/check_project_format.sh` after pulling project-file changes. The `Verso` and `VersoUnitTests` schemes are shared project data and must remain committed.
- Security-scoped bookmarks are local credentials and are intentionally not committed or synchronized. Each Mac must select or reopen its Workspace folder once to grant access on that device.
- Verso Phase 0 does not synchronize Workspace contents or `.verso` state between devices. Do not concurrently open the same cloud-synchronized Workspace on two Macs; SQLite, WAL files, and local-only execution state have no cross-device conflict resolution yet.

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
bash Scripts/check_project_format.sh
swift test --package-path Packages/VersoCore
```

See `docs/engineering/PHASE0.md` for module boundaries, failure scenarios, and remaining Phase 0 work.
