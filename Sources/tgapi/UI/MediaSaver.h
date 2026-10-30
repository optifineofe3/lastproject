#import <UIKit/UIKit.h>

@interface MediaSaver : NSObject

+ (instancetype)shared;
+ (void)attachToController:(UIViewController *)controller;
+ (void)detachFromController:(UIViewController *)controller animated:(BOOL)animated;
+ (void)attachInstantVideoButtonToNode:(id)node;
+ (void)saveMediaFromController:(UIViewController *)controller;
+ (void)saveVideoToPhotos:(NSString *)videoPath;
+ (void)saveImageToPhotos:(UIImage *)image;
+ (void)showToast:(NSString *)message success:(BOOL)success;
+ (NSString *)ensureVideoExtension:(NSString *)path;
+ (void)noteOpenedCandidatePath:(NSString *)path;
+ (NSString *)lastOpenedVideoPath;

- (void)handleButtonTap:(id)sender;
- (void)handleInstantVideoDoubleTap:(UITapGestureRecognizer *)gesture;
- (void)handleInstantVideoButtonTap:(id)sender;

@end
