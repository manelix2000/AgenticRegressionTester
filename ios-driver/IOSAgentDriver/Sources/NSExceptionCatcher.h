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

NS_ASSUME_NONNULL_END
