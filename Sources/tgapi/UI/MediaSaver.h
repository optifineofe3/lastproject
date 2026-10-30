#import <UIKit/UIKit.h>

@interface MediaSaver : NSObject

+ (instancetype)shared;
+ (void)attachToController:(UIViewController *)controller;
+ (void)saveMediaFromController:(UIViewController *)controller;
+ (void)showToast:(NSString *)message success:(BOOL)success;
+ (NSString *)findNewestVideoInDirectory:(NSString *)dir;
+ (NSString *)ensureVideoExtension:(NSString *)path;

- (void)handleButtonTap:(id)sender;
- (void)handleInstantVideoDoubleTap:(UITapGestureRecognizer *)gesture;

@end
