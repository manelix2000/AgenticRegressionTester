import Foundation
import XCTest

/// Handles element querying and UI tree operations
/// Note: Methods are synchronous (XCTest APIs are synchronous)
final class ElementQuery: Sendable {
    
    /// Finds elements matching the given criteria
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier to match (optional)
    ///   - predicate: NSPredicate string to match (optional)
    ///   - timeout: Maximum time to wait for elements
    ///   - waitStrategy: Whether to wait for elements or return immediately
    /// - Returns: Array of matching elements serialized as UINodes
    /// - Throws: If query is invalid or timeout occurs
    @MainActor static func findElements(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> [UINode] {
        
        // Validate that at least one search criterion is provided
        guard identifier != nil || label != nil || predicate != nil else {
            throw QueryError.missingCriteria
        }
        
        // Build query
        let query: XCUIElementQuery
        
        if let identifier = identifier {
            // Search by accessibility identifier
            query = app.descendants(matching: .any).safeMatching(identifier: identifier)
        } else if let labelText = label {
            // Search by label (exact match)
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            query = app.descendants(matching: .any).matching(labelPredicate)
        } else if let predicateString = predicate {
            // Search by NSPredicate
            let nsPredicate = NSPredicate(format: predicateString)
            var caughtException: NSException?
            guard let safeQuery = app.descendants(matching: .any)
                .safeMatching(nsPredicate, exception: &caughtException) else {
                let reason = caughtException?.reason ?? predicateString
                throw QueryError.invalidPredicate(reason)
            }
            query = safeQuery
        } else {
            throw QueryError.missingCriteria
        }
        
        // Handle wait strategy
        if waitStrategy == .wait {
            // Wait for at least one element to exist
            let firstElement = query.firstMatch
            guard firstElement.waitForExistence(timeout: timeout) else {
                throw QueryError.elementNotFound(
                    identifier: identifier,
                    predicate: predicate,
                    timeout: timeout
                )
            }
        }
        
        // Get all matching elements
        let elements = query.safeAllElementsBoundByIndex()
        
        // Check if we found anything
        guard !elements.isEmpty else {
            throw QueryError.elementNotFound(
                identifier: identifier,
                predicate: predicate,
                timeout: timeout
            )
        }
        
        // Serialize to UINodes
        return elements.map { UINode.fromShallow($0) }
    }
    
    /// Finds a single element by identifier
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier
    ///   - timeout: Maximum time to wait
    ///   - waitStrategy: Whether to wait or return immediately
    /// - Returns: The matching element as UINode
    /// - Throws: If element not found or timeout
    @MainActor static func findElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> UINode {
        
        let element = app.descendants(matching: .any).safeMatching(identifier: identifier).firstMatch
        
        if waitStrategy == .wait {
            guard element.waitForExistence(timeout: timeout) else {
                throw QueryError.elementNotFound(
                    identifier: identifier,
                    predicate: nil,
                    timeout: timeout
                )
            }
        } else {
            guard element.exists else {
                throw QueryError.elementNotFound(
                    identifier: identifier,
                    predicate: nil,
                    timeout: 0
                )
            }
        }
        
        return UINode.fromShallow(element)
    }
    
    /// Gets the complete UI tree starting from app root
    /// - Parameters:
    ///   - app: The XCUIApplication to traverse
    ///   - maxDepth: Maximum depth to traverse (nil = unlimited)
    /// - Returns: Root UINode with complete hierarchy
    @MainActor static func getUITree(
        from app: XCUIApplication,
        maxDepth: Int
    ) -> UINode {
        return UINode.from(app, maxDepth: maxDepth)
    }
    
    /// Gets a specific XCUIElement by identifier
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier
    ///   - timeout: Maximum time to wait
    ///   - waitStrategy: Whether to wait or return immediately
    /// - Returns: The XCUIElement
    /// - Throws: If element not found
    @MainActor static func getElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> XCUIElement {
        
        let element = app.descendants(matching: .any).safeMatching(identifier: identifier).firstMatch
        
        if waitStrategy == .wait {
            guard element.waitForExistence(timeout: timeout) else {
                throw QueryError.elementNotFound(
                    identifier: identifier,
                    predicate: nil,
                    timeout: timeout
                )
            }
        } else {
            guard element.exists else {
                throw QueryError.elementNotFound(
                    identifier: identifier,
                    predicate: nil,
                    timeout: 0
                )
            }
        }
        
        return element
    }
    
    /// Gets a specific XCUIElement by predicate
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - predicateString: NSPredicate format string
    ///   - timeout: Maximum time to wait
    ///   - waitStrategy: Whether to wait or return immediately
    /// - Returns: The first matching XCUIElement
    /// - Throws: If element not found or predicate invalid
    @MainActor static func getElement(
        in app: XCUIApplication,
        predicate predicateString: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> XCUIElement {
        
        let nsPredicate = NSPredicate(format: predicateString)
        var caughtException: NSException?
        guard let query = app.descendants(matching: .any)
            .safeMatching(nsPredicate, exception: &caughtException) else {
            let reason = caughtException?.reason ?? predicateString
            throw QueryError.invalidPredicate(reason)
        }
        let element = query.firstMatch
        
        if waitStrategy == .wait {
            guard element.waitForExistence(timeout: timeout) else {
                throw QueryError.elementNotFound(
                    identifier: nil,
                    predicate: predicateString,
                    timeout: timeout
                )
            }
        } else {
            guard element.exists else {
                throw QueryError.elementNotFound(
                    identifier: nil,
                    predicate: predicateString,
                    timeout: 0
                )
            }
        }
        
        return element
    }
    
    // MARK: - Interactions
    
    /// Taps on an element
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier (optional)
    ///   - label: Accessibility label for exact match (optional)
    ///   - predicate: NSPredicate string (optional)
    ///   - timeout: Maximum time to wait for element
    ///   - waitStrategy: Whether to wait for element or tap immediately
    /// - Throws: If element not found or tap fails
    @MainActor static func tap(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws {
        
        let element: XCUIElement
        
        if let identifier = identifier {
            element = try getElement(
                in: app,
                identifier: identifier,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let labelText = label {
            // Search by label (exact match)
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            element = try getElement(
                in: app,
                predicate: labelPredicate.predicateFormat,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let predicateString = predicate {
            element = try getElement(
                in: app,
                predicate: predicateString,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else {
            throw QueryError.missingCriteria
        }
        
        guard element.safeIsHittable() else {
            throw InteractionError.elementNotHittable
        }
        
        element.tap()
    }
    
    /// Types text into an element (typically a text field or text view)
    /// - Parameters:
    ///   - text: The text to type
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier (optional)
    ///   - label: Accessibility label for exact match (optional)
    ///   - predicate: NSPredicate string (optional)
    ///   - timeout: Maximum time to wait for element
    ///   - waitStrategy: Whether to wait for element or type immediately
    ///   - clearFirst: Whether to clear existing text before typing (default: false)
    /// - Throws: If element not found or typing fails
    @MainActor static func typeText(
        _ text: String,
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait,
        clearFirst: Bool = false
    ) throws {
        
        let element: XCUIElement
        
        if let identifier = identifier {
            element = try getElement(
                in: app,
                identifier: identifier,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let labelText = label {
            // Search by label (exact match)
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            element = try getElement(
                in: app,
                predicate: labelPredicate.predicateFormat,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let predicateString = predicate {
            element = try getElement(
                in: app,
                predicate: predicateString,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else {
            throw QueryError.missingCriteria
        }
        
        // Verify element can receive keyboard input
        guard element.elementType == .textField || 
              element.elementType == .textView ||
              element.elementType == .searchField ||
              element.elementType == .secureTextField else {
            throw InteractionError.elementNotTypeable(type: "\(element.elementType)")
        }
        
        // Tap to focus
        element.tap()
        
        // Clear existing text if requested
        if clearFirst, let currentValue = element.value as? String, !currentValue.isEmpty {
            // Select all and delete
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteString)
        }
        
        element.typeText(text)
    }
    
    /// Performs a swipe gesture on the specified element or screen
    /// - Parameters:
    ///   - app: The application instance
    ///   - direction: Swipe direction ("up", "down", "left", "right")
    ///   - identifier: Accessibility identifier (optional)
    ///   - predicate: NSPredicate string (optional)
    ///   - velocity: Swipe velocity ("slow" or "fast", defaults to "fast")
    ///   - timeout: Maximum time to wait for element
    ///   - waitStrategy: Element wait strategy
    /// - Throws: QueryError if element not found, InteractionError if invalid direction

    @MainActor static func swipe(
        in app: XCUIApplication,
        direction: String,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        velocity: String = "fast",
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws {
        // If no element specified, swipe on the app itself
        let element: XCUIElement
        if identifier != nil || label != nil || predicate != nil {
            if let identifier = identifier {
                element = app.descendants(matching: .any).safeMatching(identifier: identifier).firstMatch
                if waitStrategy == .wait {
                    guard element.waitForExistence(timeout: timeout) else {
                        throw QueryError.elementNotFound(identifier: identifier, predicate: nil, timeout: timeout)
                    }
                }
            } else if let label = label {
                let nsPredicate = NSPredicate(format: "label == %@", label)
                element = app.descendants(matching: .any).matching(nsPredicate).firstMatch
                if waitStrategy == .wait {
                    guard element.waitForExistence(timeout: timeout) else {
                        throw QueryError.elementNotFound(identifier: nil, predicate: "label == '\(label)'", timeout: timeout)
                    }
                }
            } else if let predicate = predicate {
                let nsPredicate = NSPredicate(format: predicate)
                var caughtException: NSException?
                guard let safeQuery = app.descendants(matching: .any)
                    .safeMatching(nsPredicate, exception: &caughtException) else {
                    let reason = caughtException?.reason ?? predicate
                    throw QueryError.invalidPredicate(reason)
                }
                element = safeQuery.firstMatch
                if waitStrategy == .wait {
                    guard element.waitForExistence(timeout: timeout) else {
                        throw QueryError.elementNotFound(identifier: nil, predicate: predicate, timeout: timeout)
                    }
                }
            } else {
                element = app
            }
        } else {
            element = app
        }
        
        // Perform swipe based on direction and velocity
        // Note: XCUIElement swipe methods don't support velocity parameter in all iOS versions
        // Using default swipe methods which are fast by nature
        switch direction.lowercased() {
        case "up":
            element.swipeUp()
        case "down":
            element.swipeDown()
        case "left":
            element.swipeLeft()
        case "right":
            element.swipeRight()
        default:
            throw InteractionError.invalidSwipeDirection(direction)
        }
    }
    
    /// Scrolls a container until the target element becomes visible
    /// - Parameters:
    ///   - app: The application instance
    ///   - toElementIdentifier: Target element identifier
    ///   - toElementPredicate: Target element predicate
    ///   - scrollContainerIdentifier: Scroll container identifier (optional, defaults to first scroll view)
    ///   - scrollContainerPredicate: Scroll container predicate (optional)
    ///   - timeout: Maximum time to wait for element
    ///   - waitStrategy: Element wait strategy
    /// - Throws: QueryError if element not found

    @MainActor static func scrollToElement(
        in app: XCUIApplication,
        toElementIdentifier: String? = nil,
        toElementPredicate: String? = nil,
        scrollContainerIdentifier: String? = nil,
        scrollContainerPredicate: String? = nil,
        timeout: TimeInterval = 10,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws {
        // Find the scroll container
        let scrollContainer: XCUIElement
        if let containerId = scrollContainerIdentifier {
            scrollContainer = app.descendants(matching: .any).safeMatching(identifier: containerId).firstMatch
            if waitStrategy == .wait {
                guard scrollContainer.waitForExistence(timeout: timeout) else {
                    throw QueryError.elementNotFound(identifier: containerId, predicate: nil, timeout: timeout)
                }
            }
        } else if let containerPred = scrollContainerPredicate {
            let nsPredicate = NSPredicate(format: containerPred)
            var caughtException: NSException?
            guard let safeQuery = app.descendants(matching: .any)
                .safeMatching(nsPredicate, exception: &caughtException) else {
                let reason = caughtException?.reason ?? containerPred
                throw QueryError.invalidPredicate(reason)
            }
            scrollContainer = safeQuery.firstMatch
            if waitStrategy == .wait {
                guard scrollContainer.waitForExistence(timeout: timeout) else {
                    throw QueryError.elementNotFound(identifier: nil, predicate: containerPred, timeout: timeout)
                }
            }
        } else {
            // Default to first scroll view
            scrollContainer = app.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d OR elementType == %d", 
                                                                                    XCUIElement.ElementType.scrollView.rawValue,
                                                                                    XCUIElement.ElementType.table.rawValue)).firstMatch
            if !scrollContainer.exists {
                throw QueryError.elementNotFound(identifier: nil, predicate: "scrollView or table", timeout: timeout)
            }
        }
        
        // Find the target element
        let targetElement: XCUIElement
        if let targetId = toElementIdentifier {
            targetElement = scrollContainer.descendants(matching: .any).safeMatching(identifier: targetId).firstMatch
        } else if let targetPred = toElementPredicate {
            let nsPredicate = NSPredicate(format: targetPred)
            var caughtException: NSException?
            guard let safeQuery = scrollContainer.descendants(matching: .any)
                .safeMatching(nsPredicate, exception: &caughtException) else {
                let reason = caughtException?.reason ?? targetPred
                throw QueryError.invalidPredicate(reason)
            }
            targetElement = safeQuery.firstMatch
        } else {
            throw QueryError.missingCriteria
        }
        
        // Scroll to make element visible - XCTest automatically scrolls when accessing element
        // We just need to ensure it exists
        if waitStrategy == .wait {
            guard targetElement.waitForExistence(timeout: timeout) else {
                throw QueryError.elementNotFound(identifier: toElementIdentifier, predicate: toElementPredicate, timeout: timeout)
            }
        }
        
        // Ensure element is visible by trying to scroll to it
        // XCTest will automatically scroll when we interact with it
        if !targetElement.safeIsHittable() {
            // Try to scroll by swiping until element becomes hittable
            var attempts = 0
            let maxAttempts = 10
            while !targetElement.safeIsHittable() && attempts < maxAttempts {
                scrollContainer.swipeUp()
                attempts += 1
                if targetElement.safeIsHittable() {
                    break
                }
            }
        }
    }
    
    /// Types text using hardware keyboard
    /// - Parameters:
    ///   - app: The application instance
    ///   - text: Text to type
    ///   - keys: Special keys to press (return, escape, delete, tab)
    /// - Throws: InteractionError if keyboard not available
    /// - Note: Requires an element to have keyboard focus. Use /ui/tap first to focus an element.

    @MainActor static func keyboardType(
        in app: XCUIApplication,
        text: String? = nil,
        keys: [String]? = nil
    ) throws {
        // Type text if provided
        if let text = text, !text.isEmpty {
            app.typeText(text)
        }
        
        // Press special keys if provided
        if let keys = keys {
            for key in keys {
                switch key.lowercased() {
                case "return", "enter":
                    app.typeText("\n")
                case "delete", "backspace":
                    app.typeText(XCUIKeyboardKey.delete.rawValue)
                case "tab":
                    app.typeText("\t")
                case "escape", "esc":
                    // Escape key - try to dismiss keyboard or find escape button
                    // First try keyboard dismiss
                    if app.keyboards.count > 0 {
                        // Just send escape as text
                        app.typeText(String(Character(UnicodeScalar(27)))) // ESC character
                    }
                case "space":
                    app.typeText(" ")
                default:
                    throw InteractionError.invalidKey(key)
                }
            }
        }
    }
}

// MARK: - Interaction Errors

enum InteractionError: LocalizedError, Sendable {
    case elementNotHittable
    case elementNotTypeable(type: String)
    case invalidSwipeDirection(String)
    case invalidKey(String)
    
    var errorDescription: String? {
        switch self {
        case .elementNotHittable:
            return "Element is not hittable (not visible or not enabled)"
        case .elementNotTypeable(let type):
            return "Element of type '\(type)' cannot receive text input. Only textField, textView, searchField, and secureTextField elements support typing."
        case .invalidSwipeDirection(let direction):
            return "Invalid swipe direction '\(direction)'. Must be 'up', 'down', 'left', or 'right'"
        case .invalidKey(let key):
            return "Invalid special key '\(key)'. Supported keys: 'return', 'delete', 'tab', 'escape', 'space'"
        }
    }
}

// MARK: - Errors

enum QueryError: LocalizedError, Sendable {
    case missingCriteria
    case invalidPredicate(String)
    case elementNotFound(identifier: String?, predicate: String?, timeout: TimeInterval)
    case multipleElementsFound(count: Int)
    
    var errorDescription: String? {
        switch self {
        case .missingCriteria:
            return "Must provide either 'identifier', 'label', or 'predicate' to find elements"
        case .invalidPredicate(let pred):
            return "Invalid predicate format: '\(pred)'. Use NSPredicate syntax (e.g., 'label CONTAINS \"text\"')"
        case .elementNotFound(let id, let pred, let timeout):
            if let identifier = id {
                return "Element with identifier '\(identifier)' not found within \(timeout) seconds"
            } else if let predicate = pred {
                return "Element matching predicate '\(predicate)' not found within \(timeout) seconds"
            } else {
                return "Element not found within \(timeout) seconds"
            }
        case .multipleElementsFound(let count):
            return "Expected single element but found \(count) matching elements"
        }
    }
}
