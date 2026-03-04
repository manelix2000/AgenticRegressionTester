@preconcurrency import ArgumentParser
import Foundation

/// Session management commands
struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage IOSAgentDriver sessions",
        discussion: """
            Sessions maintain persistent connections to iOS simulators.
            Each session runs an isolated IOSAgentDriver instance on a dedicated port.
            
            \(ColorPrint.header("Examples:"))
            
              \(ColorPrint.comment("# List all sessions"))
              \(ColorPrint.code("agent-cli session list"))
            
              \(ColorPrint.comment("# Create a new session"))
              \(ColorPrint.code("agent-cli session create --device \"iPhone 15\" --ios 18.6"))
            
              \(ColorPrint.comment("# Get session details"))
              \(ColorPrint.code("agent-cli session get <session-id>"))
            
              \(ColorPrint.comment("# Delete a session"))
              \(ColorPrint.code("agent-cli session delete <session-id>"))
            """,
        subcommands: [
            Create.self,
            List.self,
            Get.self,
            Delete.self,
            DeleteAll.self,
        ]
    )
    
    // MARK: - Create Session
    
    
    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new session",
            discussion: """
                Creates a new session with a dedicated simulator and IOSAgentDriver instance.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Specify device and iOS version"))
                  \(ColorPrint.code("agent-cli session create --device \"iPhone 15\" --ios 18.6"))
                
                  \(ColorPrint.comment("# Custom port"))
                  \(ColorPrint.code("agent-cli session create --device \"iPhone 15\" --ios 18.6 --port 9090"))
                
                  \(ColorPrint.comment("# With app installation"))
                  \(ColorPrint.code("agent-cli session create --device \"iPhone 15\" --ios 18.6 --app com.example.MyApp"))
                
                  \(ColorPrint.comment("# Use existing simulator"))
                  \(ColorPrint.code("agent-cli session create --simulator <udid>"))
                """
        )
        
        @Option(name: .shortAndLong, help: "Device model (e.g., 'iPhone 15')")
        var device: String
        
        @Option(name: .shortAndLong, help: "iOS version (e.g., '18.6')")
        var ios: String
        
        @Option(name: .shortAndLong, help: "Port number for IOSAgentDriver")
        var port: Int?
        
        @Option(name: .shortAndLong, help: "App bundle ID to install")
        var app: String?
        
        @Option(name: .long, help: "Use existing simulator UDID (skip creation)")
        var simulator: String?
        
        @Flag(name: .long, help: "Force reinstall IOSAgentDriver even if present")
        var forceReinstall = false
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        mutating func run() async throws {
            let sessionManager = SessionManager.shared
            
            let deviceModel = device
            let iOSVersion = ios
            
            let sessionPort = port ?? sessionManager.nextAvailablePort()
            
            if !json {
                print(ColorPrint.loading("Creating session..."))
                print("   \(ColorPrint.label("Device:")) \(ColorPrint.value(deviceModel))")
                print("   \(ColorPrint.label("iOS:")) \(ColorPrint.value(iOSVersion))")
                print("   \(ColorPrint.label("Port:")) \(ColorPrint.value(String(sessionPort)))")
                print("")
            }
            
            // Step 1: Find or create simulator
            let simulatorUDID: String
            let ownsSimulator: Bool
            
            if let existingUDID = simulator {
                if !json {
                    print(ColorPrint.info("Using existing simulator: \(existingUDID)"))
                }
                
                // Verify simulator exists
                guard let _ = try SimulatorManager.shared.getSimulator(udid: existingUDID) else {
                    throw ValidationError(ColorPrint.error("Simulator not found: \(existingUDID)"))
                }
                
                simulatorUDID = existingUDID
                ownsSimulator = false  // Session does NOT own this simulator
            } else {
                // Create new simulator
                if !json {
                    print(ColorPrint.loading("Creating new simulator..."))
                }
                
                let simulatorName = "IOSAgentDriver-\(UUID().uuidString.prefix(8))"
                let deviceType = "com.apple.CoreSimulator.SimDeviceType.\(deviceModel.replacingOccurrences(of: " ", with: "-"))"
                let runtimeId = "com.apple.CoreSimulator.SimRuntime.iOS-\(iOSVersion.replacingOccurrences(of: ".", with: "-"))"
                
                simulatorUDID = try SimulatorManager.shared.createSimulator(
                    name: simulatorName,
                    deviceType: deviceType,
                    runtime: runtimeId
                )
                ownsSimulator = true  // Session OWNS this simulator
            }
            
            // Step 2: Boot simulator (if we created it)
            if ownsSimulator {
                if !json {
                    print(ColorPrint.loading("Booting simulator..."))
                }
                try SimulatorManager.shared.bootSimulator(udid: simulatorUDID)
            }
            
            // Step 3: Create session record
            let sessionId = UUID().uuidString
            let session = RunnerSession(
                id: sessionId,
                simulatorUDID: simulatorUDID,
                port: sessionPort,
                deviceModel: deviceModel,
                iOSVersion: iOSVersion,
                status: .initializing,
                installedApp: app,
                ownsSimulator: ownsSimulator,  // Pass ownership flag
                createdAt: Date(),
                lastAccessedAt: Date()
            )
            
            try sessionManager.saveSession(session)
            if !json {
                print(ColorPrint.success("Session record created: \(sessionId)"))
                print("")
            }
            
            // Step 4: Start IOSAgentDriver
            if !json {
                print(ColorPrint.loading("Starting IOSAgentDriver..."))
                print(ColorPrint.info("This may take a few moments on first run..."))
            }
            
            do {
                try RunnerManager.shared.startRunner(
                    udid: simulatorUDID,
                    port: sessionPort,
                    forceReinstall: forceReinstall
                )
            } catch {
                // Update session status to error
                try? sessionManager.updateSession(sessionId, status: .error)
                throw error
            }
            
            // Step 5: Wait for health check
            if !json {
                print("")
                print(ColorPrint.loading("Waiting for IOSAgentDriver to be ready..."))
            }
            
            let healthURL = URL(string: "http://localhost:\(sessionPort)/health")!
            
            do {
                try await RunnerManager.shared.waitForHealth(url: healthURL, maxRetries: 10)
            } catch {
                // Update session status to error
                try? sessionManager.updateSession(sessionId, status: .error)
                throw error
            }
            
            // Step 6: Update session status to ready
            try sessionManager.updateSession(sessionId, status: .ready)
            
            // Get full session for output
            guard let session = sessionManager.getSession(sessionId) else {
                throw NSError(domain: "SessionCommands", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to retrieve created session"])
            }
            
            // Output result
            if json {
                let data = SessionData(from: session)
                JSONOutput.success(data)
            } else {
                // Success!
                print("")
                print(ColorPrint.success("✓ Session created successfully!"))
                print("")
                print("  \(ColorPrint.label("Session ID:")) \(ColorPrint.highlight(sessionId))")
                print("  \(ColorPrint.label("Simulator:")) \(simulatorUDID.colored(.dim))")
                print("  \(ColorPrint.label("Port:")) \(ColorPrint.value(String(sessionPort)))")
                print("  \(ColorPrint.label("URL:")) \(ColorPrint.code("http://localhost:\(sessionPort)"))")
                print("")
                print(ColorPrint.info("💡 Next steps:"))
                print("   \(ColorPrint.code("agent-cli session get \(sessionId)"))")
                print("   \(ColorPrint.code("curl http://localhost:\(sessionPort)/health"))")
            }
        }
    }
    
    private static let lock = NSLock()
    
    // MARK: - List Sessions
    
    
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all sessions",
            discussion: """
                Shows all active sessions with their status, ports, and devices.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# List all sessions (compact)"))
                  \(ColorPrint.code("agent-cli session list"))
                
                  \(ColorPrint.comment("# Show full details with timestamps"))
                  \(ColorPrint.code("agent-cli session list --verbose"))
                  \(ColorPrint.code("agent-cli session list -v"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli session list --json"))
                """
        )
        
        @Flag(name: .shortAndLong, help: "Show full details")
        var verbose = false
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() throws {
            let sessions = SessionManager.shared.listSessions()
            
            if json {
                let summaries = sessions.map { SessionListData.SessionSummary(from: $0) }
                let data = SessionListData(sessions: summaries, total: sessions.count)
                JSONOutput.success(data)
                return
            }
            
            if sessions.isEmpty {
                print(ColorPrint.info("No sessions found"))
                print(ColorPrint.info("Create one with '\(ColorPrint.code("agent-cli session create"))'"))
                return
            }
            
            print(ColorPrint.header("📋 Sessions (\(sessions.count)):\n"))
            
            for session in sessions {
                print("  \(ColorPrint.highlight(session.id))")
                print("    \(ColorPrint.label("Status:")) \(statusColor(session.status.rawValue))")
                print("    \(ColorPrint.label("Port:")) \(ColorPrint.value(String(session.port)))")
                print("    \(ColorPrint.label("Device:")) \(ColorPrint.value("\(session.deviceModel) (\(session.iOSVersion))"))")
                print("    \(ColorPrint.label("Simulator:")) \(session.simulatorUDID.colored(.dim))")
                if let app = session.installedApp {
                    print("    \(ColorPrint.label("App:")) \(ColorPrint.value(app))")
                }
                
                if verbose {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    
                    print("    \(ColorPrint.label("Created:")) \(formatter.string(from: session.createdAt).colored(.dim))")
                    print("    \(ColorPrint.label("Last accessed:")) \(formatter.string(from: session.lastAccessedAt).colored(.dim))")
                }
                
                print("")
            }
        }
        
        private func statusColor(_ status: String) -> String {
            switch status {
            case "ready": return status.colored(.green)
            case "running": return status.colored(.blue)
            case "initializing": return status.colored(.yellow)
            case "stopped": return status.colored(.brightBlack)
            case "error": return status.colored(.red)
            default: return status
            }
        }
    }
    
    // MARK: - Get Session
    
    
    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Get session details",
            discussion: """
                Displays detailed information about a specific session.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Get session by ID"))
                  \(ColorPrint.code("agent-cli session get abc123"))
                  \(ColorPrint.code("agent-cli session get 550e8400-e29b-41d4-a716-446655440000"))
                
                  \(ColorPrint.comment("# Get JSON output"))
                  \(ColorPrint.code("agent-cli session get abc123 --json"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .long, help: "Output as JSON")
        var json = false
        
        mutating func run() throws {
            guard let session = SessionManager.shared.getSession(sessionId) else {
                if json {
                    JSONOutput.error(code: "SESSION_NOT_FOUND", message: "Session not found: \(sessionId)")
                    throw ExitCode(1)
                }
                throw ValidationError(ColorPrint.error("Session not found: \(sessionId)"))
            }
            
            if json {
                let data = SessionData(from: session)
                JSONOutput.success(data)
                return
            }
            
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            
            print(ColorPrint.header("📱 Session: \(session.id)\n"))
            print("  \(ColorPrint.label("Status:")) \(statusColor(session.status.rawValue))")
            print("  \(ColorPrint.label("Port:")) \(ColorPrint.value(String(session.port)))")
            print("  \(ColorPrint.label("Device:")) \(ColorPrint.value("\(session.deviceModel) (\(session.iOSVersion))"))")
            print("  \(ColorPrint.label("Simulator UDID:")) \(session.simulatorUDID.colored(.dim))")
            
            if let app = session.installedApp {
                print("  \(ColorPrint.label("Installed App:")) \(ColorPrint.value(app))")
            }
            
            print("  \(ColorPrint.label("Created:")) \(formatter.string(from: session.createdAt).colored(.dim))")
            print("  \(ColorPrint.label("Last Accessed:")) \(formatter.string(from: session.lastAccessedAt).colored(.dim))")
        }
        
        private func statusColor(_ status: String) -> String {
            switch status {
            case "ready": return status.colored(.green)
            case "running": return status.colored(.blue)
            case "initializing": return status.colored(.yellow)
            case "stopped": return status.colored(.brightBlack)
            case "error": return status.colored(.red)
            default: return status
            }
        }
    }
    
    // MARK: - Delete Session
    
    
    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a session",
            discussion: """
                Deletes a session, stopping the IOSAgentDriver instance and optionally cleaning up the simulator.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Delete with confirmation prompt"))
                  \(ColorPrint.code("agent-cli session delete abc123"))
                
                  \(ColorPrint.comment("# Force delete without confirmation"))
                  \(ColorPrint.code("agent-cli session delete abc123 --force"))
                  \(ColorPrint.code("agent-cli session delete abc123 -f"))
                """
        )
        
        @Argument(help: "Session ID")
        var sessionId: String
        
        @Flag(name: .shortAndLong, help: "Delete without confirmation")
        var force = false
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        
        mutating func run() throws {
            guard let session = SessionManager.shared.getSession(sessionId) else {
                if json {
                    JSONOutput.error(code: "SESSION_NOT_FOUND", message: "Session not found: \(sessionId)")
                    throw ExitCode(1)
                }
                throw ValidationError(ColorPrint.error("Session not found: \(sessionId)"))
            }
            
            if !force && !json {
                print(ColorPrint.warning("Delete session \(sessionId)?"))
                if session.ownsSimulator {
                    print("   ⚠️  This will stop IOSAgentDriver and DELETE the simulator (\(session.simulatorUDID.prefix(8))...)")
                } else {
                    print("   This will stop IOSAgentDriver but KEEP the simulator (reused)")
                }
                print("   Type '\(ColorPrint.highlight("yes"))' to confirm: ", terminator: "")
                
                guard let response = readLine(), response.lowercased() == "yes" else {
                    print(ColorPrint.error("Cancelled"))
                    return
                }
            }
            
            if !json {
                print(ColorPrint.loading("Deleting session..."))
            }
            
            // Step 1: Stop IOSAgentDriver if running
            if session.status == .running || session.status == .ready {
                do {
                    try RunnerManager.shared.stopRunner(udid: session.simulatorUDID, port: session.port)
                } catch {
                    if !json {
                        print(ColorPrint.warning("Failed to stop IOSAgentDriver: \(error.localizedDescription)"))
                        print(ColorPrint.info("Continuing with session deletion..."))
                    }
                }
            } else {
                if !json {
                    print(ColorPrint.info("IOSAgentDriver not running, skipping stop"))
                }
            }
            
            // Step 2: Delete simulator if owned by session
            if session.ownsSimulator {
                if !json {
                    print(ColorPrint.loading("Deleting simulator \(session.simulatorUDID.prefix(8))..."))
                }
                do {
                    try SimulatorManager.shared.deleteSimulator(udid: session.simulatorUDID)
                    if !json {
                        print(ColorPrint.success("Simulator deleted"))
                    }
                } catch {
                    if !json {
                        print(ColorPrint.warning("⚠️  Failed to delete simulator: \(error.localizedDescription)"))
                        print(ColorPrint.info("   Simulator may have been already deleted - continuing..."))
                    }
                }
            } else {
                if !json {
                    print(ColorPrint.info("Keeping simulator (reused): \(session.simulatorUDID.prefix(8))..."))
                }
            }
            
            // Step 4: Delete session record (always try to clean up)
            do {
                try SessionManager.shared.deleteSession(sessionId)
                if json {
                    let result = DeleteResult(sessionId: sessionId, deleted: true)
                    JSONOutput.success(result)
                } else {
                    print(ColorPrint.success("Session deleted: \(sessionId)"))
                }
            } catch {
                if json {
                    JSONOutput.error(code: "DELETE_FAILED", message: "Failed to delete session record: \(error.localizedDescription)")
                    throw ExitCode(1)
                }
                print(ColorPrint.error("Failed to delete session record: \(error.localizedDescription)"))
                throw error  // Session record deletion is critical
            }
        }
    }
    
    // MARK: - Delete All Sessions
    
    
    struct DeleteAll: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete-all",
            abstract: "Delete all sessions",
            discussion: """
                Deletes all sessions, stopping all IOSAgentDriver instances and cleaning up resources.
                
                \(ColorPrint.header("Examples:"))
                
                  \(ColorPrint.comment("# Delete all with confirmation"))
                  \(ColorPrint.code("agent-cli session delete-all"))
                
                  \(ColorPrint.comment("# Force delete all without confirmation"))
                  \(ColorPrint.code("agent-cli session delete-all --force"))
                  \(ColorPrint.code("agent-cli session delete-all -f"))
                """
        )
        
        @Flag(name: .shortAndLong, help: "Delete without confirmation")
        var force = false
        
        @Flag(name: .long, help: "Output in JSON format")
        var json = false
        
        
        mutating func run() throws {
            let sessions = SessionManager.shared.listSessions()
            
            if sessions.isEmpty {
                if json {
                    let result = DeleteAllResult(totalSessions: 0, successCount: 0, failedCount: 0, deletedSessions: [])
                    JSONOutput.success(result)
                } else {
                    print(ColorPrint.info("No sessions to delete"))
                }
                return
            }
            
            if !force && !json {
                print(ColorPrint.warning("Delete all \(sessions.count) session(s)?"))
                print("   Type '\(ColorPrint.highlight("yes"))' to confirm: ", terminator: "")
                
                guard let response = readLine(), response.lowercased() == "yes" else {
                    print(ColorPrint.error("Cancelled"))
                    return
                }
            }
            
            if !json {
                print(ColorPrint.loading("Deleting \(sessions.count) session(s)..."))
                print("")
                
                // Count how many simulators will be deleted
                let ownedSimulators = sessions.filter { $0.ownsSimulator }
                if !ownedSimulators.isEmpty {
                    print(ColorPrint.info("Will delete \(ownedSimulators.count) simulator(s) owned by sessions"))
                }
            }
            
            // Delete each session
            var successCount = 0
            var failedCount = 0
            var deletedSessions: [String] = []
            
            for session in sessions {
                if !json {
                    print(ColorPrint.loading("Deleting session \(session.id.prefix(8))..."))
                }
                
                // Stop IOSAgentDriver if running
                if session.status == .running || session.status == .ready {
                    do {
                        try RunnerManager.shared.stopRunner(udid: session.simulatorUDID, port: session.port)
                    } catch {
                        if !json {
                            print(ColorPrint.warning("  ⚠️  Failed to stop IOSAgentDriver: \(error.localizedDescription)"))
                            print(ColorPrint.info("  Continuing with deletion..."))
                        }
                    }
                } else {
                    if !json {
                        print(ColorPrint.info("  IOSAgentDriver not running, skipping stop"))
                    }
                }
                
                // Release pool simulator if applicable
                if !session.ownsSimulator {
                    if !json {
                        print(ColorPrint.loading("  Deleting simulator \(session.simulatorUDID.prefix(8))..."))
                    }
                    do {
                        try SimulatorManager.shared.deleteSimulator(udid: session.simulatorUDID)
                        if !json {
                            print(ColorPrint.success("  Simulator deleted"))
                        }
                    } catch {
                        if !json {
                            print(ColorPrint.warning("  ⚠️  Failed to delete simulator: \(error.localizedDescription)"))
                            print(ColorPrint.info("  Simulator may have been already deleted - continuing..."))
                        }
                    }
                } else {
                    if !json {
                        print(ColorPrint.info("  Keeping simulator (reused)"))
                    }
                }
                
                // Delete session record (always attempt)
                do {
                    try SessionManager.shared.deleteSession(session.id)
                    if !json {
                        print(ColorPrint.success("  ✓ Session deleted"))
                    }
                    successCount += 1
                    deletedSessions.append(session.id)
                } catch {
                    if !json {
                        print(ColorPrint.error("  ✗ Failed to delete session record: \(error.localizedDescription)"))
                    }
                    failedCount += 1
                }
                
                if !json {
                    print("")
                }
            }
            
            // Summary
            if json {
                let result = DeleteAllResult(
                    totalSessions: sessions.count,
                    successCount: successCount,
                    failedCount: failedCount,
                    deletedSessions: deletedSessions
                )
                JSONOutput.success(result)
            } else {
                if failedCount == 0 {
                    print(ColorPrint.success("✅ Successfully deleted all \(successCount) session(s)"))
                } else {
                    print(ColorPrint.warning("⚠️  Deleted \(successCount) session(s), failed to delete \(failedCount)"))
                }
            }
        }
    }
}
