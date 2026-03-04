import Foundation

/// Helper for JSON output mode
enum JSONOutput {
    /// Print success response with data
    static func success<T: Encodable>(_ data: T) {
        let response = SuccessResponse(success: true, data: data)
        printJSON(response)
    }
    
    /// Print error response
    static func error(code: String, message: String) {
        let error = ErrorDetail(code: code, message: message)
        let response = ErrorResponse(success: false, error: error)
        printJSON(response)
    }
    
    /// Print raw encodable value (for backward compat with existing --json flags)
    static func raw<T: Encodable>(_ value: T) {
        printJSON(value)
    }
    
    private static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(value)
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } catch {
            // Fallback to error message
            print("{\"success\":false,\"error\":{\"code\":\"JSON_ENCODING_ERROR\",\"message\":\"\(error.localizedDescription)\"}}")
        }
    }
}

// MARK: - Response Structures

struct SuccessResponse<T: Encodable>: Encodable {
    let success: Bool
    let data: T
}

struct ErrorResponse: Encodable {
    let success: Bool
    let error: ErrorDetail
}

struct ErrorDetail: Encodable {
    let code: String
    let message: String
}

// MARK: - Common Data Structures

struct SessionData: Encodable {
    let sessionId: String
    let simulatorUDID: String
    let port: Int
    let device: String
    let iOSVersion: String
    let status: String
    let installedApp: String?
    let ownsSimulator: Bool
    let createdAt: Date
    let lastAccessedAt: Date
    
    init(from session: RunnerSession) {
        self.sessionId = session.id
        self.simulatorUDID = session.simulatorUDID
        self.port = session.port
        self.device = session.deviceModel
        self.iOSVersion = session.iOSVersion
        self.status = session.status.rawValue
        self.installedApp = session.installedApp
        self.ownsSimulator = session.ownsSimulator
        self.createdAt = session.createdAt
        self.lastAccessedAt = session.lastAccessedAt
    }
}

struct SessionListData: Encodable {
    let sessions: [SessionSummary]
    let total: Int
    
    struct SessionSummary: Encodable {
        let id: String
        let simulatorUDID: String
        let port: Int
        let device: String
        let iOSVersion: String
        let status: String
        let installedApp: String?
        
        init(from session: RunnerSession) {
            self.id = session.id
            self.simulatorUDID = session.simulatorUDID
            self.port = session.port
            self.device = session.deviceModel
            self.iOSVersion = session.iOSVersion
            self.status = session.status.rawValue
            self.installedApp = session.installedApp
        }
    }
}

struct DeleteResult: Encodable {
    let sessionId: String
    let deleted: Bool
}

struct DeleteAllResult: Encodable {
    let totalSessions: Int
    let successCount: Int
    let failedCount: Int
    let deletedSessions: [String]
}

struct SimulatorListData: Encodable {
    let simulators: [SimulatorSummary]
    let total: Int
    
    struct SimulatorSummary: Encodable {
        let name: String
        let udid: String
        let state: String
        let runtime: String
        let deviceType: String
    }
}

struct OperationResult: Encodable {
    let success: Bool
    let message: String?
}
