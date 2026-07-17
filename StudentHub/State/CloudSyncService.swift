import CloudKit
import Foundation

enum CloudSyncAvailability {
    static var isConfigured: Bool {
        #if STUDENT_HUB_CLOUD_SYNC_YES
        true
        #else
        false
        #endif
    }
}

enum CloudSyncStatus: Equatable {
    case localOnly
    case checking
    case syncing
    case synced(Date)
    case unavailable(String)

    var title: String {
        switch self {
        case .localOnly: "Saved locally"
        case .checking: "Checking iCloud…"
        case .syncing: "Syncing…"
        case .synced: "Synced with iCloud"
        case .unavailable: "iCloud unavailable"
        }
    }

    var icon: String {
        switch self {
        case .localOnly: "externaldrive"
        case .checking, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .unavailable: "exclamationmark.icloud"
        }
    }
}

actor CloudSyncService {
    static let shared = CloudSyncService()

    private let container: CKContainer
    private let database: CKDatabase
    private let workspaceRecordID = CKRecord.ID(recordName: "primary-workspace")

    init(container: CKContainer = .default()) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func accountIsAvailable() async throws -> Bool {
        let status: CKAccountStatus = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: status) }
            }
        }
        return status == .available
    }

    func pull() async throws -> WorkspaceSnapshot? {
        guard try await accountIsAvailable() else { return nil }
        guard let record = try await fetchRecord(workspaceRecordID),
              let asset = record["snapshot"] as? CKAsset,
              let url = asset.fileURL else { return nil }

        let data = try Data(contentsOf: url)
        guard let snapshot = WorkspaceStorage.decode(data) else {
            throw CloudSyncFailure.invalidRemoteWorkspace
        }
        try await downloadLibraryFiles(for: snapshot)
        return snapshot
    }

    func push(_ snapshot: WorkspaceSnapshot) async throws {
        guard try await accountIsAvailable() else {
            throw CloudSyncFailure.accountUnavailable
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudentHub-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try WorkspaceStorage.encode(snapshot).write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let record = try await fetchRecord(workspaceRecordID)
            ?? CKRecord(recordType: "Workspace", recordID: workspaceRecordID)
        record["modifiedAt"] = snapshot.modifiedAt as NSDate
        record["snapshot"] = CKAsset(fileURL: temporaryURL)
        _ = try await save(record)

        try await uploadLibraryFiles(snapshot.files)
        try await removeStaleLibraryFiles(keeping: Set(snapshot.files.map { $0.id.uuidString }))
    }

    private func uploadLibraryFiles(_ files: [HubFileItem]) async throws {
        for item in files {
            let sourceURL = WorkspaceStorage.fileURL(for: item)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            let recordID = CKRecord.ID(recordName: item.id.uuidString)
            let record = try await fetchRecord(recordID)
                ?? CKRecord(recordType: "LibraryAsset", recordID: recordID)
            record["displayName"] = item.displayName as NSString
            record["storedFileName"] = item.storedFileName as NSString
            record["kind"] = item.kind.rawValue as NSString
            record["addedAt"] = item.addedAt as NSDate
            record["file"] = CKAsset(fileURL: sourceURL)
            _ = try await save(record)
        }
    }

    private func downloadLibraryFiles(for snapshot: WorkspaceSnapshot) async throws {
        try WorkspaceStorage.prepareDirectories()
        let records = try await fetchAllRecords(ofType: "LibraryAsset")
        let itemsByID = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.id.uuidString, $0) })
        for record in records {
            guard let item = itemsByID[record.recordID.recordName],
                  let asset = record["file"] as? CKAsset,
                  let sourceURL = asset.fileURL else { continue }
            let destination = WorkspaceStorage.fileURL(for: item)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        }
    }

    private func removeStaleLibraryFiles(keeping recordNames: Set<String>) async throws {
        let records = try await fetchAllRecords(ofType: "LibraryAsset")
        for record in records where !recordNames.contains(record.recordID.recordName) {
            try await delete(record.recordID)
        }
    }

    private func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord?, Error>) in
            database.fetch(withRecordID: id) { record, error in
                if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: record)
                }
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.save(record) { savedRecord, error in
                if let error { continuation.resume(throwing: error) }
                else if let savedRecord { continuation.resume(returning: savedRecord) }
                else { continuation.resume(throwing: CloudSyncFailure.missingSavedRecord) }
            }
        }
    }

    private func delete(_ id: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: id) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func fetchAllRecords(ofType recordType: String) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page = try await fetchRecordPage(recordType: recordType, cursor: cursor)
            allRecords.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil
        return allRecords
    }

    private func fetchRecordPage(
        recordType: String,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<([CKRecord], CKQueryOperation.Cursor?), Error>) in
            let operation = cursor.map(CKQueryOperation.init(cursor:))
                ?? CKQueryOperation(query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)))
            var records: [CKRecord] = []
            var recordError: Error?
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record): records.append(record)
                case .failure(let error): recordError = error
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let nextCursor):
                    if let recordError { continuation.resume(throwing: recordError) }
                    else { continuation.resume(returning: (records, nextCursor)) }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
}

enum CloudSyncFailure: LocalizedError {
    case accountUnavailable
    case invalidRemoteWorkspace
    case missingSavedRecord

    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "Sign in to iCloud to sync Student Hub."
        case .invalidRemoteWorkspace: "The iCloud workspace could not be read."
        case .missingSavedRecord: "iCloud did not return the saved workspace."
        }
    }
}
