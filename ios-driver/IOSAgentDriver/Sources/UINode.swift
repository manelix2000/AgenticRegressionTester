import Foundation
import XCTest

/// Error thrown when element snapshotting fails (element disappeared from the UI tree)
enum UINodeError: Error, LocalizedError {
    case snapshotFailed(description: String)

    var errorDescription: String? {
        switch self {
        case .snapshotFailed(let description):
            return "Element snapshot failed: \(description)"
        }
    }
}

/// Represents a node in the UI accessibility tree
/// Note: All methods are synchronous (XCTest APIs are synchronous)
struct UINode: Codable, Sendable {
    let type: String              // Element type (e.g., "XCUIElementTypeButton")
    let identifier: String        // Accessibility identifier
    let label: String             // Accessibility label
    let value: String?            // Element value (for text fields, etc.)
    let placeholderValue: String? // Placeholder text (for text fields)
    let title: String?            // Title attribute
    let frame: FrameWrapper       // Screen coordinates (custom wrapper for consistent encoding)
    let isEnabled: Bool           // Whether element is enabled for interaction
    let isVisible: Bool           // Whether element is visible (exists and not hidden)
    let isSelected: Bool          // Whether element is selected
    let hasFocus: Bool            // Whether element has keyboard focus
    let children: [UINode]        // Child elements in accessibility hierarchy

    // MARK: - Snapshot-based factory methods (single IPC round-trip)

    /// Creates a UINode from an XCUIElementSnapshot (no IPC — already fetched)
    private static func fromSnapshot(_ snap: XCUIElementSnapshot) -> UINode {
        UINode(
            type: "\(snap.elementType.rawValue)",
            identifier: snap.identifier,
            label: snap.label,
            value: snap.value as? String,
            placeholderValue: snap.placeholderValue,
            title: snap.title,
            frame: FrameWrapper(from: snap.frame),
            isEnabled: snap.isEnabled,
            isVisible: !snap.frame.isEmpty,
            isSelected: snap.isSelected,
            hasFocus: snap.hasFocus,
            children: snap.children.map { fromSnapshot($0) }
        )
    }

    /// Creates a UINode from an XCUIElementSnapshot without children
    private static func shallowFromSnapshot(_ snap: XCUIElementSnapshot) -> UINode {
        UINode(
            type: "\(snap.elementType.rawValue)",
            identifier: snap.identifier,
            label: snap.label,
            value: snap.value as? String,
            placeholderValue: snap.placeholderValue,
            title: snap.title,
            frame: FrameWrapper(from: snap.frame),
            isEnabled: snap.isEnabled,
            isVisible: !snap.frame.isEmpty,
            isSelected: snap.isSelected,
            hasFocus: snap.hasFocus,
            children: []
        )
    }

    /// Creates a UINode from an XCUIElementSnapshot with limited depth
    private static func fromSnapshot(_ snap: XCUIElementSnapshot, maxDepth: Int) -> UINode {
        guard maxDepth > 0 else {
            return shallowFromSnapshot(snap)
        }
        return UINode(
            type: "\(snap.elementType.rawValue)",
            identifier: snap.identifier,
            label: snap.label,
            value: snap.value as? String,
            placeholderValue: snap.placeholderValue,
            title: snap.title,
            frame: FrameWrapper(from: snap.frame),
            isEnabled: snap.isEnabled,
            isVisible: !snap.frame.isEmpty,
            isSelected: snap.isSelected,
            hasFocus: snap.hasFocus,
            children: snap.children.map { fromSnapshot($0, maxDepth: maxDepth - 1) }
        )
    }

    // MARK: - Public factory methods

    /// Creates a UINode with full depth using a single accessibility snapshot.
    /// - Parameter element: The XCUIElement to serialize
    /// - Throws: `UINodeError.snapshotFailed` if the element disappeared from the UI tree
    static func from(_ element: XCUIElement) throws -> UINode {
        do {
            let snap = try element.snapshot()
            return fromSnapshot(snap)
        } catch {
            throw UINodeError.snapshotFailed(description: error.localizedDescription)
        }
    }

    /// Creates a UINode without children using a single accessibility snapshot.
    /// - Parameter element: The XCUIElement to serialize
    /// - Throws: `UINodeError.snapshotFailed` if the element disappeared from the UI tree
    static func fromShallow(_ element: XCUIElement) throws -> UINode {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let snap = try element.snapshot()
            let node = shallowFromSnapshot(snap)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if elapsed > 100 {
                DriverLog.log("⏱ fromShallow(snapshot): \(String(format: "%.0f", elapsed))ms")
            }
            return node
        } catch {
            throw UINodeError.snapshotFailed(description: error.localizedDescription)
        }
    }

    /// Creates a UINode with limited depth using a single accessibility snapshot.
    /// - Parameters:
    ///   - element: The XCUIElement to serialize
    ///   - maxDepth: Maximum depth to traverse (0 = no children)
    /// - Throws: `UINodeError.snapshotFailed` if the element disappeared from the UI tree
    static func from(_ element: XCUIElement, maxDepth: Int) throws -> UINode {
        do {
            let snap = try element.snapshot()
            return fromSnapshot(snap, maxDepth: maxDepth)
        } catch {
            throw UINodeError.snapshotFailed(description: error.localizedDescription)
        }
    }
}

/// Response for UI tree query
struct UITreeResponse: Codable, Sendable {
    let root: UINode
    let timestamp: String
    let depth: Int?
}

/// Request for finding elements
struct FindElementsRequest: Codable, Sendable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let timeout: TimeInterval?
    let waitStrategy: WaitStrategy?
    
    enum WaitStrategy: String, Codable, Sendable {
        case wait       // Wait for element to exist
        case immediate  // Return immediately (no wait)
    }
}

/// Response for element queries
struct ElementsResponse: Codable, Sendable {
    let elements: [UINode]
    let count: Int
    let timestamp: String
}

/// Response for single element query
struct ElementResponse: Codable, Sendable {
    let element: UINode
    let timestamp: String
}

/// Request for tapping an element
struct TapRequest: Codable, Sendable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let timeout: TimeInterval?
    let waitStrategy: FindElementsRequest.WaitStrategy?
}

/// Response for tap action
struct TapResponse: Codable, Sendable {
    let success: Bool
    let identifier: String?
    let label: String?
    let predicate: String?
    let timestamp: String
}

/// Request for tapping at absolute screen coordinates
struct TapCoordinateRequest: Codable, Sendable {
    let x: CGFloat
    let y: CGFloat
}

/// Response for tap-coordinate action
struct TapCoordinateResponse: Codable, Sendable {
    let success: Bool
    let x: CGFloat
    let y: CGFloat
    let timestamp: String
}

/// Request for typing text
struct TypeTextRequest: Codable, Sendable {
    let text: String
    let identifier: String?
    let label: String?
    let predicate: String?
    let timeout: TimeInterval?
    let waitStrategy: FindElementsRequest.WaitStrategy?
    let clearFirst: Bool?
}

/// Response for type text action
struct TypeTextResponse: Codable, Sendable {
    let success: Bool
    let text: String
    let identifier: String?
    let label: String?
    let predicate: String?
    let timestamp: String
}

// MARK: - Swipe Models

/// Request for swipe gesture
struct SwipeRequest: Codable, Sendable {
    let direction: String // "up", "down", "left", "right"
    let identifier: String?
    let label: String?
    let predicate: String?
    let velocity: String? // "slow", "fast" (optional, defaults to "fast")
    let waitStrategy: FindElementsRequest.WaitStrategy?
    let timeout: TimeInterval?
}

/// Response for swipe action
struct SwipeResponse: Codable, Sendable {
    let success: Bool
    let direction: String
    let identifier: String?
    let label: String?
    let predicate: String?
    let timestamp: String
}

// MARK: - Scroll Models

/// Request for scroll to element
struct ScrollRequest: Codable, Sendable {
    let toElementIdentifier: String?
    let toElementPredicate: String?
    let scrollContainerIdentifier: String? // Optional scroll container
    let scrollContainerPredicate: String?
    let waitStrategy: FindElementsRequest.WaitStrategy?
    let timeout: TimeInterval?
}

/// Response for scroll action
struct ScrollResponse: Codable, Sendable {
    let success: Bool
    let toElementIdentifier: String?
    let toElementPredicate: String?
    let timestamp: String
}

// MARK: - Keyboard Models

/// Request for hardware keyboard typing
struct KeyboardTypeRequest: Codable, Sendable {
    let text: String? // Optional - can send just keys
    let keys: [String]? // Special keys: "return", "escape", "delete", "tab"
}

/// Response for keyboard typing
struct KeyboardTypeResponse: Codable, Sendable {
    let success: Bool
    let text: String?
    let keys: [String]?
    let timestamp: String
}

// MARK: - Screenshot Models

struct ScreenshotResponse: Codable, Sendable {
    let image: String  // Base64 encoded PNG
    let width: Int
    let height: Int
    let timestamp: String
}

struct ElementScreenshotRequest: Codable, Sendable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let timeout: TimeInterval?
    let waitStrategy: FindElementsRequest.WaitStrategy?
}

struct ElementScreenshotResponse: Codable, Sendable {
    let image: String  // Base64 encoded PNG
    let element: UINode
    let timestamp: String
}

struct CompareScreenshotRequest: Codable, Sendable {
    let referenceImage: String  // Base64 encoded PNG
    let threshold: Double?
}

struct CompareScreenshotResponse: Codable, Sendable {
    let match: Bool
    let similarity: Double
    let differenceCount: Int
    let totalPixels: Int
    let diffImage: String?  // Base64 encoded PNG (if differences exist)
    let timestamp: String
}

// MARK: - Validation Models

/// Validation property types
enum ValidationProperty: String, Codable, Sendable {
    case exists
    case isEnabled
    case isVisible
    case label
    case value
    case count
}

/// Rule for validating element properties
struct ValidationRule: Codable, Sendable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let property: String  // Will be converted to ValidationProperty enum
    let expectedValue: String
    let timeout: TimeInterval?
}

/// Validation result for a single check
struct ValidationResult: Codable, Sendable {
    let property: String
    let expected: String
    let actual: String
    let passed: Bool
    let message: String
}

struct ValidateRequest: Codable, Sendable {
    let validations: [ValidationRule]
}

struct ValidateResponse: Codable, Sendable {
    let results: [ValidationResult]
    let allPassed: Bool
    let passedCount: Int
    let failedCount: Int
    let timestamp: String
}

struct AssertRequest: Codable, Sendable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let property: String
    let expectedValue: String
    let timeout: TimeInterval?
}

struct AssertResponse: Codable, Sendable {
    let success: Bool
    let property: String
    let expected: String
    let actual: String
    let timestamp: String
}

// MARK: - Wait Operations

struct WaitRequest: Codable, Sendable {
    let condition: String         // Wait condition (exists, notExists, isEnabled, etc.)
    let identifier: String?       // Element accessibility identifier
    let label: String?            // Element accessibility label
    let predicate: String?        // NSPredicate query string
    let value: String?            // Expected value for text/value conditions
    let timeout: TimeInterval?    // Maximum time to wait (uses defaultTimeout if nil)
    let pollInterval: TimeInterval? // Time between checks (default: 0.5s)
}

struct WaitResponse: Codable, Sendable {
    let conditionMet: Bool        // Whether condition was met
    let condition: String         // Condition that was checked
    let element: UINode?          // Element that met condition (if applicable)
    let waitedTime: TimeInterval  // Actual time waited
    let timestamp: String
}
