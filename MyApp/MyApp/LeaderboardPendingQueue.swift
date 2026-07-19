import Foundation

enum LeaderboardPendingQueue {
    static let maximumRecordCount = 100

    static func load(
        fileURL: URL,
        legacyDefaults: UserDefaults = .standard,
        legacyKey: String
    ) -> [PendingGameRecord] {
        if let records = load(from: fileURL) {
            return records
        }

        guard let data = legacyDefaults.data(forKey: legacyKey),
              let records = decode(data) else {
            return []
        }
        save(records, to: fileURL)
        legacyDefaults.removeObject(forKey: legacyKey)
        return records
    }

    static func enqueue(_ record: PendingGameRecord, into records: [PendingGameRecord]) -> [PendingGameRecord] {
        var updated = records
        if let existingIndex = updated.firstIndex(where: { $0.deduplicationKey == record.deduplicationKey }) {
            updated[existingIndex] = record
            return updated
        }

        updated.append(record)
        if updated.count > maximumRecordCount {
            updated = Array(updated.suffix(maximumRecordCount))
        }
        return updated
    }

    static func remove(_ record: PendingGameRecord, from records: [PendingGameRecord]) -> [PendingGameRecord] {
        let deduplicationKey = record.deduplicationKey
        return records.filter {
            $0.id != record.id && $0.deduplicationKey != deduplicationKey
        }
    }

    static func load(from fileURL: URL) -> [PendingGameRecord]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return decode(data)
    }

    static func save(_ records: [PendingGameRecord], to fileURL: URL) {
        guard let data = encode(records) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            // The caller owns user-facing error logging.
        }
    }

    static func encode(_ records: [PendingGameRecord]) -> Data? {
        try? JSONEncoder().encode(records)
    }

    static func decode(_ data: Data) -> [PendingGameRecord]? {
        try? JSONDecoder().decode([PendingGameRecord].self, from: data)
    }
}
