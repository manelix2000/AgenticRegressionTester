#import "NSExceptionCatcher.h"

@implementation XCUIElementQuery (SafeMatching)

- (nullable XCUIElementQuery *)safeMatchingPredicate:(NSPredicate *)predicate
                                          exception:(NSException **)outException {
    @try {
        return [self matchingPredicate:predicate];
    } @catch (NSException *exception) {
        if (outException) {
            *outException = exception;
        }
        return nil;
    }
}

@end

@implementation XCUIElement (SafeHittability)

- (BOOL)safeIsHittable {
    @try {
        return self.isHittable;
    } @catch (NSException *) {
        return NO;
    }
}

@end
