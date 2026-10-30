#import "MediaSaver.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

@interface MediaSaverButton : UIButton
@property (nonatomic, weak) UIViewController *targetController;
@end

@implementation MediaSaverButton
@end

@implementation MediaSaver

+ (instancetype)shared {
    static MediaSaver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MediaSaver alloc] init];
    });
    return instance;
}

static UIImage *downloadIconImage(void) {
    static UIImage *icon = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
            icon = [UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:config];
            if (icon) {
                icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                return;
            }
        }
        
        CGSize size = CGSizeMake(24, 24);
        UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
        
        [[UIColor whiteColor] setStroke];
        
        UIBezierPath *stem = [UIBezierPath bezierPath];
        [stem moveToPoint:CGPointMake(12, 3)];
        [stem addLineToPoint:CGPointMake(12, 14)];
        stem.lineWidth = 2.5;
        stem.lineCapStyle = kCGLineCapRound;
        [stem stroke];
        
        UIBezierPath *head = [UIBezierPath bezierPath];
        [head moveToPoint:CGPointMake(7, 10)];
        [head addLineToPoint:CGPointMake(12, 15)];
        [head addLineToPoint:CGPointMake(17, 10)];
        head.lineWidth = 2.5;
        head.lineCapStyle = kCGLineCapRound;
        head.lineJoinStyle = kCGLineJoinRound;
        [head stroke];
        
        UIBezierPath *tray = [UIBezierPath bezierPath];
        [tray moveToPoint:CGPointMake(5, 20)];
        [tray addLineToPoint:CGPointMake(19, 20)];
        tray.lineWidth = 2.5;
        tray.lineCapStyle = kCGLineCapRound;
        [tray stroke];
        
        icon = [UIGraphicsGetImageFromCurrentImageContext() imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIGraphicsEndImageContext();
    });
    return icon;
}

+ (void)attachToController:(UIViewController *)controller {
    if (!controller || !controller.isViewLoaded) return;
    
    NSString *className = NSStringFromClass([controller class]);
    BOOL isGallery = [className containsString:@"GalleryController"];
    BOOL isSecret = [className containsString:@"SecretMediaPreviewController"];
    
    if (!isGallery && !isSecret) return;
    
    UIView *view = controller.view;
    if (!view) return;
    
    // Avoid duplicate buttons
    if ([view viewWithTag:998811]) return;
    
    MediaSaverButton *btn = [MediaSaverButton buttonWithType:UIButtonTypeSystem];
    btn.tag = 998811;
    btn.targetController = controller;
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    btn.tintColor = [UIColor whiteColor];
    btn.layer.cornerRadius = 21;
    btn.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25].CGColor;
    btn.layer.borderWidth = 1.0;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.4;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 4.0;
    btn.layer.zPosition = 9999;
    btn.clipsToBounds = NO;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    
    [btn setImage:downloadIconImage() forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(handleButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    
    [view addSubview:btn];
    
    if (isSecret) {
        // Place in top-left so it does not collide with the flame timer in top-right
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:12],
            [btn.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:16],
            [btn.widthAnchor constraintEqualToConstant:42],
            [btn.heightAnchor constraintEqualToConstant:42]
        ]];
    } else {
        // Place floating in bottom-right, easy to reach with thumb
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-60],
            [btn.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [btn.widthAnchor constraintEqualToConstant:42],
            [btn.heightAnchor constraintEqualToConstant:42]
        ]];
    }
    
    // Also add long-press gesture to the view for convenience
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.5;
    [view addGestureRecognizer:lp];
}

+ (void)handleButtonTap:(MediaSaverButton *)sender {
    if (sender.targetController) {
        [self saveMediaFromController:sender.targetController];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    UIResponder *r = gesture.view;
    while (r && ![r isKindOfClass:[UIViewController class]]) {
        r = r.nextResponder;
    }
    UIViewController *vc = (UIViewController *)r;
    if (!vc) return;
    
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
    [feedback impactOccurred];
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Media Options" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Save to Camera Roll" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [MediaSaver saveMediaFromController:vc];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [vc presentViewController:sheet animated:YES completion:nil];
}

static void scanLayersRecursively(CALayer *layer, void (^foundCallback)(NSString *path)) {
    if (!layer) return;
    if ([layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayer *player = [(AVPlayerLayer *)layer player];
        AVPlayerItem *item = player.currentItem;
        if ([item.asset isKindOfClass:[AVURLAsset class]]) {
            NSURL *url = [(AVURLAsset *)item.asset URL];
            if (url && url.isFileURL && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
                foundCallback(url.path);
                return;
            }
        }
    }
    for (CALayer *sub in layer.sublayers) {
        scanLayersRecursively(sub, foundCallback);
    }
}

static void scanViewsRecursively(UIView *v, void (^checkImage)(UIImage *img), void (^checkLayerContents)(CGImageRef cg)) {
    if (!v) return;
    
    // 1. Check CALayer contents
    id contents = v.layer.contents;
    if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
        checkLayerContents((__bridge CGImageRef)contents);
    }
    
    // 2. Check UIImageView
    if ([v isKindOfClass:[UIImageView class]]) {
        checkImage([(UIImageView *)v image]);
    }
    
    // 3. Check AsyncDisplayKit node
    @try {
        id node = [v valueForKey:@"asyncdisplaykit_node"];
        if (node && [node respondsToSelector:@selector(image)]) {
            checkImage([node performSelector:@selector(image)]);
        }
    } @catch (...) {}
    
    for (UIView *sub in v.subviews) {
        scanViewsRecursively(sub, checkImage, checkLayerContents);
    }
}

+ (NSString *)findVideoPathInController:(UIViewController *)controller {
    if (!controller) return nil;
    
    // 1. Inspect controller's ivars for TempBoxFile or path
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList([controller class], &count);
    if (ivars) {
        for (unsigned int i = 0; i < count; i++) {
            const char *name = ivar_getName(ivars[i]);
            if (!name) continue;
            id val = object_getIvar(controller, ivars[i]);
            if (!val) continue;
            
            if ([val isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)val;
                if ([str hasSuffix:@".mp4"] || [str hasSuffix:@".mov"]) {
                    if ([[NSFileManager defaultManager] fileExistsAtPath:str]) {
                        free(ivars);
                        return str;
                    }
                }
            }
            @try {
                id pathObj = [val valueForKey:@"path"];
                if ([pathObj isKindOfClass:[NSString class]]) {
                    NSString *p = (NSString *)pathObj;
                    if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                        free(ivars);
                        return p;
                    }
                }
            } @catch (...) {}
        }
        free(ivars);
    }
    
    // 2. Scan view layers for AVPlayerLayer
    __block NSString *foundPath = nil;
    if (controller.isViewLoaded && controller.view.layer) {
        scanLayersRecursively(controller.view.layer, ^(NSString *path) {
            foundPath = path;
        });
    }
    if (foundPath) return foundPath;
    
    // 3. Scan temp directory for newly created/modified video file in last 3 minutes
    NSString *tmpDir = NSTemporaryDirectory();
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpDir error:nil];
    NSDate *now = [NSDate date];
    NSString *newestFile = nil;
    NSDate *newestDate = [NSDate distantPast];
    
    for (NSString *file in files) {
        if ([file hasSuffix:@".mp4"] || [file hasSuffix:@".mov"]) {
            NSString *fullPath = [tmpDir stringByAppendingPathComponent:file];
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil];
            NSDate *mod = attrs[NSFileModificationDate];
            if (mod && [now timeIntervalSinceDate:mod] < 180.0) {
                if ([mod compare:newestDate] == NSOrderedDescending) {
                    newestDate = mod;
                    newestFile = fullPath;
                }
            }
        }
    }
    return newestFile;
}

+ (UIImage *)findImageInView:(UIView *)view {
    if (!view) return nil;
    
    __block UIImage *largestImage = nil;
    __block size_t largestArea = 0;
    
    void (^checkImage)(UIImage *) = ^(UIImage *img) {
        if (!img) return;
        size_t area = (size_t)(img.size.width * img.size.height * (img.scale > 0 ? img.scale : 1.0));
        if (area > largestArea && img.size.width >= 80 && img.size.height >= 80) {
            largestArea = area;
            largestImage = img;
        }
    };
    
    void (^checkLayerContents)(CGImageRef) = ^(CGImageRef cg) {
        if (!cg) return;
        size_t w = CGImageGetWidth(cg);
        size_t h = CGImageGetHeight(cg);
        if (w * h > largestArea && w >= 80 && h >= 80) {
            largestArea = w * h;
            largestImage = [UIImage imageWithCGImage:cg scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
        }
    };
    
    scanViewsRecursively(view, checkImage, checkLayerContents);
    return largestImage;
}

+ (UIImage *)snapshotView:(UIView *)view {
    if (!view) return nil;
    CGSize size = view.bounds.size;
    if (size.width <= 0 || size.height <= 0) return nil;
    
    UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    UIImage *snap = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snap;
}

+ (void)saveMediaFromController:(UIViewController *)controller {
    if (!controller) return;
    
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
    
    // Check if video is playing or present
    NSString *videoPath = [self findVideoPathInController:controller];
    if (videoPath && [[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(videoPath)) {
            UISaveVideoAtPathToSavedPhotosAlbum(videoPath, [MediaSaver shared], @selector(video:didFinishSavingWithError:contextInfo:), NULL);
            return;
        }
    }
    
    // Check for image
    UIImage *image = [self findImageInView:controller.view];
    if (image) {
        UIImageWriteToSavedPhotosAlbum(image, [MediaSaver shared], @selector(image:didFinishSavingWithError:contextInfo:), NULL);
        return;
    }
    
    // Fallback: snapshot the view
    UIImage *snapshot = [self snapshotView:controller.view];
    if (snapshot) {
        UIImageWriteToSavedPhotosAlbum(snapshot, [MediaSaver shared], @selector(image:didFinishSavingWithError:contextInfo:), NULL);
        return;
    }
    
    [self showToast:@"Unable to save media" success:NO];
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (!error) {
        [MediaSaver showToast:@"Photo saved to Camera Roll" success:YES];
    } else {
        [MediaSaver showToast:[NSString stringWithFormat:@"Error: %@", error.localizedDescription] success:NO];
    }
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    if (!error) {
        [MediaSaver showToast:@"Video saved to Camera Roll" success:YES];
    } else {
        [MediaSaver showToast:[NSString stringWithFormat:@"Error: %@", error.localizedDescription] success:NO];
    }
}

+ (void)showToast:(NSString *)message success:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        if (!window) return;
        
        // Remove existing toast if any
        UIView *existing = [window viewWithTag:998899];
        if (existing) [existing removeFromSuperview];
        
        UIView *toast = [[UIView alloc] init];
        toast.tag = 998899;
        toast.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
        toast.layer.cornerRadius = 18;
        toast.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2].CGColor;
        toast.layer.borderWidth = 1.0;
        toast.clipsToBounds = YES;
        toast.layer.zPosition = 99999;
        toast.translatesAutoresizingMaskIntoConstraints = NO;
        
        UILabel *label = [[UILabel alloc] init];
        label.text = [NSString stringWithFormat:@"%@  %@", success ? @"✓" : @"✕", message];
        label.textColor = success ? [UIColor colorWithRed:0.35 green:0.95 blue:0.45 alpha:1.0] : [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        label.textAlignment = NSTextAlignmentCenter;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        
        [toast addSubview:label];
        [window addSubview:toast];
        
        [NSLayoutConstraint activateConstraints:@[
            [toast.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
            [toast.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:24],
            [toast.heightAnchor constraintEqualToConstant:40],
            [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:20],
            [label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-20],
            [label.centerYAnchor constraintEqualToAnchor:toast.centerYAnchor]
        ]];
        
        toast.alpha = 0.0;
        toast.transform = CGAffineTransformMakeScale(0.85, 0.85);
        
        [UIView animateWithDuration:0.25 animations:^{
            toast.alpha = 1.0;
            toast.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.25 animations:^{
                    toast.alpha = 0.0;
                    toast.transform = CGAffineTransformMakeScale(0.85, 0.85);
                } completion:^(BOOL finished) {
                    [toast removeFromSuperview];
                }];
            });
        }];
    });
}

@end
