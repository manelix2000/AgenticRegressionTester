import Foundation

/// Represents an active IOSAgentDriver session with a dedicated simulator
struct RunnerSession: Codable, Identifiable {
    let id: String
    let simulatorUDID: String
    let port: Int
    let deviceModel: String
    let iOSVersion: String
    let createdAt: Date
    var lastAccessedAt: Date
    var status: SessionStatus
    var installedApp: String?
    var ownsSimulator: Bool  // True if session created the simulator, false if reused
    
    enum SessionStatus: String, Codable {
        case initializing = "initializing"
        case ready = "ready"
        case running = "running"
        case stopped = "stopped"
        case error = "error"
    }
    
    /// Custom decoding to handle backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        simulatorUDID = try container.decode(String.self, forKey: .simulatorUDID)
        port = try container.decode(Int.self, forKey: .port)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        iOSVersion = try container.decode(String.self, forKey: .iOSVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastAccessedAt = try container.decode(Date.self, forKey: .lastAccessedAt)
        status = try container.decode(SessionStatus.self, forKey: .status)
        installedApp = try container.decodeIfPresent(String.self, forKey: .installedApp)
        // Default to true for backward compatibility (old sessions assumed ownership)
        ownsSimulator = try container.decodeIfPresent(Bool.self, forKey: .ownsSimulator) ?? true
    }
    
    /// Create a new session with a unique ID
    init(
        id: String = UUID().uuidString,
        simulatorUDID: String,
        port: Int,
        deviceModel: String,
        iOSVersion: String,
        status: SessionStatus = .initializing,
        installedApp: String? = nil,
        ownsSimulator: Bool = true,  // Default to true (session created simulator)
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) {
        self.id = id
        self.simulatorUDID = simulatorUDID
        self.port = port
        self.deviceModel = deviceModel
        self.iOSVersion = iOSVersion
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.status = status
        self.installedApp = installedApp
        self.ownsSimulator = ownsSimulator
    }
    
    mutating func updateAccess() {
        lastAccessedAt = Date()
    }
    
    mutating func updateStatus(_ newStatus: SessionStatus) {
        status = newStatus
        lastAccessedAt = Date()
    }
}
