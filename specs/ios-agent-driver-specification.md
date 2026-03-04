# iOS Runner - Technical Specification

**Version**: 1.0.0  
**Date**: 2026-03-01  
**Status**: Draft

---

## 1. Overview

### 1.1 Purpose
iOS Runner is a UI test runner for iOS applications that exposes a JSON API via HTTP to interact with apps deployed on the iOS Simulator using the Accessibility tree based on XCTest.

### 1.2 Goals
- Enable automated UI testing through a REST API
- Support multiple simultaneous runners on different simulators
- Provide comprehensive element discovery and interaction capabilities
- Offer both soft validations and hard assertions
- Support visual regression testing via screenshots

---

## 2. Architecture

### 2.1 Technology Stack
- **Target Type**: UI Testing Bundle (XCTest)
- **Build System**: Tuist
- **Minimum iOS Version**: iOS 17+
- **Language**: Swift 5.9+
- **Networking**: Network framework (NWListener/NWConnection)
- **Serialization**: Codable for JSON
- **Testing Framework**: XCTest

### 2.2 Key Components

#### HTTP Server Layer
- NWListener-based server with configurable port
- Request routing and handling
- Concurrent request management (max 10 by default)
- JSON request/response serialization

#### XCTest Bridge Layer
- Wraps XCUIApplication and XCUIElement APIs
- Manages app lifecycle (launch, terminate, state)
- Provides element query and interaction methods

#### Element Serialization Layer
- Converts XCUIElement accessibility tree to JSON
- Recursive traversal of element hierarchy
- Property extraction and formatting

#### Request Router
- Maps HTTP endpoints to test operations
- Validates request parameters
- Handles query string and body parsing

#### Response Builder
- Formats operation results as JSON
- Constructs error responses with appropriate HTTP status codes
- Manages response headers and content-type

---

## 3. Core Data Models

### 3.1 UINode Structure

```swift
struct UINode: Codable, Sendable {
    let type: String              // Element type (e.g., "button", "textField")
    let identifier: String        // Accessibility identifier
    let label: String             // Accessibility label
    let value: String?            // Element value (for text fields, etc.)
    let frame: CGRect             // Screen coordinates
    let isEnabled: Bool           // Interaction state
    let isVisible: Bool           // Visibility state
    let children: [UINode]        // Child elements
}
```

**Properties**:
- `type`: XCUIElement.ElementType as string representation
- `identifier`: XCUIElement.identifier (accessibility identifier)
- `label`: XCUIElement.label (accessibility label)
- `value`: XCUIElement.value (optional, for inputs)
- `frame`: XCUIElement.frame (CGRect with x, y, width, height)
- `isEnabled`: XCUIElement.isEnabled (interaction state)
- `isVisible`: XCUIElement.isHittable (visibility/interactable state)
- `children`: Recursively serialized child elements

### 3.2 Configuration Model

```swift
struct RunnerConfig: Codable {
    let port: Int                      // HTTP server port (default: 8080)
    let defaultTimeout: TimeInterval   // Default element wait timeout (default: 5s)
    let errorVerbosity: ErrorVerbosity // Verbose or simple errors
    let maxConcurrentRequests: Int     // Request concurrency limit (default: 10)
}

enum ErrorVerbosity: String, Codable {
    case verbose  // Includes stack traces and detailed info
    case simple   // User-friendly messages only
}
```

### 3.3 Error Response Model

```swift
struct ErrorResponse: Codable {
    let error: String              // Error type/code
    let message: String            // Human-readable message
    let details: String?           // Stack trace (verbose mode only)
    let timestamp: String          // ISO 8601 timestamp
    let suggestion: String?        // Suggested fix
}
```

---

## 4. API Specification

### 4.1 Server Control

#### GET /health
Returns server health and readiness status.

**Response**:
```json
{
  "status": "ok",
  "version": "1.0.0"
}
```

**Status Codes**:
- `200 OK` - Server is healthy

---

#### POST /config
Updates runtime configuration.

**Request Body**:
```json
{
  "defaultTimeout": 10,
  "errorVerbosity": "verbose"
}
```

**Response**:
```json
{
  "success": true,
  "config": {
    "port": 8080,
    "defaultTimeout": 10,
    "errorVerbosity": "verbose",
    "maxConcurrentRequests": 10
  }
}
```

**Status Codes**:
- `200 OK` - Configuration updated
- `400 Bad Request` - Invalid configuration values

---

### 4.2 Application Control

#### POST /app/launch
Launches an application by bundle identifier.

**Request Body**:
```json
{
  "bundleId": "com.example.app",
  "arguments": ["--test-mode"],
  "environment": {
    "API_URL": "http://localhost:3000"
  }
}
```

**Response**:
```json
{
  "success": true,
  "pid": 12345
}
```

**Status Codes**:
- `200 OK` - App launched successfully
- `400 Bad Request` - Invalid bundle ID
- `409 Conflict` - App already running

---

#### POST /app/terminate
Terminates the currently running application.

**Request Body**:
```json
{
  "bundleId": "com.example.app"
}
```

**Response**:
```json
{
  "success": true
}
```

**Status Codes**:
- `200 OK` - App terminated
- `404 Not Found` - App not running

---

#### GET /app/state
Returns the current application state.

**Response**:
```json
{
  "bundleId": "com.example.app",
  "state": "runningForeground",
  "pid": 12345
}
```

**State Values**:
- `notRunning`
- `runningBackground`
- `runningForeground`
- `runningBackgroundSuspended`

**Status Codes**:
- `200 OK` - State retrieved

---

### 4.3 UI Tree Operations

#### GET /ui/tree
Returns the complete accessibility hierarchy.

**Query Parameters**:
- `maxDepth` (optional, integer): Maximum traversal depth (default: unlimited)

**Response**:
```json
{
  "root": {
    "type": "application",
    "identifier": "",
    "label": "MyApp",
    "value": null,
    "frame": { "x": 0, "y": 0, "width": 375, "height": 812 },
    "isEnabled": true,
    "isVisible": true,
    "children": [...]
  }
}
```

**Status Codes**:
- `200 OK` - Tree retrieved
- `409 Conflict` - App not running

---

#### POST /ui/find
Finds elements matching a predicate or identifier.

**Request Body (by identifier)**:
```json
{
  "identifier": "loginButton",
  "timeout": 5,
  "waitStrategy": "wait"
}
```

**Request Body (by predicate)**:
```json
{
  "predicate": "label CONTAINS 'Login'",
  "timeout": 5,
  "waitStrategy": "wait"
}
```

**Response**:
```json
{
  "elements": [
    {
      "type": "button",
      "identifier": "loginButton",
      "label": "Login",
      ...
    }
  ],
  "count": 1
}
```

**Wait Strategies**:
- `wait` (default): Retry until found or timeout
- `immediate`: Return immediately if not found

**Status Codes**:
- `200 OK` - Elements found (empty array if none)
- `408 Request Timeout` - Timeout waiting for elements

---

#### GET /ui/element/{identifier}
Gets a single element by accessibility identifier.

**Path Parameters**:
- `identifier`: Accessibility identifier

**Query Parameters**:
- `timeout` (optional, number): Wait timeout in seconds (default: 5)
- `waitStrategy` (optional, string): "wait" or "immediate" (default: "wait")

**Response**:
```json
{
  "element": {
    "type": "button",
    "identifier": "loginButton",
    ...
  }
}
```

**Status Codes**:
- `200 OK` - Element found
- `404 Not Found` - Element not found
- `408 Request Timeout` - Timeout waiting for element

---

### 4.4 Interaction Operations

#### POST /ui/tap
Taps an element by identifier or predicate.

**Request Body**:
```json
{
  "identifier": "loginButton",
  "timeout": 5,
  "waitStrategy": "wait"
}
```

**Alternative**:
```json
{
  "predicate": "label == 'Login'",
  "timeout": 5
}
```

**Response**:
```json
{
  "success": true,
  "tappedElement": {
    "type": "button",
    "identifier": "loginButton",
    ...
  }
}
```

**Status Codes**:
- `200 OK` - Tap successful
- `404 Not Found` - Element not found
- `408 Request Timeout` - Timeout waiting for element

---

#### POST /ui/type
Types text into an element.

**Request Body**:
```json
{
  "identifier": "usernameField",
  "text": "user@example.com",
  "clearFirst": true,
  "timeout": 5
}
```

**Properties**:
- `clearFirst` (optional, boolean): Clear existing text before typing (default: false)

**Response**:
```json
{
  "success": true,
  "element": {
    "type": "textField",
    "identifier": "usernameField",
    "value": "user@example.com",
    ...
  }
}
```

**Status Codes**:
- `200 OK` - Text typed successfully
- `404 Not Found` - Element not found
- `408 Request Timeout` - Timeout waiting for element

---

#### POST /ui/swipe
Performs a swipe gesture on an element.

**Request Body**:
```json
{
  "identifier": "scrollView",
  "direction": "up",
  "velocity": "fast"
}
```

**Direction Values**:
- `up`, `down`, `left`, `right`

**Velocity Values**:
- `slow`, `normal`, `fast`

**Response**:
```json
{
  "success": true
}
```

**Status Codes**:
- `200 OK` - Swipe performed
- `404 Not Found` - Element not found

---

#### POST /ui/scroll
Scrolls to make an element visible.

**Request Body**:
```json
{
  "identifier": "targetElement",
  "timeout": 10
}
```

**Response**:
```json
{
  "success": true,
  "element": {
    "type": "cell",
    "identifier": "targetElement",
    ...
  }
}
```

**Status Codes**:
- `200 OK` - Element scrolled into view
- `404 Not Found` - Element not found
- `408 Request Timeout` - Timeout scrolling to element

---

### 4.5 Validation & Assertions

#### POST /ui/validate
Performs soft validations (returns results without failing).

**Request Body**:
```json
{
  "validations": [
    {
      "identifier": "loginButton",
      "property": "isEnabled",
      "expected": true
    },
    {
      "identifier": "errorLabel",
      "property": "exists",
      "expected": false
    }
  ]
}
```

**Supported Properties**:
- `exists`, `isEnabled`, `isVisible`, `label`, `value`

**Response**:
```json
{
  "results": [
    {
      "passed": true,
      "identifier": "loginButton",
      "property": "isEnabled",
      "actual": true,
      "expected": true
    },
    {
      "passed": true,
      "identifier": "errorLabel",
      "property": "exists",
      "actual": false,
      "expected": false
    }
  ],
  "allPassed": true
}
```

**Status Codes**:
- `200 OK` - Validations completed (check results)

---

#### POST /ui/assert
Performs hard assertion (fails on mismatch).

**Request Body**:
```json
{
  "identifier": "errorLabel",
  "property": "exists",
  "expected": false,
  "timeout": 5
}
```

**Response**:
```json
{
  "success": true
}
```

**Status Codes**:
- `200 OK` - Assertion passed
- `400 Bad Request` - Assertion failed

---

### 4.6 Screenshots

#### GET /screenshot
Captures a full screen screenshot.

**Query Parameters**:
- `format` (optional): "png" (default)
- `scale` (optional, number): Image scale factor (default: 1.0)

**Response**:
```json
{
  "image": "iVBORw0KGgoAAAANSUhEUgAA...",
  "size": {
    "width": 375,
    "height": 812
  }
}
```

**Properties**:
- `image`: Base64-encoded PNG data

**Status Codes**:
- `200 OK` - Screenshot captured

---

#### POST /screenshot/element
Captures a screenshot of a specific element.

**Request Body**:
```json
{
  "identifier": "errorMessage"
}
```

**Response**:
```json
{
  "image": "iVBORw0KGgoAAAANSUhEUgAA...",
  "element": {
    "type": "label",
    "identifier": "errorMessage",
    ...
  }
}
```

**Status Codes**:
- `200 OK` - Element screenshot captured
- `404 Not Found` - Element not found

---

#### POST /screenshot/compare
Compares current screen with a reference image.

**Request Body**:
```json
{
  "referenceImage": "iVBORw0KGgoAAAANSUhEUgAA...",
  "threshold": 0.95
}
```

**Properties**:
- `referenceImage`: Base64-encoded reference image
- `threshold`: Similarity threshold (0.0-1.0)

**Response**:
```json
{
  "match": true,
  "similarity": 0.98,
  "diff": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

**Properties**:
- `diff`: Base64-encoded difference image (optional, only if not matching)

**Status Codes**:
- `200 OK` - Comparison completed

---

### 4.7 Advanced Features (Proposed)

#### POST /ui/gesture
Performs custom gestures.

**Request Body**:
```json
{
  "type": "longPress",
  "identifier": "imageView",
  "duration": 2.0
}
```

**Gesture Types**:
- `longPress`, `pinch`, `rotate`

---

#### POST /ui/drag
Drags from one element to another.

**Request Body**:
```json
{
  "from": "itemA",
  "to": "dropZone",
  "duration": 1.0
}
```

---

#### GET /ui/alerts
Lists active system alerts and dialogs.

**Response**:
```json
{
  "alerts": [
    {
      "title": "Allow Location Access",
      "message": "MyApp would like to access your location",
      "buttons": ["Allow", "Don't Allow"]
    }
  ]
}
```

---

#### POST /ui/alert/dismiss
Dismisses an alert by button label.

**Request Body**:
```json
{
  "buttonLabel": "Allow"
}
```

---

#### POST /ui/keyboard/type
Types text using the hardware keyboard (faster than element typing).

**Request Body**:
```json
{
  "text": "hello world"
}
```

---

#### GET /ui/accessibility/audit
Performs an accessibility audit on the current screen.

**Response**:
```json
{
  "issues": [
    {
      "severity": "warning",
      "element": {...},
      "issue": "Missing accessibility label",
      "suggestion": "Add accessibility label to improve VoiceOver support"
    }
  ]
}
```

---

#### POST /ui/wait
Explicit wait for a condition.

**Request Body**:
```json
{
  "condition": "exists",
  "identifier": "successMessage",
  "timeout": 10
}
```

**Condition Types**:
- `exists`, `notExists`, `enabled`, `disabled`, `visible`, `notVisible`

---

## 5. Error Handling

### 5.1 HTTP Status Codes

- **200 OK** - Successful operation
- **400 Bad Request** - Invalid request format or parameters
- **404 Not Found** - Element or resource not found
- **408 Request Timeout** - Operation timeout exceeded
- **409 Conflict** - State conflict (e.g., app not launched)
- **500 Internal Server Error** - Unexpected server error

### 5.2 Error Response Format

```json
{
  "error": "ElementNotFound",
  "message": "Could not find element with identifier 'loginButton'",
  "details": "XCUIElement query failed after 5.0s timeout\nStack trace: ...",
  "timestamp": "2026-03-01T09:00:00Z",
  "suggestion": "Verify the accessibility identifier is correct and the element is visible"
}
```

**Error Types**:
- `ElementNotFound` - Element not found in hierarchy
- `ElementNotInteractable` - Element exists but cannot be interacted with
- `Timeout` - Operation exceeded timeout
- `InvalidRequest` - Malformed request body or parameters
- `AppNotRunning` - Operation requires app to be running
- `InvalidBundleId` - Bundle identifier is invalid or app not installed
- `InternalError` - Unexpected error in runner

---

## 6. Configuration

### 6.1 Port Configuration

**Default**: 8080

**Configuration Methods**:
1. Launch argument: `--port 8081`
2. Environment variable: `IOS_RUNNER_PORT=8081`
3. Runtime via `/config` endpoint

**Range**: 1024-65535

### 6.2 Timeout Configuration

**Default**: 5 seconds

**Configuration Methods**:
1. Global default via `/config` endpoint
2. Per-request via `timeout` parameter

**Range**: 0-300 seconds

### 6.3 Error Verbosity

**Default**: `simple`

**Options**:
- `simple`: User-friendly messages only
- `verbose`: Includes stack traces and detailed debugging info

### 6.4 Concurrency

**Default**: 10 concurrent requests

**Configuration Method**: Via `/config` endpoint

**Range**: 1-50 requests

---

## 7. Implementation Decisions

### 7.1 Network Framework over URLSession
**Decision**: Use NWListener from Network framework

**Reasoning**: NWListener provides lower-level control, better performance for server use cases, and simpler port binding. URLSession is designed for HTTP clients, not servers.

### 7.2 Base64 Screenshots in JSON
**Decision**: Return screenshots as base64-encoded strings in JSON responses

**Reasoning**: Simplifies API consumption (single response), eliminates file management, works well with JSON-based clients. Trade-off: larger payloads, but acceptable for testing scenarios.

### 7.3 Extended UINode Properties
**Decision**: Add `value`, `isEnabled`, `isVisible` to UINode

**Reasoning**: Essential for element validation and selection. Without them, clients would need multiple API calls to check element state.

### 7.4 Soft Validations vs Assertions
**Decision**: Provide both `/ui/validate` (soft) and `/ui/assert` (hard) endpoints

**Reasoning**: Soft validations allow collecting multiple validation results without stopping execution. Assertions provide traditional test behavior. Different use cases require different strategies.

### 7.5 Wait Strategy Configuration
**Decision**: Default to "wait" strategy with per-request override

**Reasoning**: Most UI testing benefits from implicit waits (handles async UI). Advanced users can opt into immediate mode for specific validations.

### 7.6 Predicate vs Identifier Selection
**Decision**: Support both accessibility identifiers and NSPredicate queries

**Reasoning**: Identifiers are fast and simple for known elements. Predicates enable complex queries for dynamic content.

### 7.7 Screenshot Comparison Feature
**Decision**: Include image comparison endpoint

**Reasoning**: Visual regression testing is a common requirement. Built-in comparison saves clients from implementing diffing logic.

---

## 8. Open Questions

1. **Tuist Configuration**: Should we use a specific Tuist template or custom configuration?
2. **Swift Version**: Target Swift 5.9 or Swift 6 with strict concurrency?
3. **Dependencies**: Any third-party dependencies allowed or keep it pure Foundation/XCTest?
4. **Testing Strategy**: Should the runner itself have tests, and how (mocked XCTest)?
5. **Deployment**: How will runners be installed/launched (CLI tool, Xcode scheme)?

---

## 9. Success Criteria

- ✅ Single Tuist project with UITest target
- ✅ HTTP server with configurable port via NWListener
- ✅ All core endpoints functional (launch, tree, tap, type, find, screenshot)
- ✅ Support for multiple simultaneous runners on different simulators
- ✅ JSON API with comprehensive error handling
- ✅ Configurable timeouts and wait strategies
- ✅ Base64 screenshot support
- ✅ Soft validation and assertion capabilities
- ✅ Clean, documented Swift code following project guidelines
- ✅ No force unwraps or force casts

---

## 10. Future Enhancements

1. **Performance Metrics** - Return operation timing in responses
2. **Session Recording** - Record all operations for playback/debugging
3. **Element Highlighting** - Flash element before interaction for visual debugging
4. **Batch Operations** - Execute multiple operations in single request
5. **Event Monitoring** - Subscribe to app events via WebSocket
6. **Snapshot Management** - Save/restore UI snapshots for test isolation
7. **Device Capabilities** - Report simulator capabilities (screen size, iOS version)
8. **Log Streaming** - Stream app console logs via WebSocket or SSE
