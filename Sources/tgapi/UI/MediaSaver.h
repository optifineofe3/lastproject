#import <UIKit/UIKit.h>

@interface MediaSaver : NSObject

+ (instancetype)shared;
+ (void)attachToController:(UIViewController *)controller;
+ (void)saveMediaFromController:(UIViewController *)controller;
+ (void)showToast:(NSString *)message success:(BOOL)success;

@end
