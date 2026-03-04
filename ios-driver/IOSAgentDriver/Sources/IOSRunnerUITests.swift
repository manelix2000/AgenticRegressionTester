import XCTest

/// Main UITest class that hosts the HTTP server for iOS automation
@MainActor
final class IOSAgentDriverUITests: XCTestCase {
    
    private var server: HTTPServer?
    
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = true
        
        // Start the HTTP server
        let port = ProcessInfo.processInfo.getRunnerPort() ?? 8080
        server = try HTTPServer(port: port)
        try await server?.start()
        
        print("✅ IOSAgentDriver started on port \(port)")
    }
    
    override func tearDown() async throws {
        // Stop the server
        await server?.stop()
        server = nil
        
        try await super.tearDown()
    }
    
    /// Keep the test running to maintain server lifecycle
    func testRunServer() throws {
        // This test runs indefinitely to keep the server alive
        print("🚀 Server is running. Send requests to http://localhost:\(server?.port ?? 8080)")
        
        // Keep the test alive using XCTWaiter (synchronous)
        let expectation = XCTestExpectation(description: "Server running")
        expectation.isInverted = true // Never fulfill this expectation
        
        // Wait for an extremely long time (effectively infinite)
        let result = XCTWaiter.wait(for: [expectation], timeout: TimeInterval.infinity)
        
        // This will never complete due to inverted expectation
        XCTAssertEqual(result, .timedOut)
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
