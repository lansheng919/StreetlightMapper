import Foundation

// MARK: - Confidence

/// Represents how reliably a value was extracted.
enum Confidence: String, Codable {
    case high   // ≥ threshold, auto-captured
    case low    // < threshold, required manual verification
    case manual // technician typed / edited the value
}

extension Confidence {
    var isAutoCapture: Bool { self == .high }

    var displayLabel: String {
        switch self {
        case .high:   return "High confidence"
        case .low:    return "Low confidence – verified"
        case .manual: return "Manual entry"
        }
    }
}

// MARK: - Street Light Entry

struct StreetLightEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var sessionID: UUID          // parent session
    var serialNumber: String
    var confidence: Confidence
    var photoPath: String?       // relative path inside app Documents
    var capturedAt: Date

    init(sessionID: UUID,
         serialNumber: String,
         confidence: Confidence,
         photoPath: String? = nil) {
        self.id = UUID()
        self.sessionID = sessionID
        self.serialNumber = serialNumber
        self.confidence = confidence
        self.photoPath = photoPath
        self.capturedAt = Date()
    }
}

// MARK: - Capture Session  (one Pole ↔ many StreetLights)

struct CaptureSession: Identifiable, Codable, Equatable {
    var id: UUID
    var poleID: String
    var poleConfidence: Confidence
    var polePhotoPath: String?
    var streetLights: [StreetLightEntry]
    var syncStatus: SyncStatus
    var createdAt: Date
    var updatedAt: Date
    /// Set the first time the server accepts this session. Older saved data has no value.
    var lastSyncedAt: Date?

    init(poleID: String,
         poleConfidence: Confidence,
         polePhotoPath: String? = nil) {
        self.id = UUID()
        self.poleID = poleID
        self.poleConfidence = poleConfidence
        self.polePhotoPath = polePhotoPath
        self.streetLights = []
        self.syncStatus = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Captures saved by versions before this one stored the pole photo under a misspelled key
    /// (`polePotoPath`). Read it so existing data on the phone keeps its photo.
    private struct LegacyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        static let polePotoPath = LegacyKey(stringValue: "polePotoPath")!
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        poleID = try c.decode(String.self, forKey: .poleID)
        poleConfidence = try c.decode(Confidence.self, forKey: .poleConfidence)
        streetLights = try c.decode([StreetLightEntry].self, forKey: .streetLights)
        syncStatus = try c.decode(SyncStatus.self, forKey: .syncStatus)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastSyncedAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        if let current = try c.decodeIfPresent(String.self, forKey: .polePhotoPath) {
            polePhotoPath = current
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKey.self)
            polePhotoPath = try legacy.decodeIfPresent(String.self, forKey: .polePotoPath)
        }
    }

    /// True when a street light with this serial number is already on the pole.
    /// Compared without regard to case or surrounding spaces, since a QR payload or typed
    /// value can differ in those without being a different device.
    func hasSerial(_ serial: String, excluding lightID: UUID? = nil) -> Bool {
        let wanted = Self.normalized(serial)
        return streetLights.contains { $0.id != lightID && Self.normalized($0.serialNumber) == wanted }
    }

    private static func normalized(_ serial: String) -> String {
        serial.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    mutating func addStreetLight(_ entry: StreetLightEntry) {
        streetLights.append(entry)
        updatedAt = Date()
    }

    mutating func markSynced() {
        syncStatus = .synced
        lastSyncedAt = Date()
        updatedAt = Date()
    }

    /// True while the server has no copy of this capture, so deleting it on the phone loses nothing
    /// that exists elsewhere. A capture that was uploaded and then edited is NOT deletable: the
    /// server still holds the earlier version.
    var canDelete: Bool {
        lastSyncedAt == nil && (syncStatus == .pending || syncStatus == .failed)
    }

    /// True when there is something to upload.
    var needsSync: Bool { syncStatus == .pending || syncStatus == .failed }
}

// MARK: - Sync Status

enum SyncStatus: String, Codable {
    case pending  // not yet sent
    case syncing  // in-flight
    case synced   // successfully sent
    case failed   // last attempt failed
}

extension SyncStatus {
    var displayLabel: String {
        switch self {
        case .pending:  return "Pending"
        case .syncing:  return "Syncing…"
        case .synced:   return "Synced"
        case .failed:   return "Sync failed"
        }
    }
}

// MARK: - REST DTO  (what we expose / send to SAP)

struct SessionDTO: Codable {
    let sessionId: String
    let poleId: String
    let poleConfidence: String
    /// Relative path of the pole photo. The JPEG itself is uploaded first with
    /// `PUT /api/v1/<path>` and can be fetched back with `GET /api/v1/<path>`.
    let polePhotoPath: String?
    let streetLights: [StreetLightDTO]
    let createdAt: String
    let syncStatus: String
}

struct StreetLightDTO: Codable {
    let id: String
    let serialNumber: String
    let confidence: String
    let photoPath: String?
    let capturedAt: String
}
