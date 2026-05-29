import Foundation
import XCTest

/// Handles element querying and UI tree operations
/// Note: Methods touching XCTest use synchronous polling.
final class ElementQuery {
    private static let pollingInterval: TimeInterval = 0.1
    
    /// Builds a safe XCUI query from criteria.

    private static func buildQuery(
        in root: XCUIElement,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil
    ) throws -> XCUIElementQuery {
        if let identifier = identifier {
            DriverLog.log("buildQuery: by identifier=\(identifier)")
            return root.descendants(matching: .any).safeMatching(identifier: identifier)
        }
        
        if let labelText = label {
            DriverLog.log("buildQuery: by label=\(labelText)")
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            return root.descendants(matching: .any).safeMatching(predicate: labelPredicate)
        }
        
        if let predicateString = predicate {
            DriverLog.log("buildQuery: by predicate=\(predicateString)")
            guard let nsPredicate = NSPredicate.safePredicate(format: predicateString) else {
                throw QueryError.invalidPredicate(predicateString)
            }
            var caughtException: NSException?
            guard let safeQuery = root.descendants(matching: .any)
                .safeMatching(nsPredicate, exception: &caughtException) else {
                let reason = caughtException?.reason ?? predicateString
                throw QueryError.invalidPredicate(reason)
            }
            return safeQuery
        }
        
        throw QueryError.missingCriteria
    }
    
    /// Returns matched elements using safe enumeration and optional polling.

    private static func resolveElements(
        from query: XCUIElementQuery,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy
    ) -> [XCUIElement] {
        if waitStrategy == .immediate {
            let elements = query.safeAllElementsBoundByIndex()
            DriverLog.log("resolveElements: immediate, found \(elements.count)")
            return elements
        }
        
        DriverLog.log("resolveElements: polling with timeout=\(timeout)s")
        let deadline = Date().addingTimeInterval(max(timeout, 0))
        while true {
            let elements = query.safeAllElementsBoundByIndex()
            if !elements.isEmpty {
                DriverLog.log("resolveElements: found \(elements.count) elements")
                return elements
            }
            
            if Date() >= deadline {
                DriverLog.log("resolveElements: timeout expired, no elements found")
                return []
            }
            
            let sleepTime = min(Self.pollingInterval, deadline.timeIntervalSinceNow)
            if sleepTime > 0 {
                sleepForPolling(sleepTime)
            }
        }
    }
    

    private static func resolveElement(
        from query: XCUIElementQuery,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy
    ) -> XCUIElement? {
        resolveElements(from: query, timeout: timeout, waitStrategy: waitStrategy).first
    }
    
    private static func sleepForPolling(_ seconds: TimeInterval) {
        let clampedSeconds = max(0, seconds)
        guard clampedSeconds > 0 else { return }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: clampedSeconds))
    }
    
    /// Finds elements matching the given criteria
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier to match (optional)
    ///   - predicate: NSPredicate string to match (optional)
    ///   - timeout: Maximum time to wait for elements
    ///   - waitStrategy: Whether to wait for elements or return immediately
    /// - Returns: Array of matching elements serialized as UINodes
    /// - Throws: If query is invalid or timeout occurs
    static func findElements(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> [UINode] {
        DriverLog.log("findElements: identifier=\(identifier ?? "-") label=\(label ?? "-") predicate=\(predicate ?? "-") timeout=\(timeout)s")
        
        // Validate that at least one search criterion is provided
        guard identifier != nil || label != nil || predicate != nil else {
            throw QueryError.missingCriteria
        }
        
        let query = try buildQuery(
            in: app,
            identifier: identifier,
            label: label,
            predicate: predicate
        )
        
        let elements = resolveElements(
            from: query,
            timeout: timeout,
            waitStrategy: waitStrategy
        )
        
        // Check if we found anything
        guard !elements.isEmpty else {
            throw QueryError.elementNotFound(
                identifier: identifier,
                predicate: predicate,
                timeout: timeout
            )
        }
        
        // Serialize to UINodes
        DriverLog.log("findElements: found \(elements.count) elements")
        return try elements.map { try UINode.fromShallow($0) }
    }
    
    /// Finds a single element by identifier
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier
    ///   - timeout: Maximum time to wait
    ///   - waitStrategy: Whether to wait or return immediately
    /// - Returns: The matching element as UINode
    /// - Throws: If element not found or timeout
    static func findElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> UINode {
        let element = try getElement(
            in: app,
            identifier: identifier,
            timeout: timeout,
            waitStrategy: waitStrategy
        )
        return try UINode.fromShallow(element)
    }
    
    /// Gets the complete UI tree starting from app root
    /// - Parameters:
    ///   - app: The XCUIApplication to traverse
    ///   - maxDepth: Maximum depth to traverse (nil = unlimited)
    /// - Returns: Root UINode with complete hierarchy
    static func getUITree(
        from app: XCUIApplication,
        maxDepth: Int
    ) throws -> UINode {
        DriverLog.log("getUITree: maxDepth=\(maxDepth)")
        return try UINode.from(app, maxDepth: maxDepth)
    }
    
    /// Gets a specific XCUIElement by identifier
    /// - Parameters:
    ///   - app: The XCUIApplication to search in
    ///   - identifier: Accessibility identifier
    ///   - timeout: Maximum time to wait
    ///   - waitStrategy: Whether to wait or return immediately
    /// - Returns: The XCUIElement
    /// - Throws: If element not found
    static func getElement(
        in app: XCUIApplication,
        identifier: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> XCUIElement {
        DriverLog.log("getElement: identifier=\(identifier) timeout=\(timeout)s")
        let query = app.descendants(matching: .any).safeMatching(identifier: identifier)
        guard let element = resolveElement(
            from: query,
            timeout: timeout,
            waitStrategy: waitStrategy
        ) else {
            throw QueryError.elementNotFound(
                identifier: identifier,
                predicate: nil,
                timeout: waitStrategy == .wait ? timeout : 0
            )
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
    static func getElement(
        in app: XCUIApplication,
        predicate predicateString: String,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> XCUIElement {
        DriverLog.log("getElement: predicate=\(predicateString) timeout=\(timeout)s")
        let query = try buildQuery(
            in: app,
            predicate: predicateString
        )
        guard let element = resolveElement(
            from: query,
            timeout: timeout,
            waitStrategy: waitStrategy
        ) else {
            throw QueryError.elementNotFound(
                identifier: nil,
                predicate: predicateString,
                timeout: waitStrategy == .wait ? timeout : 0
            )
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
    static func tap(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws {
        DriverLog.log("tap: identifier=\(identifier ?? "-") label=\(label ?? "-") predicate=\(predicate ?? "-")")
        
        let element: XCUIElement
        
        if let identifier = identifier {
            element = try getElement(
                in: app,
                identifier: identifier,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let labelText = label {
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
            DriverLog.log("tap: element not hittable")
            throw InteractionError.elementNotHittable
        }
        
        element.tap()
    }
    
    /// Taps at absolute screen coordinates using XCUICoordinate.
    /// - Parameters:
    ///   - app: The XCUIApplication providing the coordinate space
    ///   - x: Absolute screen X coordinate in points
    ///   - y: Absolute screen Y coordinate in points
    static func tapAtCoordinate(in app: XCUIApplication, x: CGFloat, y: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let target = origin.withOffset(CGVector(dx: x, dy: y))
        target.tap()
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
    static func typeText(
        _ text: String,
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait,
        clearFirst: Bool = false
    ) throws {
        DriverLog.log("typeText: identifier=\(identifier ?? "-") label=\(label ?? "-") predicate=\(predicate ?? "-") textLength=\(text.count) clearFirst=\(clearFirst ? 1 : 0)")
        
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
        DriverLog.log("typeText: found element of type=\(element.elementType.rawValue)")
        guard element.elementType == .textField || 
              element.elementType == .textView ||
              element.elementType == .searchField ||
              element.elementType == .secureTextField else {
            DriverLog.log("typeText: element type \(element.elementType.rawValue) is not typeable")
            throw InteractionError.elementNotTypeable(type: "\(element.elementType)")
        }
        
        // Tap to focus
        DriverLog.log("typeText: tapping to focus")
        element.tap()
        
        // Clear existing text if requested
        if clearFirst, let currentValue = element.value as? String, !currentValue.isEmpty {
            DriverLog.log("typeText: clearing \(currentValue.count) existing chars")
            // Select all and delete
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count)
            element.typeText(deleteString)
        }
        
        DriverLog.log("typeText: typing \(text.count) chars")
        element.typeText(text)
    }
    
    /// Performs a swipe gesture on the specified element or screen
    ///   - app: The application instance
    ///   - direction: Swipe direction ("up", "down", "left", "right")
    ///   - identifier: Accessibility identifier (optional)
    ///   - predicate: NSPredicate string (optional)
    ///   - velocity: Swipe velocity ("slow" or "fast", defaults to "fast")
    ///   - timeout: Maximum time to wait for element
    ///   - waitStrategy: Element wait strategy
    /// - Throws: QueryError if element not found, InteractionError if invalid direction

    static func swipe(
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
        if let identifier = identifier {
            element = try getElement(
                in: app,
                identifier: identifier,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let labelText = label {
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            element = try getElement(
                in: app,
                predicate: labelPredicate.predicateFormat,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let predicate = predicate {
            element = try getElement(
                in: app,
                predicate: predicate,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else {
            element = app
        }
        
        // Validate element is visible and hittable before attempting the swipe
        // to avoid XCTest recording an internal failure that could crash the server
        if element !== app {
            guard !element.frame.isEmpty else {
                DriverLog.log("swipe: element has empty frame (offscreen)")
                throw InteractionError.elementNotSwipeable(
                    reason: "Element has an empty visible frame (likely offscreen). "
                        + "Try scrolling the element into view first or swipe on the app itself."
                )
            }
            guard element.safeIsHittable() else {
                DriverLog.log("swipe: element not hittable")
                throw InteractionError.elementNotSwipeable(
                    reason: "Element is not hittable (not visible or obscured by another element). "
                        + "Try scrolling the element into view first."
                )
            }
        }
        
        let gestureVelocity = XCUIGestureVelocity.from(velocity)
        
        switch direction.lowercased() {
        case "up":
            element.swipeUp(velocity: gestureVelocity)
        case "down":
            element.swipeDown(velocity: gestureVelocity)
        case "left":
            element.swipeLeft(velocity: gestureVelocity)
        case "right":
            element.swipeRight(velocity: gestureVelocity)
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

    static func scrollToElement(
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
            scrollContainer = try getElement(
                in: app,
                identifier: containerId,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else if let containerPred = scrollContainerPredicate {
            scrollContainer = try getElement(
                in: app,
                predicate: containerPred,
                timeout: timeout,
                waitStrategy: waitStrategy
            )
        } else {
            // Default to first scroll view
            let scrollContainerQuery = app.descendants(matching: .any).safeMatching(
                predicate: NSPredicate(
                    format: "elementType == %d OR elementType == %d",
                    XCUIElement.ElementType.scrollView.rawValue,
                    XCUIElement.ElementType.table.rawValue
                )
            )
            guard let firstContainer = resolveElement(
                from: scrollContainerQuery,
                timeout: timeout,
                waitStrategy: waitStrategy
            ) else {
                throw QueryError.elementNotFound(identifier: nil, predicate: "scrollView or table", timeout: timeout)
            }
            scrollContainer = firstContainer
        }
        
        // Find the target element
        let targetElement: XCUIElement
        if let targetId = toElementIdentifier {
            let targetQuery = scrollContainer.descendants(matching: .any).safeMatching(identifier: targetId)
            guard let found = resolveElement(
                from: targetQuery,
                timeout: timeout,
                waitStrategy: waitStrategy
            ) else {
                throw QueryError.elementNotFound(
                    identifier: toElementIdentifier,
                    predicate: toElementPredicate,
                    timeout: waitStrategy == .wait ? timeout : 0
                )
            }
            targetElement = found
        } else if let targetPred = toElementPredicate {
            let targetQuery = try buildQuery(
                in: scrollContainer,
                predicate: targetPred
            )
            guard let found = resolveElement(
                from: targetQuery,
                timeout: timeout,
                waitStrategy: waitStrategy
            ) else {
                throw QueryError.elementNotFound(
                    identifier: toElementIdentifier,
                    predicate: toElementPredicate,
                    timeout: waitStrategy == .wait ? timeout : 0
                )
            }
            targetElement = found
        } else {
            throw QueryError.missingCriteria
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

    static func keyboardType(
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
    case elementNotSwipeable(reason: String)
    case invalidSwipeDirection(String)
    case invalidKey(String)
    
    var errorDescription: String? {
        switch self {
        case .elementNotHittable:
            return "Element is not hittable (not visible or not enabled)"
        case .elementNotTypeable(let type):
            return "Element of type '\(type)' cannot receive text input. Only textField, textView, searchField, and secureTextField elements support typing."
        case .elementNotSwipeable(let reason):
            return "Cannot swipe on element: \(reason)"
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

// MARK: - Gesture Velocity Mapping

extension XCUIGestureVelocity {
    /// Creates a gesture velocity from a string value.
    /// - Parameter string: One of "slow", "default", or "fast" (default)
    /// - Returns: The corresponding `XCUIGestureVelocity`
    static func from(_ string: String) -> XCUIGestureVelocity {
        switch string.lowercased() {
        case "slow":
            return .slow
        case "default":
            return .default
        case "fast":
            return .fast
        default:
            return .fast
        }
    }
}
