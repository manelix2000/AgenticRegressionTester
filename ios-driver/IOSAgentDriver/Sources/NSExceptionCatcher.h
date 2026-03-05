#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

/// An XCUIElementQuery category that wraps predicate matching in an ObjC
/// @try/@catch block, since Swift cannot catch NSExceptions natively.
@interface XCUIElementQuery (SafeMatching)

/// Matches elements using the given predicate, catching any NSException
/// thrown during XCTest's predicate validation.
/// - Returns: The filtered query, or nil if the predicate was rejected.
/// - Parameter outException: Set to the caught exception on failure.
- (nullable XCUIElementQuery *)safeMatchingPredicate:(NSPredicate *)predicate
                                          exception:(NSException *_Nullable *_Nullable)outException
    NS_SWIFT_NAME(safeMatching(_:exception:));
@end

/// An XCUIElement category that wraps isHittable access in an ObjC
/// @try/@catch block. Elements with invalid frames throw
/// NSInternalInconsistencyException when isHittable is evaluated — Swift
/// cannot catch ObjC exceptions, so we intercept them here.
@interface XCUIElement (SafeHittability)

/// Safely checks whether the element is hittable, catching any
/// NSInternalInconsistencyException thrown for elements with invalid frames.
/// - Returns: YES if the element is hittable, NO if an exception occurred or
///            the element is not hittable.
- (BOOL)safeIsHittable NS_SWIFT_NAME(safeIsHittable());

@end

/// An XCUIElementQuery category that wraps allElementsBoundByIndex in an ObjC
/// @try/@catch block. Enumerating children of certain elements (e.g. ScrollView)
/// can trigger NSInternalInconsistencyException inside XCTest's snapshot machinery —
/// Swift cannot catch ObjC exceptions, so we intercept them here and return an
/// empty array, preventing nested-exception crashes in the test runner.
@interface XCUIElementQuery (SafeEnumeration)

/// Safely enumerates all elements matched by this query, catching any
/// NSInternalInconsistencyException thrown by XCTest's snapshot mechanism.
/// - Returns: The matched element array, or an empty array if an exception occurred.
- (NSArray<XCUIElement *> *)safeAllElementsBoundByIndex NS_SWIFT_NAME(safeAllElementsBoundByIndex());

/// Safely filters this query by accessibility identifier, catching any
/// NSInternalInconsistencyException thrown by XCTest's predicate engine.
/// Falls back to returning an empty query on failure.
/// - Parameter identifier: The accessibility identifier to match.
/// - Returns: A filtered query, or an empty query if an exception occurred.
- (XCUIElementQuery *)safeMatchingIdentifier:(NSString *)identifier NS_SWIFT_NAME(safeMatching(identifier:));

@end

/// An XCUIElement category that wraps screenshot() in an ObjC @try/@catch block.
/// Capturing a screenshot of an element whose window has been deallocated throws
/// NSInternalInconsistencyException — Swift cannot catch ObjC exceptions, so we
/// intercept it here and return nil instead of crashing the test runner.
@interface XCUIElement (SafeScreenshot)

/// Safely captures a screenshot of this element, catching any
/// NSInternalInconsistencyException thrown when the element has no window.
/// - Returns: A screenshot, or nil if an exception occurred.
- (nullable XCUIScreenshot *)safeScreenshot NS_SWIFT_NAME(safeScreenshot());

@end

NS_ASSUME_NONNULL_END
