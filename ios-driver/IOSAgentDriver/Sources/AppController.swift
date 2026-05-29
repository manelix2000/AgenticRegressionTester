import Foundation
import XCTest

/// Manages XCUIApplication lifecycle and state.
/// All methods must be called from the main thread (XCTest requirement).
final class AppController {
    
    private var currentApp: XCUIApplication?
    private var currentBundleId: String?
    
    /// Singleton instance
    static let shared = AppController()
    
    private init() {}
    
    // MARK: - App Lifecycle
    
    /// Launches an application by bundle identifier
    /// - Parameters:
    ///   - bundleId: The bundle identifier of the app to launch
    ///   - arguments: Launch arguments to pass to the app
    ///   - environment: Environment variables to set
    /// - Returns: The PID of the launched app
    /// - Throws: If app cannot be launched
    func launch(bundleId: String, arguments: [String] = [], environment: [String: String] = [:]) throws -> Int {
        DriverLog.log("AppController.launch: bundleId=\(bundleId)")

        // Terminate existing app if running
        if let existing = currentApp, existing.state != .notRunning {
            DriverLog.log("AppController.launch: terminating existing app (state=\(existing.state.rawValue))")
            existing.terminate()
        }
        
        // Create and configure new app instance
        DriverLog.log("AppController.launch: creating XCUIApplication for \(bundleId)")
        let app = XCUIApplication(bundleIdentifier: bundleId)
        app.launchArguments = arguments
        app.launchEnvironment = environment
        
        // Launch the app
        DriverLog.log("AppController.launch: calling app.launch()")
        app.launch()
        
        // Wait briefly for launch to complete
        DriverLog.log("AppController.launch: waiting for runningForeground (timeout: 5s)")
        guard app.wait(for: .runningForeground, timeout: 5) else {
            DriverLog.log("AppController.launch: ❌ timeout waiting for runningForeground")
            throw AppError.launchTimeout(bundleId: bundleId)
        }
        
        currentApp = app
        currentBundleId = bundleId
        
        DriverLog.log("AppController.launch: ✅ success, bundleId=\(bundleId) state=\(app.state.rawValue)")
        return 0
    }
    
    /// Terminates the currently running application
    /// - Throws: If no app is running
    func terminate() throws {
        DriverLog.log("AppController.terminate: bundleId=\(currentBundleId ?? "nil")")
        guard let app = currentApp else {
            DriverLog.log("AppController.terminate: no app running")
            throw AppError.noAppRunning
        }
        
        app.terminate()
        currentApp = nil
        currentBundleId = nil
    }
    
    /// Gets the current application state
    /// - Returns: Information about the current app state
    /// - Throws: If no app is running
    func getState() throws -> AppStateResponse {
        guard let app = currentApp, let bundleId = currentBundleId else {
            throw AppError.noAppRunning
        }
        
        let stateString: String
        switch app.state {
        case .notRunning:
            stateString = "notRunning"
        case .runningBackgroundSuspended:
            stateString = "runningBackgroundSuspended"
        case .runningBackground:
            stateString = "runningBackground"
        case .runningForeground:
            stateString = "runningForeground"
        case .unknown:
            stateString = "unknown"
        @unknown default:
            stateString = "unknown"
        }
        
        return AppStateResponse(
            bundleId: bundleId,
            state: stateString,
            pid: 0, // XCUIApplication doesn't expose PID
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }
    
    /// Activates the application (brings to foreground)
    /// - Throws: If no app is running
    func activate() throws {
        DriverLog.log("AppController.activate")
        guard let app = currentApp else {
            DriverLog.log("AppController.activate: no app running")
            throw AppError.noAppRunning
        }
        
        app.activate()
        
        // Wait for foreground state
        let result = app.wait(for: .runningForeground, timeout: 3)
        DriverLog.log("AppController.activate: waitForForeground=\(result ? 1 : 0)")
    }
    
    // MARK: - App Access
    
    /// Executes an operation with the current app.
    /// - Parameter body: Operation that receives the current app.
    /// - Throws: AppError.noAppRunning if there is no current app, or any error from body.
    func withCurrentApp<T>(
        _ body: (XCUIApplication) throws -> T
    ) throws -> T {
        DriverLog.log("AppController.withCurrentApp")
        guard let app = currentApp else {
            DriverLog.log("AppController.withCurrentApp: no app running")
            throw AppError.noAppRunning
        }
        return try body(app)
    }
}

// MARK: - Request/Response Models

/// Request to launch an application
struct LaunchAppRequest: Codable, Sendable {
    let bundleId: String
    let arguments: [String]?
    let environment: [String: String]?
}

/// Response after launching an application
struct LaunchAppResponse: Codable, Sendable {
    let success: Bool
    let bundleId: String
    let pid: Int
    let timestamp: String
}

/// Request to terminate an application
struct TerminateAppRequest: Codable, Sendable {
    let bundleId: String?  // Optional, defaults to current app
}

/// Response after terminating an application
struct TerminateAppResponse: Codable, Sendable {
    let success: Bool
    let timestamp: String
}

/// Response containing app state information
struct AppStateResponse: Codable, Sendable {
    let bundleId: String
    let state: String  // "notRunning", "runningBackgroundSuspended", "runningBackground", "runningForeground"
    let pid: Int
    let timestamp: String
}

/// Response containing list of installed applications
struct AppListResponse: Codable, Sendable {
    let applications: [String]
    let count: Int
    let timestamp: String
}

// MARK: - Errors

enum AppError: LocalizedError, Sendable {
    case noAppRunning
    case launchTimeout(bundleId: String)
    case invalidBundleId(bundleId: String)
    case appNotFound(bundleId: String)
    
    var errorDescription: String? {
        switch self {
        case .noAppRunning:
            return "No application is currently running"
        case .launchTimeout(let bundleId):
            return "Application '\(bundleId)' failed to launch within timeout"
        case .invalidBundleId(let bundleId):
            return "Invalid bundle identifier: \(bundleId)"
        case .appNotFound(let bundleId):
            return "Application with bundle identifier '\(bundleId)' not found"
        }
    }
}
