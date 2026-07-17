# Student Hub sync architecture

## Product rule

Student Hub is local-first. Every edit is atomically saved before sync starts, the interface never waits for the network, and turning sync off leaves a complete local workspace. CloudKit uses the signed-in user's private database; no API key or custom student-data server is required.

## Implemented in v0.1

The optional sync actor stores two private CloudKit record types:

| Record type | Contents |
| --- | --- |
| `Workspace` | The complete JSON workspace as a `CKAsset`, plus `modifiedAt` |
| `LibraryAsset` | One imported file/PDF as a `CKAsset`, keyed by its stable file UUID |

Edits are debounced for two seconds before upload. A manual **Sync now** action is also available. On activation, the newer workspace timestamp wins; downloading a workspace also restores its library assets. Missing remote files are removed after the corresponding local metadata is removed.

This snapshot model is intentionally small and dependable for a first usable version. It keeps all existing task/project/note relationships intact and makes offline use the default. Its tradeoff is that simultaneous edits on two devices are resolved at workspace level, so the most recently saved complete workspace wins.

## Activation in Xcode

The unsigned local build omits CloudKit entitlements so it can run immediately. To create a synchronized build:

1. Select the `StudentHub` target and choose your Apple Development Team.
2. Register `iCloud.com.benjamin.StudentHub`, or replace it in `StudentHub.entitlements` with a container owned by your bundle identifier.
3. Set `STUDENT_HUB_CLOUD_ENTITLEMENTS` to `StudentHub/StudentHub.entitlements` and `STUDENT_HUB_CLOUD_SYNC_ENABLED` to `YES` for the configurations you sign.
4. Build the same bundle identifier for macOS, iPhone, and iPad, then enable **Sync with iCloud** inside the app.
5. Exercise both record types in CloudKit's development environment and deploy the schema to production before distributing the app.

The first account or entitlement error is shown beside the sidebar sync control and does not stop local saving.

## Production tests still required

- First upload from an existing local workspace
- Restore on a second physical device
- Offline edits followed by reconnect
- iCloud account sign-out and sign-in
- Imported PDF upload, restore, annotation, and deletion
- Simultaneous edits on two devices, confirming the documented last-writer behavior

This machine has the iPhoneOS SDK but not Xcode's complete iOS platform component, so the shared iOS source is type-checked here; a signed simulator/device run must be completed after installing that component.

## Planned v0.2 conflict model

If multi-device collaboration grows, replace the full snapshot with per-record `Task`, `Project`, `Note`, `ScheduleBlock`, `JournalEntry`, `Meeting`, `Reminder`, and `Capture` records. Keep stable UUID relationships, incremental change tokens, recoverable note conflict copies, and deletion tombstones. That is a later reliability upgrade, not a dependency of the current local-first version.
