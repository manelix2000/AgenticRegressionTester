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

NS_ASSUME_NONNULL_END
