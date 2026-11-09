#import "ObjCTry.h"

NSString *_Nullable HiveTry(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *e) {
        return [NSString stringWithFormat:@"%@: %@", e.name, e.reason ?: @"no reason"];
    }
}
