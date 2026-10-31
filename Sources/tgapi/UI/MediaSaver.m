#import "MediaSaver.h"
#import "../Headers.h"
#import "Headers.h"
#import "../fishhook/fishhook.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <pthread.h>

@interface MediaSaverButton : UIButton
@property (nonatomic, weak) UIViewController *targetController;
@property (nonatomic, weak) id targetNode;
@end

@implementation MediaSaverButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect expanded = CGRectInset(self.bounds, -10.0, -10.0);
    return CGRectContainsPoint(expanded, point);
}
@end

#define MAX_TRACKED_FDS 4096

static int (*orig_open)(const char *path, int oflag, ...);
static int (*orig_close)(int fd);
static ssize_t (*orig_read)(int fd, void *buf, size_t nbyte);
static ssize_t (*orig_pread)(int fd, void *buf, size_t nbyte, off_t offset);

static char *fd_to_path[MAX_TRACKED_FDS];
static uint8_t fd_is_video[MAX_TRACKED_FDS];
static pthread_mutex_t fd_mutex = PTHREAD_MUTEX_INITIALIZER;

static char last_played_video_path[1024] = {0};
static double last_played_video_time = 0;
static pthread_mutex_t played_video_mutex = PTHREAD_MUTEX_INITIALIZER;

static NSMutableArray<NSString *> *openedVideoPaths = nil;
static id openedVideoPathsLock = nil;

static void recordPlayingVideo(const char *path) {
    if (!path || path[0] == '\0') return;
    pthread_mutex_lock(&played_video_mutex);
    strlcpy(last_played_video_path, path, sizeof(last_played_video_path));
    last_played_video_time = CFAbsoluteTimeGetCurrent();
    pthread_mutex_unlock(&played_video_mutex);
}

static NSString *getCurrentPlayingVideoPath(void) {
    pthread_mutex_lock(&played_video_mutex);
    NSString *p = (last_played_video_path[0] != '\0') ? [NSString stringWithUTF8String:last_played_video_path] : nil;
    pthread_mutex_unlock(&played_video_mutex);
    return p;
}

static int hook_open(const char *path, int oflag, ...) {
    int fd;
    if (oflag & O_CREAT) {
        va_list args;
        va_start(args, oflag);
        mode_t mode = (mode_t)va_arg(args, int);
        va_end(args);
        fd = orig_open ? orig_open(path, oflag, mode) : open(path, oflag, mode);
    } else {
        fd = orig_open ? orig_open(path, oflag) : open(path, oflag);
    }
    
    if (fd >= 0 && fd < MAX_TRACKED_FDS && path != NULL) {
        const char *dot = strrchr(path, '.');
        BOOL isExtVideo = (dot && (strcasecmp(dot, ".mp4") == 0 || strcasecmp(dot, ".mov") == 0 || strcasecmp(dot, ".m4v") == 0));
        BOOL isPostboxOrTemp = (strstr(path, "postbox/media") != NULL || strstr(path, "/temp/") != NULL || strstr(path, "/tmp/") != NULL);
        
        pthread_mutex_lock(&fd_mutex);
        if (fd_to_path[fd]) {
            free(fd_to_path[fd]);
            fd_to_path[fd] = NULL;
        }
        if (isExtVideo || isPostboxOrTemp) {
            fd_to_path[fd] = strdup(path);
            fd_is_video[fd] = isExtVideo ? 1 : 0;
            if (isExtVideo) {
                @autoreleasepool {
                    [MediaSaver noteOpenedCandidatePath:[NSString stringWithUTF8String:path]];
                }
            }
        } else {
            fd_is_video[fd] = 0;
        }
        pthread_mutex_unlock(&fd_mutex);
    }
    return fd;
}

static int hook_close(int fd) {
    if (fd >= 0 && fd < MAX_TRACKED_FDS) {
        pthread_mutex_lock(&fd_mutex);
        if (fd_to_path[fd]) {
            free(fd_to_path[fd]);
            fd_to_path[fd] = NULL;
        }
        fd_is_video[fd] = 0;
        pthread_mutex_unlock(&fd_mutex);
    }
    return orig_close ? orig_close(fd) : close(fd);
}

static ssize_t hook_read(int fd, void *buf, size_t nbyte) {
    ssize_t ret = orig_read ? orig_read(fd, buf, nbyte) : read(fd, buf, nbyte);
    if (ret > 0 && fd >= 0 && fd < MAX_TRACKED_FDS) {
        char *path = NULL;
        uint8_t isVid = 0;
        pthread_mutex_lock(&fd_mutex);
        if (fd_to_path[fd]) {
            if (fd_is_video[fd] == 0 && ret >= 8) {
                const char *b = (const char *)buf;
                if (memcmp(b + 4, "ftyp", 4) == 0 ||
                    memcmp(b + 4, "moov", 4) == 0 ||
                    memcmp(b + 4, "wide", 4) == 0 ||
                    memcmp(b, "\x1A\x45\xDF\xA3", 4) == 0) {
                    fd_is_video[fd] = 1;
                } else {
                    size_t scanLimit = (ret < 64) ? ret : 64;
                    for (size_t i = 0; i + 4 <= scanLimit; i++) {
                        if (memcmp(b + i, "ftyp", 4) == 0 || memcmp(b + i, "moov", 4) == 0) {
                            fd_is_video[fd] = 1;
                            break;
                        }
                    }
                }
            }
            isVid = fd_is_video[fd];
            path = fd_to_path[fd];
        }
        pthread_mutex_unlock(&fd_mutex);
        
        if (isVid && path) {
            recordPlayingVideo(path);
        }
    }
    return ret;
}

static ssize_t hook_pread(int fd, void *buf, size_t nbyte, off_t offset) {
    ssize_t ret = orig_pread ? orig_pread(fd, buf, nbyte, offset) : pread(fd, buf, nbyte, offset);
    if (ret > 0 && fd >= 0 && fd < MAX_TRACKED_FDS) {
        char *path = NULL;
        uint8_t isVid = 0;
        pthread_mutex_lock(&fd_mutex);
        if (fd_to_path[fd]) {
            if (fd_is_video[fd] == 0 && ret >= 8) {
                const char *b = (const char *)buf;
                if (offset == 0 && (memcmp(b + 4, "ftyp", 4) == 0 ||
                                    memcmp(b + 4, "moov", 4) == 0 ||
                                    memcmp(b + 4, "wide", 4) == 0 ||
                                    memcmp(b, "\x1A\x45\xDF\xA3", 4) == 0)) {
                    fd_is_video[fd] = 1;
                } else {
                    size_t scanLimit = (ret < 64) ? ret : 64;
                    for (size_t i = 0; i + 4 <= scanLimit; i++) {
                        if (memcmp(b + i, "ftyp", 4) == 0 || memcmp(b + i, "moov", 4) == 0) {
                            fd_is_video[fd] = 1;
                            break;
                        }
                    }
                }
            }
            isVid = fd_is_video[fd];
            path = fd_to_path[fd];
        }
        pthread_mutex_unlock(&fd_mutex);
        
        if (isVid && path) {
            recordPlayingVideo(path);
        }
    }
    return ret;
}

__attribute__((constructor))
static void initMediaSaverHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        openedVideoPaths = [NSMutableArray array];
        openedVideoPathsLock = [[NSObject alloc] init];
        
        rebind_symbols((struct rebinding[]){
            {"open", (void *)hook_open, (void **)&orig_open},
            {"close", (void *)hook_close, (void **)&orig_close},
            {"read", (void *)hook_read, (void **)&orig_read},
            {"pread", (void *)hook_pread, (void **)&orig_pread}
        }, 4);
    });
}

@implementation MediaSaver

+ (instancetype)shared {
    static MediaSaver *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MediaSaver alloc] init];
    });
    return instance;
}

+ (void)noteOpenedCandidatePath:(NSString *)path {
    if (!path || path.length == 0) return;
    
    if (!openedVideoPathsLock) {
        openedVideoPaths = [NSMutableArray array];
        openedVideoPathsLock = [[NSObject alloc] init];
    }
    
    @synchronized (openedVideoPathsLock) {
        [openedVideoPaths removeObject:path];
        [openedVideoPaths insertObject:path atIndex:0];
        if (openedVideoPaths.count > 15) {
            [openedVideoPaths removeLastObject];
        }
    }
}

+ (NSString *)lastOpenedVideoPath {
    if (!openedVideoPathsLock) return nil;
    @synchronized (openedVideoPathsLock) {
        for (NSString *p in openedVideoPaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                return p;
            }
        }
    }
    return nil;
}

+ (NSString *)currentActivePlayingVideoPath {
    return getCurrentPlayingVideoPath();
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

static UIImage *downloadIconImageSmall(void) {
    static UIImage *icon = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
            icon = [UIImage systemImageNamed:@"arrow.down.to.line" withConfiguration:config];
            if (icon) {
                icon = [icon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                return;
            }
        }
        
        CGSize size = CGSizeMake(18, 18);
        UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
        
        [[UIColor whiteColor] setStroke];
        
        UIBezierPath *stem = [UIBezierPath bezierPath];
        [stem moveToPoint:CGPointMake(9, 2)];
        [stem addLineToPoint:CGPointMake(9, 10)];
        stem.lineWidth = 2.0;
        stem.lineCapStyle = kCGLineCapRound;
        [stem stroke];
        
        UIBezierPath *head = [UIBezierPath bezierPath];
        [head moveToPoint:CGPointMake(5, 7)];
        [head addLineToPoint:CGPointMake(9, 11)];
        [head addLineToPoint:CGPointMake(13, 7)];
        head.lineWidth = 2.0;
        head.lineCapStyle = kCGLineCapRound;
        head.lineJoinStyle = kCGLineJoinRound;
        [head stroke];
        
        UIBezierPath *tray = [UIBezierPath bezierPath];
        [tray moveToPoint:CGPointMake(4, 15)];
        [tray addLineToPoint:CGPointMake(14, 15)];
        tray.lineWidth = 2.0;
        tray.lineCapStyle = kCGLineCapRound;
        [tray stroke];
        
        icon = [UIGraphicsGetImageFromCurrentImageContext() imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIGraphicsEndImageContext();
    });
    return icon;
}

+ (NSString *)ensureVideoExtension:(NSString *)path {
    if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSString *ext = [path pathExtension].lowercaseString;
    if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) {
        return path;
    }
    
    NSString *target = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tg_saved_%ld.mp4", (long)(CFAbsoluteTimeGetCurrent() * 1000)]];
    [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
    NSError *err = nil;
    if ([[NSFileManager defaultManager] copyItemAtPath:path toPath:target error:&err]) {
        return target;
    }
    return path;
}

static BOOL isViewVisibleInWindow(UIView *v) {
    if (!v || v.hidden || v.alpha < 0.05) return NO;
    UIWindow *win = v.window ?: UIApplication.sharedApplication.keyWindow;
    if (!win) return YES;
    CGRect r = [v convertRect:v.bounds toView:win];
    CGRect inter = CGRectIntersection(r, win.bounds);
    return (!CGRectIsNull(inter) && inter.size.width > 60 && inter.size.height > 60);
}

static BOOL isDisplayingVideo(UIView *view) {
    if (!view) return NO;
    NSString *cls = NSStringFromClass([view class]);
    BOOL isVideoClass = [cls containsString:@"UniversalVideo"] ||
                        [cls containsString:@"MediaPlayer"] ||
                        [cls containsString:@"VideoPlayback"] ||
                        [cls containsString:@"ChatVideoGallery"] ||
                        [cls containsString:@"InstantVideo"];
    if (isVideoClass && isViewVisibleInWindow(view)) {
        return YES;
    }
    
    @try {
        id node = [view valueForKey:@"asyncdisplaykit_node"];
        if (node) {
            NSString *ncls = NSStringFromClass([node class]);
            if ([ncls containsString:@"UniversalVideo"] ||
                [ncls containsString:@"InstantVideo"] ||
                [ncls containsString:@"ChatVideoGallery"]) {
                if (isViewVisibleInWindow(view)) {
                    return YES;
                }
            }
        }
    } @catch (...) {}
    
    Class sampleBufferClass = NSClassFromString(@"AVSampleBufferDisplayLayer");
    Class mediaLayerClass = NSClassFromString(@"MediaPlayerNodeLayer");
    if ((sampleBufferClass && [view.layer isKindOfClass:sampleBufferClass]) ||
        (mediaLayerClass && [view.layer isKindOfClass:mediaLayerClass])) {
        if (isViewVisibleInWindow(view)) {
            return YES;
        }
    }
    
    for (UIView *sub in view.subviews) {
        if (isDisplayingVideo(sub)) return YES;
    }
    return NO;
}

static id safeInvokeGetter(id obj, NSString *selectorName) {
    if (!obj || !selectorName) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if ([obj respondsToSelector:sel]) {
        IMP imp = [obj methodForSelector:sel];
        id (*func)(id, SEL) = (id (*)(id, SEL))imp;
        return func(obj, sel);
    }
    return nil;
}

static id findCentralGalleryItemNode(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return nil;
    UIView *rootView = controller.view;
    if (!rootView) return nil;
    
    CGFloat screenCenterX = CGRectGetMidX(rootView.bounds);
    id bestNode = nil;
    CGFloat minDistance = CGFLOAT_MAX;
    
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:rootView];
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        id node = nil;
        @try {
            node = [v valueForKey:@"asyncdisplaykit_node"];
        } @catch (...) {}
        
        if (node) {
            NSString *nodeCls = NSStringFromClass([node class]);
            if ([nodeCls containsString:@"GalleryItemNode"]) {
                if (!v.isHidden && v.alpha >= 0.05) {
                    CGRect rectInRoot = [v convertRect:v.bounds toView:rootView];
                    if (rectInRoot.size.width >= 80 && rectInRoot.size.height >= 80) {
                        CGFloat midX = CGRectGetMidX(rectInRoot);
                        CGFloat dist = fabs(midX - screenCenterX);
                        if (dist < minDistance) {
                            minDistance = dist;
                            bestNode = node;
                        }
                    }
                }
            }
        }
        
        for (UIView *sub in v.subviews) {
            if (!sub.isHidden && sub.alpha >= 0.05) {
                [queue addObject:sub];
            }
        }
    }
    
    if (bestNode && minDistance < rootView.bounds.size.width * 0.6) {
        return bestNode;
    }
    return nil;
}

static BOOL isControllerDisplayingVideo(UIViewController *controller) {
    if (!controller) return NO;
    
    NSString *controllerClass = NSStringFromClass([controller class]);
    BOOL isGallery = [controllerClass containsString:@"GalleryController"];
    
    id central = findCentralGalleryItemNode(controller);
    if (central) {
        NSString *cls = NSStringFromClass([central class]);
        if ([cls containsString:@"Image"] || [cls containsString:@"Photo"]) {
            return NO;
        }
        if ([cls containsString:@"Video"] || [cls containsString:@"UniversalVideo"] || [cls containsString:@"Animation"]) {
            return YES;
        }
        @try {
            id vn = safeInvokeGetter(central, @"videoNode");
            if (vn) return YES;
        } @catch (...) {}
        return NO;
    }
    
    if (isGallery) {
        return NO;
    }
    
    if (controller.isViewLoaded) {
        return isDisplayingVideo(controller.view);
    }
    return NO;
}

static void scanViewsRecursively(UIView *view, void (^checkImage)(UIImage *img), void (^checkLayerContents)(CGImageRef cg)) {
    if (!view || view.hidden || view.alpha < 0.05) return;
    @try {
        if (isViewVisibleInWindow(view)) {
            id contents = view.layer.contents;
            if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
                checkLayerContents((__bridge CGImageRef)contents);
            }
            
            if ([view isKindOfClass:[UIImageView class]]) {
                checkImage([(UIImageView *)view image]);
            }
            
            @try {
                id node = [view valueForKey:@"asyncdisplaykit_node"];
                if (node && [node respondsToSelector:@selector(image)]) {
                    checkImage(safeInvokeGetter(node, @"image"));
                }
            } @catch (...) {}
        }
        
        for (UIView *sub in view.subviews) {
            scanViewsRecursively(sub, checkImage, checkLayerContents);
        }
    } @catch (...) {}
}

+ (void)attachToController:(UIViewController *)controller {
    if (!controller || !controller.isViewLoaded) return;
    
    NSString *className = NSStringFromClass([controller class]);
    BOOL isGallery = [className containsString:@"GalleryController"];
    BOOL isSecret = [className containsString:@"SecretMediaPreviewController"];
    
    if (!isGallery && !isSecret) return;
    
    UIView *view = controller.view;
    if (!view) return;
    
    if ([view viewWithTag:998811]) return;
    
    MediaSaverButton *btn = [MediaSaverButton buttonWithType:UIButtonTypeCustom];
    btn.tag = 998811;
    btn.targetController = controller;
    
    // Telegram-style sleek dark-black translucent appearance (NO border)
    btn.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.90];
    btn.tintColor = [UIColor whiteColor];
    btn.layer.cornerRadius = 21.0;
    btn.layer.borderWidth = 0.0;
    btn.layer.borderColor = nil;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.40;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 6.0;
    btn.layer.zPosition = 9999;
    btn.clipsToBounds = NO;
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    
    [btn setImage:downloadIconImage() forState:UIControlStateNormal];
    [btn addTarget:[MediaSaver shared] action:@selector(handleButtonTap:) forControlEvents:UIControlEventTouchUpInside];
    
    btn.alpha = 0.0;
    btn.transform = CGAffineTransformMakeScale(0.85, 0.85);
    
    [view addSubview:btn];
    
    if (isSecret) {
        [NSLayoutConstraint activateConstraints:@[
            [btn.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:64],
            [btn.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:16],
            [btn.widthAnchor constraintEqualToConstant:42],
            [btn.heightAnchor constraintEqualToConstant:42]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [btn.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-60],
            [btn.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [btn.widthAnchor constraintEqualToConstant:42],
            [btn.heightAnchor constraintEqualToConstant:42]
        ]];
    }
    
    [UIView animateWithDuration:0.25 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
        btn.alpha = 1.0;
        btn.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleLongPress:)];
    lp.minimumPressDuration = 0.5;
    [view addGestureRecognizer:lp];
}

+ (void)detachFromController:(UIViewController *)controller animated:(BOOL)animated {
    if (!controller || !controller.isViewLoaded) return;
    UIView *btn = [controller.view viewWithTag:998811] ?: [controller.view.window viewWithTag:998811];
    if (!btn) return;
    
    if (btn.alpha <= 0.05) {
        [btn removeFromSuperview];
        return;
    }
    
    if (animated) {
        [UIView animateWithDuration:0.10 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            btn.alpha = 0.0;
            btn.transform = CGAffineTransformMakeScale(0.85, 0.85);
        } completion:^(BOOL finished) {
            [btn removeFromSuperview];
        }];
    } else {
        btn.alpha = 0.0;
        [btn removeFromSuperview];
    }
}

+ (void)attachInstantVideoButtonToNode:(id)node {
    if (!node) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *v = nil;
        id viewVal = safeInvokeGetter(node, @"view");
        if (viewVal && [viewVal isKindOfClass:[UIView class]]) {
            v = (UIView *)viewVal;
        } else if ([node isKindOfClass:[UIView class]]) {
            v = (UIView *)node;
        }
        if (!v) return;
        
        CGSize size = v.bounds.size;
        if (size.width < 50 || size.height < 50) return;
        
        CGFloat btnDim = 32.0;
        CGRect targetFrame = CGRectMake(size.width - btnDim - 6.0, 6.0, btnDim, btnDim);
        
        MediaSaverButton *btn = [v viewWithTag:998833];
        if (btn) {
            btn.frame = targetFrame;
            [v bringSubviewToFront:btn];
            return;
        }
        
        btn = [MediaSaverButton buttonWithType:UIButtonTypeCustom];
        btn.tag = 998833;
        btn.targetNode = node;
        btn.frame = targetFrame;
        btn.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.08 alpha:0.92];
        btn.tintColor = [UIColor whiteColor];
        btn.layer.cornerRadius = btnDim / 2.0;
        btn.layer.borderWidth = 0.0;
        btn.layer.borderColor = nil;
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOpacity = 0.45;
        btn.layer.shadowOffset = CGSizeMake(0, 1.5);
        btn.layer.shadowRadius = 4.0;
        btn.layer.zPosition = 99999;
        btn.clipsToBounds = NO;
        btn.userInteractionEnabled = YES;
        
        [btn setImage:downloadIconImageSmall() forState:UIControlStateNormal];
        [btn addTarget:[MediaSaver shared] action:@selector(handleInstantVideoButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        
        UITapGestureRecognizer *singleTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleInstantVideoButtonTap:)];
        singleTap.numberOfTapsRequired = 1;
        [btn addGestureRecognizer:singleTap];
        
        btn.alpha = 0.0;
        btn.transform = CGAffineTransformMakeScale(0.70, 0.70);
        [v addSubview:btn];
        [v bringSubviewToFront:btn];
        
        [UIView animateWithDuration:0.25 delay:0.05 options:UIViewAnimationOptionCurveEaseOut animations:^{
            btn.alpha = 1.0;
            btn.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

- (void)handleButtonTap:(MediaSaverButton *)sender {
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            sender.transform = CGAffineTransformIdentity;
        }];
    }];
    
    UIViewController *vc = sender.targetController;
    if (!vc) {
        UIResponder *r = sender;
        while (r && ![r isKindOfClass:[UIViewController class]]) {
            r = r.nextResponder;
        }
        vc = (UIViewController *)r;
    }
    if (vc) {
        [MediaSaver saveMediaFromController:vc];
    }
}

- (void)handleInstantVideoButtonTap:(id)sender {
    MediaSaverButton *btn = nil;
    if ([sender isKindOfClass:[MediaSaverButton class]]) {
        btn = (MediaSaverButton *)sender;
    } else if ([sender isKindOfClass:[UIGestureRecognizer class]]) {
        UIView *v = [(UIGestureRecognizer *)sender view];
        if ([v isKindOfClass:[MediaSaverButton class]]) {
            btn = (MediaSaverButton *)v;
        }
    }
    
    if (btn) {
        [UIView animateWithDuration:0.1 animations:^{
            btn.transform = CGAffineTransformMakeScale(0.85, 0.85);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.15 animations:^{
                btn.transform = CGAffineTransformIdentity;
            }];
        }];
    }
    
    @try {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    } @catch (...) {}
    
    id target = btn.targetNode ?: btn;
    NSString *videoPath = [MediaSaver findVideoPathForTarget:target];
    if (videoPath && [[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        [MediaSaver saveVideoToPhotos:videoPath];
        return;
    }
    
    [MediaSaver showToast:@"Play round video first to cache it" success:NO];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    UIResponder *r = gesture.view;
    while (r && ![r isKindOfClass:[UIViewController class]]) {
        r = r.nextResponder;
    }
    UIViewController *vc = (UIViewController *)r;
    if (!vc) return;
    
    @try {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [feedback impactOccurred];
    } @catch (...) {}
    
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Media Options" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Save to Camera Roll" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [MediaSaver saveMediaFromController:vc];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    
    [vc presentViewController:sheet animated:YES completion:nil];
}

- (void)handleInstantVideoDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    
    @try {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
        [feedback impactOccurred];
    } @catch (...) {}
    
    id target = gesture.view;
    NSString *videoPath = [MediaSaver findVideoPathForTarget:target];
    if (videoPath && [[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        [MediaSaver saveVideoToPhotos:videoPath];
        return;
    }
    
    [MediaSaver showToast:@"Play round video first to cache it" success:NO];
}

static NSString *extractPathFromPlayerLayer(CALayer *layer) {
    if (!layer) return nil;
    @try {
        id player = safeInvokeGetter(layer, @"player");
        if (player) {
            id item = safeInvokeGetter(player, @"currentItem");
            if (item) {
                id asset = safeInvokeGetter(item, @"asset");
                if (asset) {
                    id urlObj = safeInvokeGetter(asset, @"URL");
                    if (urlObj && [urlObj isKindOfClass:[NSURL class]]) {
                        NSURL *url = (NSURL *)urlObj;
                        if (url.isFileURL && url.path) {
                            return url.path;
                        }
                    }
                }
            }
        }
    } @catch (...) {}
    for (CALayer *sub in layer.sublayers) {
        NSString *found = extractPathFromPlayerLayer(sub);
        if (found) return found;
    }
    return nil;
}

+ (NSString *)findVideoPathForTarget:(id)target {
    if (!target) return nil;
    
    NSString *targetCls = NSStringFromClass([target class]);
    if ([targetCls containsString:@"Image"] || [targetCls containsString:@"Photo"]) {
        return nil;
    }
    
    // If target is a UIViewController and it is not displaying a video (e.g. photo is viewed), do not look for video!
    if ([target isKindOfClass:[UIViewController class]]) {
        if (!isControllerDisplayingVideo((UIViewController *)target)) {
            return nil;
        }
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // 1. Precise binding via TLParser Swift reflection (centralItemNode / fileId / uniqueId / tempPath)
    Class parserCls = NSClassFromString(@"TLParser");
    if (parserCls && [parserCls respondsToSelector:@selector(findMediaFilePathFromTarget:)]) {
        NSString *path = [parserCls findMediaFilePathFromTarget:target];
        if (path && [fm fileExistsAtPath:path]) {
            return [self ensureVideoExtension:path];
        }
    }
    
    // 2. AVPlayerLayer on target view or subviews
    UIView *view = nil;
    if ([target isKindOfClass:[UIViewController class]]) {
        view = [(UIViewController *)target isViewLoaded] ? [(UIViewController *)target view] : nil;
    } else if ([target isKindOfClass:[UIView class]]) {
        view = (UIView *)target;
    } else {
        id v = safeInvokeGetter(target, @"view");
        if (v && [v isKindOfClass:[UIView class]]) {
            view = (UIView *)v;
        }
    }
    if (view) {
        NSString *playerPath = extractPathFromPlayerLayer(view.layer);
        if (playerPath && [fm fileExistsAtPath:playerPath]) {
            return [self ensureVideoExtension:playerPath];
        }
    }
    
    // For gallery items/controllers, never fall back to old played videos from other pages!
    BOOL isGallery = [targetCls containsString:@"GalleryItemNode"] || [targetCls containsString:@"GalleryController"];
    if (isGallery) {
        return nil;
    }
    
    // 3. Last opened candidate or active playing video from Telegram decoder (only if very recent within 5s)
    NSString *active = getCurrentPlayingVideoPath();
    if (active && (CFAbsoluteTimeGetCurrent() - last_played_video_time < 5.0)) {
        if ([active hasSuffix:@"_partial"]) {
            NSString *complete = [active substringToIndex:active.length - 8];
            if ([fm fileExistsAtPath:complete]) {
                active = complete;
            }
        }
        if ([fm fileExistsAtPath:active]) {
            NSDictionary *attrs = [fm attributesOfItemAtPath:active error:nil];
            if (attrs && [attrs fileSize] >= 40 * 1024) {
                return [self ensureVideoExtension:active];
            }
        }
    }
    
    NSString *recent = [self lastOpenedVideoPath];
    if (recent && [fm fileExistsAtPath:recent]) {
        if ([recent hasSuffix:@"_partial"]) {
            NSString *complete = [recent substringToIndex:recent.length - 8];
            if ([fm fileExistsAtPath:complete]) {
                recent = complete;
            }
        }
        return [self ensureVideoExtension:recent];
    }
    
    return nil;
}

+ (NSString *)findVideoPathInController:(UIViewController *)controller {
    return [self findVideoPathForTarget:controller];
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
    if (size.width <= 10 || size.height <= 10) return nil;
    
    UIImage *snap = nil;
    @try {
        UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
        [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
        snap = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    } @catch (...) {}
    return snap;
}

+ (void)saveVideoToPhotos:(NSString *)videoPath {
    NSString *cleanPath = [self ensureVideoExtension:videoPath];
    if (!cleanPath || ![[NSFileManager defaultManager] fileExistsAtPath:cleanPath]) {
        [self showToast:@"Video file not found" success:NO];
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(cleanPath)) {
            UISaveVideoAtPathToSavedPhotosAlbum(cleanPath, [MediaSaver shared], @selector(video:didFinishSavingWithError:contextInfo:), NULL);
        } else {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:cleanPath]];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (success) {
                        [self showToast:@"Video saved to Camera Roll" success:YES];
                    } else {
                        [self showToast:[NSString stringWithFormat:@"Error: %@", error.localizedDescription ?: @"failed"] success:NO];
                    }
                });
            }];
        }
    });
}

+ (void)saveImageToPhotos:(UIImage *)image {
    if (!image) {
        [self showToast:@"No image found" success:NO];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImageWriteToSavedPhotosAlbum(image, [MediaSaver shared], @selector(image:didFinishSavingWithError:contextInfo:), NULL);
    });
}

+ (void)saveMediaFromController:(UIViewController *)controller {
    if (!controller) return;
    
    @try {
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    } @catch (...) {}
    
    id centralNode = findCentralGalleryItemNode(controller);
    BOOL isVideo = NO;
    if (centralNode) {
        NSString *cls = NSStringFromClass([centralNode class]);
        if ([cls containsString:@"Video"] || [cls containsString:@"UniversalVideo"] || [cls containsString:@"Animation"]) {
            isVideo = YES;
        } else if ([cls containsString:@"Image"] || [cls containsString:@"Photo"]) {
            isVideo = NO;
        } else {
            @try {
                if (safeInvokeGetter(centralNode, @"videoNode")) {
                    isVideo = YES;
                }
            } @catch (...) {}
        }
    } else {
        isVideo = isControllerDisplayingVideo(controller);
    }
    
    if (isVideo) {
        id target = centralNode ?: controller;
        NSString *videoPath = [self findVideoPathForTarget:target];
        if (videoPath && [[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
            [self saveVideoToPhotos:videoPath];
            return;
        }
        [self showToast:@"Video is downloading, please wait..." success:NO];
        return;
    }
    
    UIView *targetView = nil;
    if (centralNode) {
        id v = safeInvokeGetter(centralNode, @"view");
        if (v && [v isKindOfClass:[UIView class]]) {
            targetView = (UIView *)v;
        }
    }
    if (!targetView && controller.isViewLoaded) {
        targetView = controller.view;
    }
    
    if (targetView) {
        UIImage *image = [self findImageInView:targetView];
        if (image) {
            [self saveImageToPhotos:image];
            return;
        }
        
        if (controller.isViewLoaded && targetView != controller.view) {
            image = [self findImageInView:controller.view];
            if (image) {
                [self saveImageToPhotos:image];
                return;
            }
        }
        
        UIImage *snapshot = [self snapshotView:targetView];
        if (snapshot) {
            [self saveImageToPhotos:snapshot];
            return;
        }
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
        
        UIView *existing = [window viewWithTag:998899];
        if (existing) [existing removeFromSuperview];
        
        UIView *toast = [[UIView alloc] init];
        toast.tag = 998899;
        toast.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:0.94];
        toast.layer.cornerRadius = 18;
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

+ (void)showEditHistoryForNode:(id)node bFrame:(CGRect)bFrame msgId:(NSNumber *)msgId {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window && [UIApplication sharedApplication].windows.count > 0) {
        window = [UIApplication sharedApplication].windows.firstObject;
    }
    if (!window) return;

    UIView *oldOverlay = [window viewWithTag:998899];
    if (oldOverlay) {
        [oldOverlay removeFromSuperview];
    }

    NSArray *history = nil;
    if (node) {
        history = [NSClassFromString(@"TLParser") getEditHistoryForNode:node];
    }
    if (!history || history.count == 0) {
        NSString *cachedOrig = msgId ? [NSClassFromString(@"TLParser") getOriginalTextForId:msgId] : nil;
        if (cachedOrig && cachedOrig.length > 0) {
            history = @[
                @{
                    @"badge": @"[--:--:--]",
                    @"label": @"Исходное сообщение",
                    @"text": cachedOrig
                }
            ];
        } else {
            history = @[
                @{
                    @"badge": @"[--:--:--]",
                    @"label": @"Отредактировано",
                    @"text": @"(Исходный текст не был сохранён до редактирования)"
                }
            ];
        }
    }

    UIView *nodeView = nil;
    if (node && [node respondsToSelector:@selector(view)]) {
        SEL selView = @selector(view);
        NSMethodSignature *sig = [node methodSignatureForSelector:selView];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:node];
            [inv setSelector:selView];
            [inv invoke];
            void *retVal = NULL;
            [inv getReturnValue:&retVal];
            nodeView = (__bridge UIView *)retVal;
        }
    }

    UIView *backdrop = [[UIView alloc] initWithFrame:window.bounds];
    backdrop.tag = 998899;
    backdrop.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    backdrop.alpha = 0.0;
    backdrop.userInteractionEnabled = YES;

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(dismissEditHistoryOverlay)];
    [backdrop addGestureRecognizer:dismissTap];

    CGFloat screenW = window.bounds.size.width;
    CGFloat screenH = window.bounds.size.height;

    CGRect bubbleInWindow;
    if (nodeView && !CGRectIsEmpty(bFrame)) {
        bubbleInWindow = [nodeView convertRect:bFrame toView:window];
    } else {
        bubbleInWindow = CGRectMake((screenW - 240.0) / 2.0, (screenH - 160.0) / 2.0, 240.0, 160.0);
    }

    CGFloat cardW = MAX(bubbleInWindow.size.width, 240.0);
    if (cardW > screenW - 24.0) cardW = screenW - 24.0;
    if (cardW < 220.0) cardW = 220.0;

    CGFloat contentH = 34.0;
    for (NSDictionary *entry in history) {
        NSString *txt = entry[@"text"] ?: @"";
        CGSize s = [txt boundingRectWithSize:CGSizeMake(cardW - 24.0, 300) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5]} context:nil].size;
        contentH += MAX(s.height, 16.0) + 26.0;
    }
    contentH += 10.0;
    CGFloat maxH = screenH * 0.55;
    if (contentH > maxH) contentH = maxH;

    CGFloat cardX = bubbleInWindow.origin.x;
    if (cardX + cardW > screenW - 12.0) cardX = screenW - cardW - 12.0;
    if (cardX < 12.0) cardX = 12.0;

    CGFloat cardY = bubbleInWindow.origin.y - contentH - 8.0;
    if (cardY < 60.0) {
        cardY = CGRectGetMaxY(bubbleInWindow) + 8.0;
    }
    if (cardY + contentH > screenH - 40.0) {
        cardY = screenH - contentH - 40.0;
    }

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:blur];
    card.frame = CGRectMake(cardX, cardY, cardW, contentH);
    card.layer.cornerRadius = 14.0;
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
    card.transform = CGAffineTransformMakeScale(0.92, 0.92);

    UILabel *header = [[UILabel alloc] initWithFrame:CGRectMake(12, 9, cardW - 24, 16)];
    header.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    header.textColor = [UIColor colorWithRed:0.40 green:0.75 blue:1.0 alpha:1.0];
    header.text = @"✏️ ИСТОРИЯ ИЗМЕНЕНИЙ";
    [card.contentView addSubview:header];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 28, cardW, contentH - 28)];
    scrollView.showsVerticalScrollIndicator = YES;
    scrollView.alwaysBounceVertical = NO;

    CGFloat currY = 4.0;
    for (NSDictionary *entry in history) {
        NSString *badgeStr = entry[@"badge"] ?: @"";
        NSString *labelStr = entry[@"label"] ?: @"";
        NSString *bodyStr = entry[@"text"] ?: @"";

        UILabel *badgeLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, currY, cardW - 24, 14)];
        badgeLbl.font = [UIFont monospacedDigitSystemFontOfSize:11.0 weight:UIFontWeightBold];
        badgeLbl.textColor = [UIColor colorWithRed:0.55 green:0.85 blue:1.0 alpha:1.0];
        badgeLbl.text = [NSString stringWithFormat:@"%@  %@", badgeStr, labelStr];
        [scrollView addSubview:badgeLbl];
        currY += 16.0;

        CGSize bodySize = [bodyStr boundingRectWithSize:CGSizeMake(cardW - 24.0, 300) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12.5]} context:nil].size;
        CGFloat textH = MAX(bodySize.height, 16.0);

        UILabel *bodyLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, currY, cardW - 24, textH)];
        bodyLbl.font = [UIFont systemFontOfSize:12.5];
        bodyLbl.textColor = [UIColor whiteColor];
        bodyLbl.numberOfLines = 0;
        bodyLbl.text = bodyStr;
        bodyLbl.userInteractionEnabled = YES;

        UITapGestureRecognizer *rowTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleHistoryCopyTap:)];
        objc_setAssociatedObject(rowTap, "TweakCopyText", bodyStr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bodyLbl addGestureRecognizer:rowTap];

        [scrollView addSubview:bodyLbl];
        currY += textH + 10.0;
    }
    scrollView.contentSize = CGSizeMake(cardW, currY);
    [card.contentView addSubview:scrollView];

    [backdrop addSubview:card];
    [window addSubview:backdrop];

    [UIView animateWithDuration:0.25 delay:0.0 usingSpringWithDamping:0.85 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        backdrop.alpha = 1.0;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)handleHistoryCopyTap:(UITapGestureRecognizer *)gesture {
    NSString *txt = objc_getAssociatedObject(gesture, "TweakCopyText");
    if (txt && txt.length > 0) {
        [UIPasteboard generalPasteboard].string = txt;
        [MediaSaver showToast:@"Текст скопирован!" success:YES];
    }
}

- (void)dismissEditHistoryOverlay {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window && [UIApplication sharedApplication].windows.count > 0) {
        window = [UIApplication sharedApplication].windows.firstObject;
    }
    UIView *overlay = [window viewWithTag:998899];
    if (overlay) {
        [UIView animateWithDuration:0.20 animations:^{
            overlay.alpha = 0.0;
        } completion:^(BOOL finished) {
            (void)finished;
            [overlay removeFromSuperview];
        }];
    }
}

- (void)handleBubbleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    UIView *v = gesture.view;
    if (!v) return;

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (keyWindow && [keyWindow viewWithTag:998899]) {
        [self dismissEditHistoryOverlay];
        return;
    }

    id node = objc_getAssociatedObject(v, "TweakMessageNode");
    if (!node) return;

    BOOL isEdit = [NSClassFromString(@"TLParser") isNodeEdited:node];
    if (!isEdit) return;

    NSNumber *msgId = [NSClassFromString(@"TLParser") getMessageIdFromNode:node];

    CGRect bFrame = CGRectZero;
    SEL sel = @selector(contentFrame);
    if ([node respondsToSelector:sel]) {
        NSMethodSignature *sig = [node methodSignatureForSelector:sel];
        if (sig && strcmp([sig methodReturnType], @encode(CGRect)) == 0) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:node];
            [inv setSelector:sel];
            [inv invoke];
            [inv getReturnValue:&bFrame];
        }
    }
    if (CGRectIsEmpty(bFrame)) {
        bFrame = v.bounds;
    }

    CGPoint loc = [gesture locationInView:v];
    if (CGRectContainsPoint(bFrame, loc)) {
        [MediaSaver showEditHistoryForNode:node bFrame:bFrame msgId:msgId];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)handleEditBadgeTap:(UITapGestureRecognizer *)gesture {
    UIView *badge = gesture.view;
    if (!badge) return;

    [UIView animateWithDuration:0.1 animations:^{
        badge.transform = CGAffineTransformMakeScale(0.90, 0.90);
    } completion:^(BOOL finished) {
        (void)finished;
        [UIView animateWithDuration:0.1 animations:^{
            badge.transform = CGAffineTransformIdentity;
        }];
    }];

    id node = objc_getAssociatedObject(badge, "TweakBadgeNode");
    NSNumber *msgId = objc_getAssociatedObject(badge, "TweakBadgeMsgId") ?: objc_getAssociatedObject(badge, "LeadBadgeMsgId");

    CGRect bFrame = CGRectZero;
    if (node) {
        SEL sel = @selector(contentFrame);
        if ([node respondsToSelector:sel]) {
            NSMethodSignature *sig = [node methodSignatureForSelector:sel];
            if (sig && strcmp([sig methodReturnType], @encode(CGRect)) == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:node];
                [inv setSelector:sel];
                [inv invoke];
                [inv getReturnValue:&bFrame];
            }
        }
    }
    if (CGRectIsEmpty(bFrame)) {
        bFrame = badge.superview ? badge.superview.bounds : badge.frame;
    }

    [MediaSaver showEditHistoryForNode:node bFrame:bFrame msgId:msgId];
}

@end
