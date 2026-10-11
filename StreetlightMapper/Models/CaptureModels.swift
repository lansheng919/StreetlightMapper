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
    var polePotoPath: String?
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
        self.polePotoPath = polePhotoPath
        self.streetLights = []
        self.syncStatus = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
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
    let polePotoPath: String?
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
