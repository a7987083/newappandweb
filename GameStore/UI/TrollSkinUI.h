#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Embeddable UIKit demo interface. No UIApplicationMain or app delegate is included.
/// The returned view controller owns its four tabs and placeholder interactions.
@interface TrollSkinUI : NSObject
+ (UIViewController *)createRootViewController;
@end

NS_ASSUME_NONNULL_END
