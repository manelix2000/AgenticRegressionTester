import Foundation

// MARK: - Health Response

struct HealthResponse: Codable {
    let status: String
    let version: String?
    let uptime: Double?
}

// MARK: - App Management

struct LaunchAppRequest: Codable {
    let bundleId: String
    let arguments: [String]?
    let environment: [String: String]?
}

struct LaunchAppResponse: Codable {
    let success: Bool
    let pid: Int?
}

struct TerminateAppRequest: Codable {
    let bundleId: String
}

struct TerminateAppResponse: Codable {
    let success: Bool
}

struct AppStateResponse: Codable {
    let bundleId: String?
    let state: String
    let pid: Int?
}

// MARK: - UI Tree

struct FrameRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct UINode: Codable {
    let type: String
    let identifier: String
    let label: String
    let value: String?
    let placeholderValue: String?
    let title: String?
    let frame: FrameRect
    let isEnabled: Bool
    let isVisible: Bool
    let isSelected: Bool
    let hasFocus: Bool
    let children: [UINode]
}

struct GetUITreeResponse: Codable {
    let root: UINode
    let timestamp: String
    let depth: Int?
}

// MARK: - Element Finding

struct GetElementRequest: Codable {
    let identifier: String
    let timeout: Double?
    let waitStrategy: String?
}

struct GetElementResponse: Codable {
    let element: UINode
}

struct FindElementsRequest: Codable {
    let predicate: String?
    let identifier: String?
    let timeout: Double?
    let waitStrategy: String?
}

struct FindElementsResponse: Codable {
    let elements: [UINode]
    let count: Int
}

struct FindElementResponse: Codable {
    let element: UINode
}

// MARK: - Interactions

struct TapRequest: Codable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let timeout: Double?
    let waitStrategy: String?
}

struct TapResponse: Codable {
    let success: Bool
    let tappedElement: UINode?
}

struct TypeTextRequest: Codable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let text: String
    let clearFirst: Bool?
    let timeout: Double?
    let waitStrategy: String?
}

struct TypeTextResponse: Codable {
    let success: Bool
    let element: UINode?
}

struct SwipeRequest: Codable {
    let identifier: String?
    let label: String?
    let predicate: String?
    let direction: String
    let velocity: String?
}

struct SwipeResponse: Codable {
    let success: Bool
}

// MARK: - Screenshots

struct ScreenshotResponse: Codable {
    let image: String  // base64 encoded
    let width: Double
    let height: Double
    let timestamp: String
}

struct ScreenshotElementRequest: Codable {
    let identifier: String
}

struct ScreenshotElementResponse: Codable {
    let image: String  // base64 encoded
    let element: UINode
}

struct ScreenshotCompareRequest: Codable {
    let referenceImage: String  // base64 encoded
    let threshold: Double?
}

struct ScreenshotCompareResponse: Codable {
    let match: Bool
    let similarity: Double
    let diff: String?  // base64 encoded diff image
}

// MARK: - Validation

struct WaitRequest: Codable {
    let condition: String
    let identifier: String?
    let label: String?
    let predicate: String?
    let value: String?
    let timeout: Double?
    let softValidation: Bool?
}

struct WaitResponse: Codable {
    let conditionMet: Bool
    let condition: String
    let element: UINode?
    let waitedTime: Double
    let timestamp: String
}

struct WaitForElementRequest: Codable {
    let predicate: String?
    let identifier: String?
    let condition: String?
    let timeout: Double?
}

struct WaitForElementResponse: Codable {
    let success: Bool
    let element: UINode?
}

struct AssertRequest: Codable {
    let identifier: String?
    let predicate: String?
    let property: String
    let expected: Bool
    let timeout: Double?
}

struct AssertResponse: Codable {
    let success: Bool
}

struct ValidationCheck: Codable {
    let identifier: String?
    let predicate: String?
    let property: String
    let expected: Bool
}

struct ValidateRequest: Codable {
    let validations: [ValidationCheck]
}

struct ValidationResult: Codable {
    let passed: Bool
    let actual: Bool?
    let expected: Bool
}

struct ValidateResponse: Codable {
    let results: [ValidationResult]
    let allPassed: Bool
}

// MARK: - Configuration

struct RunnerConfig: Codable {
    let defaultTimeout: Double
    let errorVerbosity: String
    let maxConcurrentRequests: Int
}

struct ConfigResponse: Codable {
    let config: RunnerConfig
    let timestamp: String
}

struct SetTimeoutRequest: Codable {
    let timeout: Double
}

struct ConfigurationResponse: Codable {
    let port: Int
    let defaultTimeout: Double
    let errorVerbosity: String
    let maxConcurrentRequests: Int
}

struct UpdateConfigRequest: Codable {
    let defaultTimeout: Double?
    let errorVerbosity: String?
}

struct UpdateConfigResponse: Codable {
    let config: RunnerConfig
    let updated: [String]
    let timestamp: String
}

// MARK: - Alerts

struct AlertInfo: Codable {
    let title: String?
    let message: String?
    let buttons: [String]
}

struct AlertsResponse: Codable {
    let alerts: [AlertInfo]
}

struct Alert: Codable {
    let title: String?
    let message: String?
    let buttons: [String]
    let type: String
}

struct DetectAlertResponse: Codable {
    let alerts: [Alert]
}

struct DismissAlertRequest: Codable {
    let buttonLabel: String
}

struct DismissAlertResponse: Codable {
    let success: Bool
}

// MARK: - Generic Response Wrapper (for JSON output)

struct APIResponse<T: Codable>: Codable {
    let success: Bool
    let data: T?
    let error: APIErrorDetail?
    let executionTime: Double?
}

struct APIErrorDetail: Codable {
    let code: String
    let message: String
    let suggestion: String?
}
