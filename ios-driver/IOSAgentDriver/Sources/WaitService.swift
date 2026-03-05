import XCTest
import Foundation

/// Service for explicit wait operations using XCTest native mechanisms
/// This service uses XCUIElement.waitForExistence() and XCTNSPredicateExpectation
/// for optimal performance and stability, following Apple's guidelines for XCUITest
@MainActor
final class WaitService {
    
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
    
    /// Wait for a specific condition using XCTest native mechanisms
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
        
        do {
            // Validate identifier usage
            let identifierCount = [identifier, label, predicate].compactMap { $0 }.count
            guard identifierCount <= 1 else {
                throw WaitError.multipleIdentifiers
            }
            
            // Find the element
            let element = try findElement(
                in: app,
                identifier: identifier,
                label: label,
                predicate: predicate
            )
            
            // Wait for condition using XCTest native mechanisms
            try waitForCondition(
                element: element,
                condition: condition,
                value: value,
                timeout: timeout
            )
            
            // Success!
            let actualTime = Date().timeIntervalSince(startTime)
            let node = serialize(element)
            
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
            
            if softValidation {
                // Soft validation: Log warning but don't throw
                print("⚠️ Wait failed (soft validation): \(error.localizedDescription)")
                
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
    
    /// Wait for condition using appropriate XCTest mechanism
    private static func waitForCondition(
        element: XCUIElement,
        condition: WaitCondition,
        value: String?,
        timeout: TimeInterval
    ) throws {
        
        switch condition {
        
        // MARK: - Simple Existence Checks
        
        case .exists:
            // Use XCUIElement.waitForExistence (fastest, most reliable)
            guard element.waitForExistence(timeout: timeout) else {
                throw WaitError.conditionNotMet(condition: "exists", timeout: timeout)
            }
        
        case .notExists:
            // Wait for element to disappear
            let predicate = NSPredicate(format: "exists == false")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "notExists")
        
        // MARK: - State Checks (use XCTNSPredicateExpectation)
        
        case .isEnabled:
            let predicate = NSPredicate(format: "isEnabled == true")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isEnabled")
        
        case .isDisabled:
            let predicate = NSPredicate(format: "isEnabled == false")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isDisabled")
        
        case .isHittable:
            let predicate = NSPredicate(format: "isHittable == true")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isHittable")
        
        case .isNotHittable:
            let predicate = NSPredicate(format: "isHittable == false")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isNotHittable")
        
        case .hasFocus:
            let predicate = NSPredicate(format: "hasFocus == true")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "hasFocus")
        
        case .isSelected:
            let predicate = NSPredicate(format: "isSelected == true")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isSelected")
        
        case .isNotSelected:
            let predicate = NSPredicate(format: "isSelected == false")
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "isNotSelected")
        
        // MARK: - Text/Value Checks (use XCTNSPredicateExpectation)
        
        case .labelContains:
            guard let expectedValue = value else {
                throw WaitError.invalidCondition(condition: "labelContains", reason: "value parameter required")
            }
            let predicate = NSPredicate(format: "label CONTAINS[cd] %@", expectedValue)
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "labelContains")
        
        case .labelEquals:
            guard let expectedValue = value else {
                throw WaitError.invalidCondition(condition: "labelEquals", reason: "value parameter required")
            }
            let predicate = NSPredicate(format: "label == %@", expectedValue)
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "labelEquals")
        
        case .valueContains:
            guard let expectedValue = value else {
                throw WaitError.invalidCondition(condition: "valueContains", reason: "value parameter required")
            }
            let predicate = NSPredicate(format: "value CONTAINS[cd] %@", expectedValue)
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "valueContains")
        
        case .valueEquals:
            guard let expectedValue = value else {
                throw WaitError.invalidCondition(condition: "valueEquals", reason: "value parameter required")
            }
            let predicate = NSPredicate(format: "value == %@", expectedValue)
            try waitWithPredicate(element: element, predicate: predicate, timeout: timeout, condition: "valueEquals")
        }
    }
    
    /// Wait using XCTNSPredicateExpectation (XCTest native)
    private static func waitWithPredicate(
        element: XCUIElement,
        predicate: NSPredicate,
        timeout: TimeInterval,
        condition: String
    ) throws {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        
        guard result == .completed else {
            throw WaitError.conditionNotMet(
                condition: condition,
                timeout: timeout
            )
        }
    }
    
    /// Find element by identifier, label, or predicate
    private static func findElement(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil
    ) throws -> XCUIElement {
        
        if let identifier = identifier {
            // Find by accessibility identifier
            return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        
        if let label = label {
            // Find by accessibility label
            let nsPredicate = NSPredicate(format: "label == %@", label)
            return app.descendants(matching: .any).matching(nsPredicate).firstMatch
        }
        
        if let predicateString = predicate {
            // Find by custom predicate
            let nsPredicate = NSPredicate(format: predicateString)
            return app.descendants(matching: .any).matching(nsPredicate).firstMatch
        }
        
        throw WaitError.invalidCondition(condition: "find", reason: "No identifier, label, or predicate provided")
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
