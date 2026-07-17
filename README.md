# Student Hub

Student Hub is a lightweight, local-first SwiftUI study workspace for macOS, iPadOS, and iOS. v0.1 has full desktop workspaces and compact phone/tablet views built from the same data model.

## Included in v0.1

- Colored day timeline plus a drag-to-select calendar and task drop scheduling
- Task inbox, full task editor, due dates, Space filters, project links, note links, and subtasks
- User-defined Spaces that can be created, renamed, recolored, or deleted with linked content safely reassigned
- Projects with deadlines, progress, task lists, and meeting records
- Markdown notes with folders, multiple open tabs, preview, task linking, and Finder access
- Journal entries and local reminders
- File import, in-app PDF preview, annotation notes, and PDF free-text annotations
- Meeting transcripts, editable summaries, and `TODO:` / `- [ ]` action extraction
- Pomodoro timer linked to a task
- CSV and Markdown task/project export
- Universal scratchpad captures that can be converted into tasks or notes
- Detailed Command Hub plus a global macOS Quick Command panel (`Option-Space`)
- System, Light, and Dark appearance modes
- Atomic JSON persistence; Markdown, imported files, and exports are ordinary user-accessible files
- Optional private-iCloud sync for the workspace and imported library files

## Build

Open `StudentHub.xcodeproj` in Xcode 26 and run the `StudentHub` scheme. The macOS build can also be verified with:

```sh
xcodebuild -project StudentHub.xcodeproj \
  -scheme StudentHub \
  -configuration Debug \
  -destination 'platform=macOS' build
```

Run the core tests with:

```sh
xcodebuild -project StudentHub.xcodeproj \
  -scheme StudentHub \
  -configuration Debug \
  -destination 'platform=macOS' test
```

This Mac currently has the iOS SDK but not the complete iOS platform component, so the iPhone/iPad destination cannot be built here until it is installed from Xcode Settings → Components.

## Data locations

- Workspace database: `~/Library/Application Support/StudentHub/workspace.json`
- Markdown and user files: `~/Documents/Student Hub Library/`
- Exports: `~/Documents/Student Hub Library/Exports/`

The first launch includes sample school data so every workflow can be tried immediately.

## Optional multi-device sync

Local mode is the default, so the packaged Mac app works without an Apple Developer account. The app also includes an opt-in CloudKit implementation using the user's private database. To activate it, select an Apple Development Team, register the iCloud container, set `STUDENT_HUB_CLOUD_ENTITLEMENTS` to `StudentHub/StudentHub.entitlements`, and set `STUDENT_HUB_CLOUD_SYNC_ENABLED` to `YES`. After installing the signed build on each device, turn on **Sync with iCloud** from the colored sidebar menu.

The implemented v0.1 model, limitations, and production checklist are in [Docs/SyncArchitecture.md](Docs/SyncArchitecture.md).
