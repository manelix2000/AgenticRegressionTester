import Foundation

/// Manages session persistence using file-based JSON storage
final class SessionManager: @unchecked Sendable {
    static let shared = SessionManager()
    
    private let fileURL: URL
    private var sessions: [String: RunnerSession] = [:]
    private let lock = NSLock()
    
    enum SessionError: LocalizedError {
        case sessionNotFound(String)
        
        var errorDescription: String? {
            switch self {
            case .sessionNotFound(let id):
                return "Session not found: \(id)"
            }
        }
    }
    
    private init() {
        // Use ~/.agent-cli/ directory for storage
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let cliDir = homeDir.appendingPathComponent(".agent-cli")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
        
        self.fileURL = cliDir.appendingPathComponent("sessions.json")
        
        // Load existing sessions
        loadSessions()
    }
    
    // MARK: - Session Operations
    
    /// Create a new session
    func createSession(
        simulatorUDID: String,
        port: Int,
        deviceModel: String,
        iOSVersion: String,
        installedApp: String? = nil
    ) throws -> RunnerSession {
        lock.lock()
        defer { lock.unlock() }
        
        let session = RunnerSession(
            simulatorUDID: simulatorUDID,
            port: port,
            deviceModel: deviceModel,
            iOSVersion: iOSVersion,
            installedApp: installedApp
        )
        
        sessions[session.id] = session
        try saveSessions()
        
        print(ColorPrint.success("Created session \(session.id)"))
        print("   \(ColorPrint.label("Simulator:")) \(ColorPrint.value(simulatorUDID))")
        print("   \(ColorPrint.label("Port:")) \(ColorPrint.value(String(port)))")
        print("   \(ColorPrint.label("Device:")) \(ColorPrint.value("\(deviceModel) (\(iOSVersion))"))")
        
        return session
    }
    
    /// Get a session by ID
    func getSession(_ id: String) -> RunnerSession? {
        lock.lock()
        defer { lock.unlock()}
        return sessions[id]
    }
    
    /// List all sessions
    func listSessions() -> [RunnerSession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Update a session
    func updateSession(_ session: RunnerSession) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
        try saveSessions()
    }
    
    /// Update a session status by ID
    func updateSession(_ id: String, status: RunnerSession.SessionStatus) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard var session = sessions[id] else {
            throw SessionError.sessionNotFound(id)
        }
        
        session.status = status
        session.lastAccessedAt = Date()
        sessions[id] = session
        try saveSessions()
    }
    
    /// Save a new session (without printing)
    func saveSession(_ session: RunnerSession) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions[session.id] = session
        try saveSessions()
    }
    
    /// Delete a session
    func deleteSession(_ id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: id)
        try saveSessions()
        print(ColorPrint.success("Deleted session \(id)"))
    }
    
    /// Delete all sessions
    func deleteAllSessions() throws {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll()
        try saveSessions()
        print(ColorPrint.success("Deleted all sessions"))
    }
    
    /// Find next available port
    func nextAvailablePort() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let usedPorts = Set(sessions.values.map { $0.port })
        var port = 8080  // Default start port
        while usedPorts.contains(port) {
            port += 1
        }
        return port
    }
    
    /// Get sessions that haven't been accessed recently
    func getIdleSessions(olderThan minutes: Int) -> [RunnerSession] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return sessions.values.filter { $0.lastAccessedAt < cutoff }
    }
    
    // MARK: - Persistence
    
    private func loadSessions() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Send to stderr to avoid contaminating JSON output
            fputs(ColorPrint.info("No existing sessions found") + "\n", stderr)
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loadedSessions = try decoder.decode([RunnerSession].self, from: data)
            
            sessions = Dictionary(loadedSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Send to stderr to avoid contaminating JSON output
            fputs(ColorPrint.info("Loaded \(sessions.count) session(s)") + "\n", stderr)
        } catch {
            // Send to stderr to avoid contaminating JSON output
            fputs(ColorPrint.warning("Failed to load sessions: \(error.localizedDescription)") + "\n", stderr)
            fputs("   Starting with empty session list\n", stderr)
        }
    }
    
    private func saveSessions() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(Array(sessions.values))
        try data.write(to: fileURL, options: .atomic)
    }
}
