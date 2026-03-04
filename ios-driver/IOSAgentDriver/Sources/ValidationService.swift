import XCTest

/// Service for validating element properties (synchronous)
enum ValidationService {
    
    // MARK: - Validation Methods
    
    /// Validates multiple element properties without throwing errors
    /// - Parameters:
    ///   - app: The application instance
    ///   - validations: Array of validation rules
    /// - Returns: Array of validation results
    @MainActor
    static func validate(
        in app: XCUIApplication,
        validations: [ValidationRule]
    ) -> [ValidationResult] {
        var results: [ValidationResult] = []
        
        for validation in validations {
            let result = validateSingle(in: app, validation: validation)
            results.append(result)
        }
        
        return results
    }
    
    /// Validates a single element property
    /// - Parameters:
    ///   - app: The application instance
    ///   - validation: Validation rule
    /// - Returns: Validation result
    @MainActor
    private static func validateSingle(
        in app: XCUIApplication,
        validation: ValidationRule
    ) -> ValidationResult {
        // Parse property enum
        guard let property = ValidationProperty(rawValue: validation.property) else {
            return ValidationResult(
                property: validation.property,
                expected: validation.expectedValue,
                actual: "error",
                passed: false,
                message: "Invalid property type: \(validation.property)"
            )
        }
        
        do {
            // Find elements using synchronous ElementQuery
            let nodes = try ElementQuery.findElements(
                in: app,
                identifier: validation.identifier,
                label: validation.label,
                predicate: validation.predicate,
                timeout: validation.timeout ?? 5,
                waitStrategy: .wait
            )
            
            // Validate based on property type
            switch property {
            case .exists:
                return validateExists(
                    nodes: nodes,
                    expected: validation.expectedValue
                )
                
            case .count:
                return validateCount(
                    nodes: nodes,
                    expected: validation.expectedValue
                )
                
            case .isEnabled:
                return validateBooleanProperty(
                    nodes: nodes,
                    property: "isEnabled",
                    expected: validation.expectedValue,
                    getValue: { $0.isEnabled }
                )
                
            case .isVisible:
                return validateBooleanProperty(
                    nodes: nodes,
                    property: "isVisible",
                    expected: validation.expectedValue,
                    getValue: { $0.isVisible }
                )
                
            case .label:
                return validateStringProperty(
                    nodes: nodes,
                    property: "label",
                    expected: validation.expectedValue,
                    getValue: { $0.label }
                )
                
            case .value:
                return validateStringProperty(
                    nodes: nodes,
                    property: "value",
                    expected: validation.expectedValue,
                    getValue: { $0.value }
                )
            }
        } catch {
            // Element not found or other error
            return ValidationResult(
                property: validation.property,
                expected: validation.expectedValue,
                actual: "error",
                passed: false,
                message: "Failed to find element: \(error.localizedDescription)"
            )
        }
    }
    
    /// Asserts a single property (throws on failure)
    /// - Parameters:
    ///   - app: The application instance
    ///   - assertion: Assertion rule
    /// - Throws: ValidationError if assertion fails
    @MainActor
    static func assert(
        in app: XCUIApplication,
        assertion: ValidationRule
    ) throws {
        let result = validateSingle(in: app, validation: assertion)
        
        if !result.passed {
            throw ValidationError.assertionFailed(result: result)
        }
    }
    
    // MARK: - Property Validators
    
    private static func validateExists(
        nodes: [UINode],
        expected: String
    ) -> ValidationResult {
        let exists = !nodes.isEmpty
        let expectedBool = expected.lowercased() == "true"
        let passed = exists == expectedBool
        
        return ValidationResult(
            property: "exists",
            expected: expected,
            actual: String(exists),
            passed: passed,
            message: passed ? "Element existence matches expected" : "Element existence does not match"
        )
    }
    
    private static func validateCount(
        nodes: [UINode],
        expected: String
    ) -> ValidationResult {
        let actualCount = nodes.count
        
        // Support different formats: "5", ">3", ">=2", "<10"
        let passed: Bool
        let message: String
        
        if expected.hasPrefix(">=") {
            let threshold = Int(expected.dropFirst(2)) ?? 0
            passed = actualCount >= threshold
            message = passed ? "Count \(actualCount) >= \(threshold)" : "Count \(actualCount) < \(threshold)"
        } else if expected.hasPrefix(">") {
            let threshold = Int(expected.dropFirst()) ?? 0
            passed = actualCount > threshold
            message = passed ? "Count \(actualCount) > \(threshold)" : "Count \(actualCount) <= \(threshold)"
        } else if expected.hasPrefix("<=") {
            let threshold = Int(expected.dropFirst(2)) ?? 0
            passed = actualCount <= threshold
            message = passed ? "Count \(actualCount) <= \(threshold)" : "Count \(actualCount) > \(threshold)"
        } else if expected.hasPrefix("<") {
            let threshold = Int(expected.dropFirst()) ?? 0
            passed = actualCount < threshold
            message = passed ? "Count \(actualCount) < \(threshold)" : "Count \(actualCount) >= \(threshold)"
        } else {
            let expectedCount = Int(expected) ?? 0
            passed = actualCount == expectedCount
            message = passed ? "Count matches expected" : "Count \(actualCount) != \(expectedCount)"
        }
        
        return ValidationResult(
            property: "count",
            expected: expected,
            actual: String(actualCount),
            passed: passed,
            message: message
        )
    }
    
    private static func validateBooleanProperty(
        nodes: [UINode],
        property: String,
        expected: String,
        getValue: (UINode) -> Bool
    ) -> ValidationResult {
        guard let firstNode = nodes.first else {
            return ValidationResult(
                property: property,
                expected: expected,
                actual: "null",
                passed: false,
                message: "No element found to validate"
            )
        }
        
        let actualValue = getValue(firstNode)
        let expectedBool = expected.lowercased() == "true"
        let passed = actualValue == expectedBool
        
        return ValidationResult(
            property: property,
            expected: expected,
            actual: String(actualValue),
            passed: passed,
            message: passed ? "\(property) matches expected" : "\(property) does not match"
        )
    }
    
    private static func validateStringProperty(
        nodes: [UINode],
        property: String,
        expected: String,
        getValue: (UINode) -> String?
    ) -> ValidationResult {
        guard let firstNode = nodes.first else {
            return ValidationResult(
                property: property,
                expected: expected,
                actual: "null",
                passed: false,
                message: "No element found to validate"
            )
        }
        
        let actualValue = getValue(firstNode) ?? ""
        
        // Support exact match and contains
        let passed: Bool
        let message: String
        
        if expected.hasPrefix("contains:") {
            let searchText = String(expected.dropFirst(9))
            passed = actualValue.contains(searchText)
            message = passed ? "\(property) contains '\(searchText)'" : "\(property) does not contain '\(searchText)'"
        } else {
            passed = actualValue == expected
            message = passed ? "\(property) matches expected" : "\(property) '\(actualValue)' != '\(expected)'"
        }
        
        return ValidationResult(
            property: property,
            expected: expected,
            actual: actualValue,
            passed: passed,
            message: message
        )
    }
}

// MARK: - Validation Errors

enum ValidationError: LocalizedError {
    case assertionFailed(result: ValidationResult)
    
    var errorDescription: String? {
        switch self {
        case .assertionFailed(let result):
            return "Assertion failed: \(result.message). Expected '\(result.expected)', got '\(result.actual)'"
        }
    }
}
