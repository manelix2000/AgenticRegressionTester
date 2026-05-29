import XCTest
import Foundation

/// Service for explicit wait operations using safe query polling.
/// This avoids XCTest lookup/wait paths that can emit hard test failures
/// when queries have zero matches.
final class WaitService {
    private static let pollingInterval: TimeInterval = 0.1
    
    /// Result of a wait operation
    struct WaitResult: Codable {
        let success: Bool
        let element: UINode?
        let error: String?
        let condition: String
        let timeout: TimeInterval
        let actualTime: TimeInterval
        
        /// Convenience accessor for throwing contexts
        func get() throws -> UINode {
            guard success, let element = element else {
                throw WaitError.conditionNotMet(condition: condition, timeout: timeout)
            }
            return element
        }
    }
    
    /// Wait condition types
    enum WaitCondition: String, Codable {
        case exists           // Element exists in UI tree
        case notExists        // Element does not exist in UI tree
        case isEnabled        // Element is enabled (interactable)
        case isDisabled       // Element is disabled (not interactable)
        case isHittable       // Element is visible and tappable
        case isNotHittable    // Element is not hittable
        case hasFocus         // Element has keyboard focus
        case isSelected       // Element is selected
        case isNotSelected    // Element is not selected
        case labelContains    // Element label contains text
        case labelEquals      // Element label equals text
        case valueContains    // Element value contains text
        case valueEquals      // Element value equals text
    }
    
    /// Error types for wait operations
    enum WaitError: LocalizedError {
        case conditionNotMet(condition: String, timeout: TimeInterval)
        case elementNotFound(identifier: String?)
        case invalidCondition(condition: String, reason: String)
        case multipleIdentifiers
        
        var errorDescription: String? {
            switch self {
            case .conditionNotMet(let condition, let timeout):
                return "Wait condition '\(condition)' was not met within \(timeout) seconds"
            case .elementNotFound(let identifier):
                if let id = identifier {
                    return "Element '\(id)' not found"
                } else {
                    return "Element not found"
                }
            case .invalidCondition(let condition, let reason):
                return "Invalid wait condition '\(condition)': \(reason)"
            case .multipleIdentifiers:
                return "Only one identifier method allowed (identifier, label, or predicate)"
            }
        }
    }
    
    /// Wait for a specific condition using safe polling
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - condition: The wait condition to check
    ///   - identifier: Element accessibility identifier (optional)
    ///   - label: Element accessibility label (optional)
    ///   - predicate: NSPredicate query string (optional)
    ///   - value: Expected value for text/value conditions (optional)
    ///   - timeout: Maximum time to wait in seconds
    ///   - softValidation: If true, returns result instead of throwing (default: false)
    /// - Returns: WaitResult containing success status and element
    /// - Throws: WaitError if condition not met and softValidation is false
    static func wait(
        in app: XCUIApplication,
        condition: WaitCondition,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        value: String? = nil,
        timeout: TimeInterval,
        softValidation: Bool = false
    ) throws -> WaitResult {
        
        let startTime = Date()
        DriverLog.log("WaitService.wait: condition=\(condition.rawValue) timeout=\(timeout)s identifier=\(identifier ?? "-") label=\(label ?? "-") predicate=\(predicate ?? "-")")
        
        do {
            // Validate identifier usage
            let identifierCount = [identifier, label, predicate].compactMap { $0 }.count
            guard identifierCount <= 1 else {
                throw WaitError.multipleIdentifiers
            }
            
            // Build query once and evaluate condition through safe polling.
            let query = try buildQuery(
                in: app,
                identifier: identifier,
                label: label,
                predicate: predicate
            )
            
            let element = try waitForCondition(
                query: query,
                condition: condition,
                value: value,
                timeout: timeout
            )
            
            // Success!
            let actualTime = Date().timeIntervalSince(startTime)
            DriverLog.log("WaitService.wait: success in %.2fs")
            let node = element.map(serialize)
            
            return WaitResult(
                success: true,
                element: node,
                error: nil,
                condition: condition.rawValue,
                timeout: timeout,
                actualTime: actualTime
            )
            
        } catch let error as WaitError {
            let actualTime = Date().timeIntervalSince(startTime)
            DriverLog.log("WaitService.wait: failed after %.2fs: \(actualTime)")
            
            if softValidation {
                // Soft validation: Log warning but don't throw
                DriverLog.log("⚠️ Wait failed (soft validation): \(error.localizedDescription)")
                
                return WaitResult(
                    success: false,
                    element: nil,
                    error: error.localizedDescription,
                    condition: condition.rawValue,
                    timeout: timeout,
                    actualTime: actualTime
                )
            } else {
                // Hard validation: Throw error
                throw error
            }
        }
    }
    
    /// Wait for condition by polling safe query enumeration.
    private static func waitForCondition(
        query: XCUIElementQuery,
        condition: WaitCondition,
        value: String?,
        timeout: TimeInterval
    ) throws -> XCUIElement? {
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        
        while true {
            let elements = query.safeAllElementsBoundByIndex()
            let firstElement = elements.first
            
            if try conditionMet(
                condition: condition,
                element: firstElement,
                value: value
            ) {
                return firstElement
            }
            
            if Date() >= deadline {
                throw WaitError.conditionNotMet(
                    condition: condition.rawValue,
                    timeout: timeout
                )
            }
            
            let sleepTime = min(Self.pollingInterval, deadline.timeIntervalSinceNow)
            if sleepTime > 0 {
                sleepForPolling(sleepTime)
            }
        }
    }
    
    private static func sleepForPolling(_ seconds: TimeInterval) {
        let clampedSeconds = max(0, seconds)
        guard clampedSeconds > 0 else { return }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: clampedSeconds))
    }
    
    /// Build element query by identifier, label, or predicate.
    private static func buildQuery(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil
    ) throws -> XCUIElementQuery {
        
        if let identifier = identifier {
            // Find by accessibility identifier
            return app.descendants(matching: .any).safeMatching(identifier: identifier)
        }
        
        if let label = label {
            // Find by accessibility label
            let nsPredicate = NSPredicate(format: "label == %@", label)
            return app.descendants(matching: .any).safeMatching(predicate: nsPredicate)
        }
        
        if let predicateString = predicate {
            // Find by custom predicate
            let nsPredicate = NSPredicate(format: predicateString)
            var caughtException: NSException?
            guard let query = app.descendants(matching: .any)
                .safeMatching(nsPredicate, exception: &caughtException) else {
                let reason = caughtException?.reason ?? predicateString
                throw WaitError.invalidCondition(condition: "predicate", reason: reason)
            }
            return query
        }
        
        throw WaitError.invalidCondition(condition: "find", reason: "No identifier, label, or predicate provided")
    }
    
    /// Evaluates whether the current element snapshot satisfies the wait condition.
    private static func conditionMet(
        condition: WaitCondition,
        element: XCUIElement?,
        value: String?
    ) throws -> Bool {
        switch condition {
        case .exists:
            return element != nil
        case .notExists:
            return element == nil
        case .isEnabled:
            guard let element = element else { return false }
            return element.isEnabled
        case .isDisabled:
            guard let element = element else { return false }
            return !element.isEnabled
        case .isHittable:
            guard let element = element else { return false }
            return element.safeIsHittable()
        case .isNotHittable:
            guard let element = element else { return false }
            return !element.safeIsHittable()
        case .hasFocus:
            guard let element = element else { return false }
            return element.hasFocus
        case .isSelected:
            guard let element = element else { return false }
            return element.isSelected
        case .isNotSelected:
            guard let element = element else { return false }
            return !element.isSelected
        case .labelContains:
            guard let expected = value else {
                throw WaitError.invalidCondition(condition: "labelContains", reason: "value parameter required")
            }
            guard let element = element else { return false }
            return element.label.localizedCaseInsensitiveContains(expected)
        case .labelEquals:
            guard let expected = value else {
                throw WaitError.invalidCondition(condition: "labelEquals", reason: "value parameter required")
            }
            guard let element = element else { return false }
            return element.label == expected
        case .valueContains:
            guard let expected = value else {
                throw WaitError.invalidCondition(condition: "valueContains", reason: "value parameter required")
            }
            guard let element = element else { return false }
            let currentValue = String(describing: element.value ?? "")
            return currentValue.localizedCaseInsensitiveContains(expected)
        case .valueEquals:
            guard let expected = value else {
                throw WaitError.invalidCondition(condition: "valueEquals", reason: "value parameter required")
            }
            guard let element = element else { return false }
            let currentValue = String(describing: element.value ?? "")
            return currentValue == expected
        }
    }
    
    /// Serialize XCUIElement to UINode
    private static func serialize(_ element: XCUIElement) -> UINode {
        UINode(
            type: "\(element.elementType.rawValue)",
            identifier: element.identifier,
            label: element.label,
            value: element.value as? String,
            placeholderValue: element.placeholderValue,
            title: element.title,
            frame: FrameWrapper(from: element.frame),
            isEnabled: element.isEnabled,
            isVisible: element.exists && !element.frame.isEmpty,
            isSelected: element.isSelected,
            hasFocus: element.hasFocus,
            children: []  // Don't serialize children in wait results
        )
    }
}
