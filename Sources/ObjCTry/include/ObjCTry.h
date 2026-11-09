#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs the block and catches an Objective-C exception (AVAudioEngine throws them, e.g. on a format mismatch).
/// Swift cannot catch these; one that unwinds through Swift code leaves the process broken and it crashes later.
/// Returns the exception's reason, or nil if the block finished.
NSString *_Nullable HiveTry(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
