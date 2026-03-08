import Vision
import CoreImage
import UIKit

// MARK: - OCR Models

/// Bounding box in pixel coordinates (origin at top-left)
struct BoundingBox: Codable, Sendable {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

/// A single recognized word
struct OCRWord: Codable, Sendable {
    let text: String
    let confidence: Float
    let box: BoundingBox
}

/// A line of recognized text containing words
struct OCRLine: Codable, Sendable {
    let text: String
    let confidence: Float
    let box: BoundingBox
    let words: [OCRWord]
}

/// A block of text lines sharing spatial proximity
struct OCRBlock: Codable, Sendable {
    let box: BoundingBox
    let lines: [OCRLine]
}

/// Full OCR result for a captured screen
struct OCRDocument: Codable, Sendable {
    let imageWidth: Int
    let imageHeight: Int
    let blocks: [OCRBlock]
}

// MARK: - OCR Service

/// Service for performing OCR on the current screen using Vision and CoreImage
enum OcrService {

    // MARK: - Public API

    /// Captures the current full-screen screenshot and runs OCR on it.
    /// - Returns: An `OCRDocument` with all recognized text blocks, lines and words.
    /// - Throws: `OcrError` if the screenshot cannot be processed or recognition fails.
    @MainActor
    static func recognize() async throws -> OCRDocument {
        let pngData = ScreenshotService.captureFullScreen()

        guard let uiImage = UIImage(data: pngData),
              let cgImage = uiImage.cgImage else {
            throw OcrError.invalidScreenshot
        }

        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        let blocks = try await performRecognition(on: cgImage,
                                                  imageWidth: imageWidth,
                                                  imageHeight: imageHeight)

        return OCRDocument(imageWidth: imageWidth, imageHeight: imageHeight, blocks: blocks)
    }

    // MARK: - Private Helpers

    /// Runs `VNRecognizeTextRequest` on the given `CGImage` and maps results to `OCRBlock`s.
    private static func performRecognition(
        on cgImage: CGImage,
        imageWidth: Int,
        imageHeight: Int
    ) async throws -> [OCRBlock] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OcrError.recognitionFailed(error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let blocks = Self.mapObservationsToBlocks(observations,
                                                          imageWidth: imageWidth,
                                                          imageHeight: imageHeight)
                continuation.resume(returning: blocks)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OcrError.recognitionFailed(error))
            }
        }
    }

    /// Maps Vision observations into `OCRBlock` instances.
    /// Each observation becomes one block with one line (Vision does not natively expose block grouping).
    private static func mapObservationsToBlocks(
        _ observations: [VNRecognizedTextObservation],
        imageWidth: Int,
        imageHeight: Int
    ) -> [OCRBlock] {
        observations.compactMap { observation -> OCRBlock? in
            let candidates = observation.topCandidates(10)
            guard let topCandidate = candidates.first else { return nil }

            let lineBox = pixelBox(observation.boundingBox,
                                   imageWidth: imageWidth,
                                   imageHeight: imageHeight)

            let words = buildWords(from: topCandidate,
                                   observation: observation,
                                   imageWidth: imageWidth,
                                   imageHeight: imageHeight)

            let line = OCRLine(
                text: topCandidate.string,
                confidence: topCandidate.confidence,
                box: lineBox,
                words: words
            )

            return OCRBlock(box: lineBox, lines: [line])
        }
    }

    /// Builds `OCRWord` instances by splitting the candidate string and approximating word boxes.
    private static func buildWords(
        from candidate: VNRecognizedText,
        observation: VNRecognizedTextObservation,
        imageWidth: Int,
        imageHeight: Int
    ) -> [OCRWord] {
        let fullText = candidate.string
        let wordStrings = fullText.split(separator: " ").map(String.init)

        return wordStrings.compactMap { word -> OCRWord? in
            guard let range = fullText.range(of: word) else { return nil }

            // Try to get the bounding box for this specific word's range
            let wordBox: BoundingBox
            if let wordObservationBox = try? candidate.boundingBox(for: range) {
                wordBox = pixelBox(wordObservationBox.boundingBox,
                                   imageWidth: imageWidth,
                                   imageHeight: imageHeight)
            } else {
                // Fall back to line box
                wordBox = pixelBox(observation.boundingBox,
                                   imageWidth: imageWidth,
                                   imageHeight: imageHeight)
            }

            return OCRWord(text: word, confidence: candidate.confidence, box: wordBox)
        }
    }

    /// Converts a Vision normalized bounding box (origin at bottom-left, y grows upward)
    /// into pixel coordinates with origin at top-left.
    private static func pixelBox(_ rect: CGRect, imageWidth: Int, imageHeight: Int) -> BoundingBox {
        let x = Int(rect.origin.x * CGFloat(imageWidth))
        let y = Int((1 - rect.origin.y - rect.height) * CGFloat(imageHeight))
        let w = Int(rect.width * CGFloat(imageWidth))
        let h = Int(rect.height * CGFloat(imageHeight))
        return BoundingBox(x: x, y: y, width: w, height: h)
    }
}

// MARK: - OCR Errors

enum OcrError: LocalizedError {
    case invalidScreenshot
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidScreenshot:
            return "Failed to decode screenshot for OCR processing."
        case .recognitionFailed(let underlying):
            return "Vision OCR recognition failed: \(underlying.localizedDescription)"
        }
    }
}
