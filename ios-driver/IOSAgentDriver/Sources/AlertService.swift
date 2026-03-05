import XCTest
import Foundation

/// Service for detecting and interacting with system alerts and dialogs (synchronous)
final class AlertService {
    
    /// Detects all active alerts (springboard alerts, in-app alerts)
    /// - Parameter app: The application instance
    /// - Returns: List of detected alerts with their properties
    @MainActor
    static func detectAlerts(in app: XCUIApplication) -> [AlertInfo] {
        var alerts: [AlertInfo] = []
        
        // Check for springboard alerts (system-level)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let springboardAlerts = springboard.alerts.safeAllElementsBoundByIndex()
        
        for alert in springboardAlerts {
            if alert.exists {
                alerts.append(extractAlertInfo(from: alert, isSystem: true))
            }
        }
        
        // Check for in-app alerts
        let appAlerts = app.alerts.safeAllElementsBoundByIndex()
        
        for alert in appAlerts {
            if alert.exists {
                alerts.append(extractAlertInfo(from: alert, isSystem: false))
            }
        }
        
        // Check for sheets (action sheets)
        let sheets = app.sheets.safeAllElementsBoundByIndex()
        
        for sheet in sheets {
            if sheet.exists {
                alerts.append(extractSheetInfo(from: sheet))
            }
        }
        
        return alerts
    }
    
    /// Dismisses an alert by tapping a button with the specified label
    /// - Parameters:
    ///   - app: The application instance
    ///   - buttonLabel: The label of the button to tap
    ///   - timeout: Maximum time to wait for alert (default: 5 seconds)
    /// - Returns: Success status and dismissed alert info
    /// - Throws: AlertError if alert or button not found
    @MainActor
    static func dismissAlert(
        in app: XCUIApplication,
        buttonLabel: String,
        timeout: TimeInterval = 5
    ) throws -> DismissedAlertInfo {
        // Check springboard alerts first (system alerts have priority)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        // Try to find and dismiss springboard alert
        if let springboardAlert = springboard.alerts.firstMatch.waitForExistence(timeout: 0.5) ? springboard.alerts.firstMatch : nil {
            if springboardAlert.exists {
                let button = springboardAlert.buttons[buttonLabel]
                if button.waitForExistence(timeout: timeout) {
                    let alertInfo = extractAlertInfo(from: springboardAlert, isSystem: true)
                    button.tap()
                    
                    // Wait for alert to disappear (synchronously)
                    try waitForAlertDismissal(springboardAlert, timeout: 2)
                    
                    return DismissedAlertInfo(
                        success: true,
                        alertType: "system",
                        title: alertInfo.title,
                        message: alertInfo.message,
                        buttonTapped: buttonLabel
                    )
                }
            }
        }
        
        // Try to find and dismiss in-app alert
        if let appAlert = app.alerts.firstMatch.waitForExistence(timeout: 0.5) ? app.alerts.firstMatch : nil {
            if appAlert.exists {
                let button = appAlert.buttons[buttonLabel]
                if button.waitForExistence(timeout: timeout) {
                    let alertInfo = extractAlertInfo(from: appAlert, isSystem: false)
                    button.tap()
                    
                    try waitForAlertDismissal(appAlert, timeout: 2)
                    
                    return DismissedAlertInfo(
                        success: true,
                        alertType: "alert",
                        title: alertInfo.title,
                        message: alertInfo.message,
                        buttonTapped: buttonLabel
                    )
                }
            }
        }
        
        // Try to find and dismiss sheet
        if let sheet = app.sheets.firstMatch.waitForExistence(timeout: 0.5) ? app.sheets.firstMatch : nil {
            if sheet.exists {
                let button = sheet.buttons[buttonLabel]
                if button.waitForExistence(timeout: timeout) {
                    let sheetInfo = extractSheetInfo(from: sheet)
                    button.tap()
                    
                    try waitForAlertDismissal(sheet, timeout: 2)
                    
                    return DismissedAlertInfo(
                        success: true,
                        alertType: "sheet",
                        title: sheetInfo.title,
                        message: sheetInfo.message,
                        buttonTapped: buttonLabel
                    )
                }
                
                throw AlertError.buttonNotFound(buttonLabel: buttonLabel)
            }
        }
        
        throw AlertError.alertNotFound
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private static func extractAlertInfo(from alert: XCUIElement, isSystem: Bool) -> AlertInfo {
        // Get title from static text or label
        let title = alert.staticTexts.firstMatch.label.isEmpty 
            ? alert.label 
            : alert.staticTexts.firstMatch.label
        
        // Get message (usually second static text)
        var message: String?
        let staticTexts = alert.staticTexts.safeAllElementsBoundByIndex()
        if staticTexts.count > 1 {
            message = staticTexts[1].label
        } else if staticTexts.count == 1, staticTexts[0].label != title {
            message = staticTexts[0].label
        }
        
        // Get all button labels
        let buttons = alert.buttons.safeAllElementsBoundByIndex().map { $0.label }
        
        return AlertInfo(
            type: isSystem ? "system" : "alert",
            title: title,
            message: message,
            buttons: buttons,
            identifier: alert.identifier,
            frame: alert.frame
        )
    }
    
    @MainActor
    private static func extractSheetInfo(from sheet: XCUIElement) -> AlertInfo {
        // Get title
        let title = sheet.staticTexts.firstMatch.label.isEmpty 
            ? sheet.label 
            : sheet.staticTexts.firstMatch.label
        
        // Get message if exists
        var message: String?
        let staticTexts = sheet.staticTexts.safeAllElementsBoundByIndex()
        if staticTexts.count > 1 {
            message = staticTexts[1].label
        }
        
        // Get all button labels
        let buttons = sheet.buttons.safeAllElementsBoundByIndex().map { $0.label }
        
        return AlertInfo(
            type: "sheet",
            title: title,
            message: message,
            buttons: buttons,
            identifier: sheet.identifier,
            frame: sheet.frame
        )
    }
    
    @MainActor
    private static func waitForAlertDismissal(_ element: XCUIElement, timeout: TimeInterval) throws {
        let startTime = Date()
        while element.exists {
            if Date().timeIntervalSince(startTime) > timeout {
                throw AlertError.dismissalTimeout
            }
            Thread.sleep(forTimeInterval: 0.1)  // Use Thread.sleep instead of Task.sleep
        }
    }
}

// MARK: - Data Models

struct AlertInfo: Codable, Sendable {
    let type: String           // "system", "alert", or "sheet"
    let title: String          // Alert title
    let message: String?       // Alert message (optional)
    let buttons: [String]      // Available button labels
    let identifier: String     // Accessibility identifier
    let frame: CGRect          // Alert frame
}

struct AlertsResponse: Codable, Sendable {
    let alerts: [AlertInfo]    // List of active alerts
    let count: Int             // Number of alerts
    let timestamp: String      // ISO 8601 timestamp
}

struct DismissAlertRequest: Codable, Sendable {
    let buttonLabel: String    // Button label to tap
    let timeout: TimeInterval? // Optional timeout (default: 5)
}

struct DismissedAlertInfo: Codable, Sendable {
    let success: Bool          // Whether dismissal succeeded
    let alertType: String      // Type of alert dismissed
    let title: String          // Alert title
    let message: String?       // Alert message
    let buttonTapped: String   // Button that was tapped
}

struct DismissAlertResponse: Codable, Sendable {
    let dismissed: DismissedAlertInfo
    let timestamp: String      // ISO 8601 timestamp
}

// MARK: - Errors

enum AlertError: LocalizedError {
    case alertNotFound
    case buttonNotFound(buttonLabel: String)
    case dismissalTimeout
    case multipleAlertsFound
    
    var errorDescription: String? {
        switch self {
        case .alertNotFound:
            return "No alert found"
        case .buttonNotFound(let label):
            return "Button '\(label)' not found in alert"
        case .dismissalTimeout:
            return "Alert did not dismiss within timeout"
        case .multipleAlertsFound:
            return "Multiple alerts found, specify which one to dismiss"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .alertNotFound:
            return "Ensure an alert is currently displayed before attempting to dismiss"
        case .buttonNotFound:
            return "Check the available button labels using GET /ui/alerts. Button label must match exactly (case-sensitive). Common labels: 'Allow', 'Don't Allow', 'OK', 'Cancel'"
        case .dismissalTimeout:
            return "The alert may not have responded to the tap. Try increasing the timeout or check if the button is tappable"
        case .multipleAlertsFound:
            return "Dismiss alerts one at a time, starting with system alerts"
        }
    }
}
