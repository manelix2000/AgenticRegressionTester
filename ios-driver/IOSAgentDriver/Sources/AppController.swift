import Foundation
import XCTest

/// Manages XCUIApplication lifecycle and state
@MainActor
final class AppController: Sendable {
    
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
        // Terminate existing app if running
        if let existing = currentApp, existing.state != .notRunning {
            existing.terminate()
        }
        
        // Create and configure new app instance
        let app = XCUIApplication(bundleIdentifier: bundleId)
        app.launchArguments = arguments
        app.launchEnvironment = environment
        
        // Launch the app
        app.launch()
        
        // Wait briefly for launch to complete
        guard app.wait(for: .runningForeground, timeout: 5) else {
            throw AppError.launchTimeout(bundleId: bundleId)
        }
        
        currentApp = app
        currentBundleId = bundleId
        
        // Note: XCUIApplication doesn't expose PID directly, return 0 as placeholder
        return 0
    }
    
    /// Terminates the currently running application
    /// - Throws: If no app is running
    func terminate() throws {
        guard let app = currentApp else {
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
        guard let app = currentApp else {
            throw AppError.noAppRunning
        }
        
        app.activate()
        
        // Wait for foreground state
        _ = app.wait(for: .runningForeground, timeout: 3)
    }
    
    // MARK: - App Access
    
    /// Gets the current XCUIApplication instance
    /// - Returns: The current app instance
    /// - Throws: If no app is running
    func getCurrentApp() throws -> XCUIApplication {
        guard let app = currentApp else {
            throw AppError.noAppRunning
        }
        return app
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
