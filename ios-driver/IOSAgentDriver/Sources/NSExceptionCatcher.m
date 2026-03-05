#import "NSExceptionCatcher.h"

@implementation XCUIElementQuery (SafeMatching)

- (nullable XCUIElementQuery *)safeMatchingPredicate:(NSPredicate *)predicate
                                          exception:(NSException **)outException {
    @try {
        return [self matchingPredicate:predicate];
    } @catch (NSException *exception) {
        NSLog(@"[IOSAgentDriver][NSExceptionCatcher] safeMatchingPredicate caught %@: %@. Predicate: %@",
              exception.name, exception.reason, predicate);
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
    } @catch (NSException *exception) {
        NSLog(@"[IOSAgentDriver][NSExceptionCatcher] safeIsHittable caught %@: %@. Element: %@",
              exception.name, exception.reason, self.description);
        return NO;
    }
}

@end

@implementation XCUIElementQuery (SafeEnumeration)

- (NSArray<XCUIElement *> *)safeAllElementsBoundByIndex {
    @try {
        return self.allElementsBoundByIndex;
    } @catch (NSException *exception) {
        NSLog(@"[IOSAgentDriver][NSExceptionCatcher] safeAllElementsBoundByIndex caught %@: %@. Query: %@",
              exception.name, exception.reason, self.description);
        return @[];
    }
}

- (XCUIElementQuery *)safeMatchingIdentifier:(NSString *)identifier {
    @try {
        return [self matchingIdentifier:identifier];
    } @catch (NSException *exception) {
        NSLog(@"[IOSAgentDriver][NSExceptionCatcher] safeMatching(identifier:%@) caught %@: %@. Query: %@",
              identifier, exception.name, exception.reason, self.description);
        // Return a query that always resolves to zero elements
        return [self matchingPredicate:[NSPredicate predicateWithValue:NO]];
    }
}

@end

@implementation XCUIElement (SafeScreenshot)

- (nullable XCUIScreenshot *)safeScreenshot {
    @try {
        return [self screenshot];
    } @catch (NSException *exception) {
        NSLog(@"[IOSAgentDriver][NSExceptionCatcher] safeScreenshot caught %@: %@. Element: %@",
              exception.name, exception.reason, self.description);
        return nil;
    }
}

@end
