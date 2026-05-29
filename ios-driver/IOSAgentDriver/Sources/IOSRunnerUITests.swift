import XCTest

/// Main UITest class that hosts the HTTP server for iOS automation.
/// Uses RunLoop spinning (à la Facebook WDA) to keep the server alive.
final class IOSAgentDriverUITests: XCTestCase {
    
    private var server: HTTPServer?
    private var runnerPort: Int = 8080
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        
        // Start the HTTP server
        let port = ProcessInfo.processInfo.getRunnerPort() ?? 8080
        runnerPort = port
        DriverLog.configure(port: port)
        DriverLog.log("setUp: RUNNER_PORT=\(port), INSTALLED_APPLICATIONS=\(ProcessInfo.processInfo.environment["INSTALLED_APPLICATIONS"] ?? "<not set>")")
        
        do {
            let server = try HTTPServer(port: port)
            self.server = server
            do {
                try server.start()
                DriverLog.log("✅ HTTPServer started on port \(port)")
            } catch {
                DriverLog.log("❌ HTTPServer.start() failed: \(error.localizedDescription)")
            }
        } catch {
            DriverLog.log("❌ HTTPServer init failed on port \(port): \(error.localizedDescription)")
        }
    }
    
    override func tearDown() {
        DriverLog.log("🔴 tearDown called — test is ending")
        if let server {
            server.stop()
            self.server = nil
        }
        
        super.tearDown()
    }
    
    /// Intercepts XCTest failure recording to log what caused the test to end.
    /// This helps diagnose crashes triggered by async XCTest assertions (e.g., after swipe gestures).
    override func record(_ issue: XCTIssue) {
        DriverLog.log("🔴 XCTest FAILURE recorded — type=\(issue.type.rawValue) description=\(issue.compactDescription)")
        if let sourceLocation = issue.sourceCodeContext.location {
            DriverLog.log("🔴   at \(sourceLocation.fileURL.lastPathComponent):\(sourceLocation.lineNumber)")
        }
        super.record(issue)
    }
    
    /// Keep the test running to maintain server lifecycle.
    /// RunLoop.current.run() blocks the main thread while still processing
    /// events (DispatchQueue.main.sync from route handlers, UI updates, etc.)
    func testRunServer() {
        DriverLog.log("🚀 testRunServer: entering RunLoop on port \(runnerPort)")
        
        // Spin the main RunLoop — this keeps the test alive and allows
        // DispatchQueue.main.sync calls from route handlers to execute.
        // The test ends when XCTest cancels it (e.g., via xcodebuild timeout
        // or manual test stop).
        RunLoop.current.run()
    }
}

// MARK: - Command Line Argument Helpers

extension ProcessInfo {
    /// Extracts port number from environment variables
    /// Test plans set RUNNER_PORT as an environment variable
    func getRunnerPort() -> Int? {
        if let portString = environment["RUNNER_PORT"],
           let port = Int(portString) {
            return port
        }
        return nil
    }
    
    /// Extracts installed applications from environment variables
    /// Reads INSTALLED_APPLICATIONS as comma-separated bundle IDs
    func getInstalledApplications() -> [String] {
        if let appsString = environment["INSTALLED_APPLICATIONS"], !appsString.isEmpty {
            return appsString
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}
