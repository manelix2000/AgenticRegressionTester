import XCTest
import UIKit

/// Service for capturing and comparing screenshots
enum ScreenshotService {
    
    // MARK: - Screenshot Capture
    
    /// Captures a full screen screenshot
    /// - Returns: PNG image data
    @MainActor
    static func captureFullScreen() -> Data {
        let screenshot = XCUIScreen.main.screenshot()
        return screenshot.pngRepresentation
    }
    
    /// Captures a screenshot of a specific element
    /// - Parameters:
    ///   - app: The application instance
    ///   - identifier: Optional accessibility identifier
    ///   - label: Optional accessibility label
    ///   - predicate: Optional NSPredicate string
    ///   - timeout: Timeout for finding element
    ///   - waitStrategy: Wait strategy for element lookup
    /// - Returns: Tuple of PNG data and the UINode representation
    /// - Throws: QueryError if element not found
    @MainActor
    static func captureElement(
        in app: XCUIApplication,
        identifier: String? = nil,
        label: String? = nil,
        predicate: String? = nil,
        timeout: TimeInterval = 5,
        waitStrategy: FindElementsRequest.WaitStrategy = .wait
    ) throws -> (data: Data, node: UINode) {
        let nodes = try ElementQuery.findElements(
            in: app,
            identifier: identifier,
            label: label,
            predicate: predicate,
            timeout: timeout,
            waitStrategy: waitStrategy
        )
        
        guard let firstNode = nodes.first else {
            throw QueryError.elementNotFound(
                identifier: identifier,
                predicate: predicate,
                timeout: timeout
            )
        }
        
        // Get the XCUIElement to capture screenshot
        let element: XCUIElement
        if let id = identifier {
            element = app.descendants(matching: .any).safeMatching(identifier: id).firstMatch
        } else if let labelText = label {
            let labelPredicate = NSPredicate(format: "label == %@", labelText)
            element = app.descendants(matching: .any).matching(labelPredicate).firstMatch
        } else if let predicateString = predicate {
            let pred = NSPredicate(format: predicateString)
            element = app.descendants(matching: .any).matching(pred).firstMatch
        } else {
            throw QueryError.missingCriteria
        }
        
        guard let screenshot = element.safeScreenshot() else {
            throw QueryError.elementNotFound(
                identifier: identifier,
                predicate: predicate,
                timeout: timeout
            )
        }
        return (screenshot.pngRepresentation, firstNode)
    }
    
    // MARK: - Image Encoding
    
    /// Converts PNG data to base64 string
    /// - Parameter pngData: PNG image data
    /// - Returns: Base64 encoded string
    static func pngToBase64(_ pngData: Data) -> String {
        return pngData.base64EncodedString()
    }
    
    /// Converts base64 string to PNG data
    /// - Parameter base64String: Base64 encoded string
    /// - Returns: PNG data, or nil if invalid
    static func base64ToPng(_ base64String: String) -> Data? {
        return Data(base64Encoded: base64String)
    }
    
    // MARK: - Image Comparison
    
    /// Comparison result containing match status and metrics
    struct ComparisonResult {
        let match: Bool
        let similarity: Double  // 0.0 to 1.0
        let differenceCount: Int
        let totalPixels: Int
        let diffImageBase64: String?
    }
    
    /// Compares two screenshots and generates a diff image
    /// - Parameters:
    ///   - referenceBase64: Base64 encoded reference image
    ///   - currentPngData: Current screenshot PNG data
    ///   - threshold: Similarity threshold (0.0 to 1.0, default 0.95)
    /// - Returns: Comparison result with metrics and diff image
    /// - Throws: ScreenshotError if images cannot be compared
    static func compareScreenshots(
        referenceBase64: String,
        currentPngData: Data,
        threshold: Double = 0.95
    ) throws -> ComparisonResult {
        // Decode reference image
        guard let referenceData = base64ToPng(referenceBase64),
              let referenceImage = UIImage(data: referenceData),
              let referenceCGImage = referenceImage.cgImage else {
            throw ScreenshotError.invalidReferenceImage
        }
        
        // Decode current image
        guard let currentImage = UIImage(data: currentPngData),
              let currentCGImage = currentImage.cgImage else {
            throw ScreenshotError.invalidCurrentImage
        }
        
        // Check dimensions match
        guard referenceCGImage.width == currentCGImage.width,
              referenceCGImage.height == currentCGImage.height else {
            throw ScreenshotError.dimensionMismatch(
                reference: CGSize(width: referenceCGImage.width, height: referenceCGImage.height),
                current: CGSize(width: currentCGImage.width, height: currentCGImage.height)
            )
        }
        
        let width = referenceCGImage.width
        let height = referenceCGImage.height
        let totalPixels = width * height
        
        // Get pixel data
        guard let referencePixels = getPixelData(from: referenceCGImage),
              let currentPixels = getPixelData(from: currentCGImage) else {
            throw ScreenshotError.pixelDataExtractionFailed
        }
        
        // Compare pixels and build diff image
        var differenceCount = 0
        var diffPixels = [UInt8](repeating: 0, count: totalPixels * 4)
        
        for i in 0..<totalPixels {
            let pixelIndex = i * 4
            let rRef = referencePixels[pixelIndex]
            let gRef = referencePixels[pixelIndex + 1]
            let bRef = referencePixels[pixelIndex + 2]
            let aRef = referencePixels[pixelIndex + 3]
            
            let rCur = currentPixels[pixelIndex]
            let gCur = currentPixels[pixelIndex + 1]
            let bCur = currentPixels[pixelIndex + 2]
            let aCur = currentPixels[pixelIndex + 3]
            
            // Check if pixels are different (with small tolerance)
            let tolerance: UInt8 = 5
            let isDifferent = abs(Int(rRef) - Int(rCur)) > tolerance ||
                            abs(Int(gRef) - Int(gCur)) > tolerance ||
                            abs(Int(bRef) - Int(bCur)) > tolerance ||
                            abs(Int(aRef) - Int(aCur)) > tolerance
            
            if isDifferent {
                differenceCount += 1
                // Highlight difference in red
                diffPixels[pixelIndex] = 255     // R
                diffPixels[pixelIndex + 1] = 0   // G
                diffPixels[pixelIndex + 2] = 0   // B
                diffPixels[pixelIndex + 3] = 255 // A
            } else {
                // Keep original pixel (dimmed)
                diffPixels[pixelIndex] = rCur / 2
                diffPixels[pixelIndex + 1] = gCur / 2
                diffPixels[pixelIndex + 2] = bCur / 2
                diffPixels[pixelIndex + 3] = aCur
            }
        }
        
        // Calculate similarity
        let similarity = 1.0 - (Double(differenceCount) / Double(totalPixels))
        let match = similarity >= threshold
        
        // Generate diff image
        let diffImageBase64: String?
        if differenceCount > 0 {
            if let diffImage = createImage(from: diffPixels, width: width, height: height),
               let diffPngData = diffImage.pngData() {
                diffImageBase64 = pngToBase64(diffPngData)
            } else {
                diffImageBase64 = nil
            }
        } else {
            diffImageBase64 = nil // No differences
        }
        
        return ComparisonResult(
            match: match,
            similarity: similarity,
            differenceCount: differenceCount,
            totalPixels: totalPixels,
            diffImageBase64: diffImageBase64
        )
    }
    
    // MARK: - Private Helpers
    
    /// Extracts pixel data from CGImage
    private static func getPixelData(from cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        guard let ctx = context else { return nil }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return pixelData
    }
    
    /// Creates UIImage from pixel data
    private static func createImage(from pixels: [UInt8], width: Int, height: Int) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelsCopy = pixels
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: &pixelsCopy,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Screenshot Errors

enum ScreenshotError: LocalizedError {
    case invalidReferenceImage
    case invalidCurrentImage
    case dimensionMismatch(reference: CGSize, current: CGSize)
    case pixelDataExtractionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidReferenceImage:
            return "Invalid reference image. Could not decode base64 PNG data."
        case .invalidCurrentImage:
            return "Invalid current image. Could not decode PNG data."
        case .dimensionMismatch(let reference, let current):
            return "Image dimensions do not match. Reference: \(reference), Current: \(current)"
        case .pixelDataExtractionFailed:
            return "Failed to extract pixel data from images."
        }
    }
}
