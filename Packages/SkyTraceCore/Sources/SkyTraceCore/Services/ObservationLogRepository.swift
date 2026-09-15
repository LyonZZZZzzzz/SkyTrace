import Foundation

public enum ObservationLogError: LocalizedError {
    case applicationSupportUnavailable
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "无法访问观测日志存储目录。"
        case .encodingFailed(let message): "无法保存观测日志：\(message)"
        case .decodingFailed(let message): "无法读取观测日志：\(message)"
        }
    }
}

public actor ObservationLogRepository {
    private let fileURL: URL
    private let fileManager: FileManager
    private var entries: [ObservationLogEntry]?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base: URL
            if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                base = applicationSupport
            } else {
                base = URL(fileURLWithPath: NSHomeDirectory())
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            }
            self.fileURL = base
                .appendingPathComponent("SkyTrace", isDirectory: true)
                .appendingPathComponent("observation-log.json")
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func allEntries() throws -> [ObservationLogEntry] {
        try loadIfNeeded()
            .sorted { $0.observedAt > $1.observedAt }
    }

    public func entries(matching filter: ObservationLogFilter) throws -> [ObservationLogEntry] {
        try allEntries().filter { entry in
            if let objectID = filter.objectID, entry.objectID != objectID { return false }
            if let minimumRating = filter.minimumRating, entry.rating < minimumRating { return false }
            if let startDate = filter.startDate, entry.observedAt < startDate { return false }
            if let endDate = filter.endDate, entry.observedAt > endDate { return false }
            return true
        }
    }

    @discardableResult
    public func save(_ entry: ObservationLogEntry) throws -> ObservationLogEntry {
        var values = try loadIfNeeded()
        var normalized = entry
        normalized.rating = min(5, max(1, entry.rating))
        normalized.updatedAt = Date()
        if let index = values.firstIndex(where: { $0.id == normalized.id }) {
            values[index] = normalized
        } else {
            values.append(normalized)
        }
        try persist(values)
        entries = values
        return normalized
    }

    public func delete(id: UUID) throws {
        var values = try loadIfNeeded()
        values.removeAll { $0.id == id }
        try persist(values)
        entries = values
    }

    public func removeEntries(objectID: String) throws {
        var values = try loadIfNeeded()
        values.removeAll { $0.objectID == objectID }
        try persist(values)
        entries = values
    }

    public func removeUnknownObjects(validIDs: Set<String>) throws {
        var values = try loadIfNeeded()
        values.removeAll { !validIDs.contains($0.objectID) }
        try persist(values)
        entries = values
    }

    private func loadIfNeeded() throws -> [ObservationLogEntry] {
        if let entries { return entries }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            entries = []
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([ObservationLogEntry].self, from: data)
            entries = decoded
            return decoded
        } catch {
            try backupCorruptFile()
            entries = []
            throw ObservationLogError.decodingFailed(error.localizedDescription)
        }
    }

    private func persist(_ values: [ObservationLogEntry]) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(values)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ObservationLogError.encodingFailed(error.localizedDescription)
        }
    }

    private func backupCorruptFile() throws {
        let directory = fileURL.deletingLastPathComponent()
        let timestamp = Int(Date().timeIntervalSince1970)
        let backup = directory.appendingPathComponent("observation-log-corrupt-\(timestamp).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.moveItem(at: fileURL, to: backup)
        }
    }
}
