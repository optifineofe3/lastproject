#import <UIKit/UIKit.h>

@interface MediaSaver : NSObject <UIGestureRecognizerDelegate>

+ (void)showEditHistoryForNode:(id)node bFrame:(CGRect)bFrame msgId:(NSNumber *)msgId;
- (void)dismissEditHistoryOverlay;
- (void)handleBubbleTap:(UITapGestureRecognizer *)gesture;

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
+ (NSString *)currentActivePlayingVideoPath;
+ (NSString *)findVideoPathForTarget:(id)target;
+ (NSString *)findVideoPathForTarget:(id)target controller:(UIViewController *)controller;
+ (BOOL)isPathVideoPlayable:(NSString *)path;
+ (void)startDownloadingAndSaveStoryVideoForTarget:(id)target controller:(UIViewController *)controller;

- (void)handleButtonTap:(id)sender;
- (void)handleInstantVideoDoubleTap:(UITapGestureRecognizer *)gesture;
- (void)handleInstantVideoButtonTap:(id)sender;
- (void)handleEditBadgeTap:(UITapGestureRecognizer *)gesture;

@end
