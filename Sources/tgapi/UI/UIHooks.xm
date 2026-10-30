#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Headers.h"
#import "../Headers.h"
#import "MediaSaver.h"

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readonly) UIView *view;
@property (atomic, assign, readonly) CGRect bounds;
@property (atomic, assign, readonly) BOOL isNodeLoaded;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
- (void)didLoad;
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)__handle5PleTap;
@end

@interface TabBarNode : ASDisplayNode
@end

@interface PeerInfoScreenItemNode : ASDisplayNode
@end

static ThreeFingerGestureHandler *gestureHandler = nil;
static __weak TGLocalization *TGLocalizationShared = nil;

%hook TGLocalization

- (id)initWithVersion:(int)a code:(id)b dict:(id)c isActive:(BOOL)d {
    TGLocalization *instance = %orig;
    if (a != 96929692 && instance) {
        TGLocalizationShared = instance;
    }
    return instance;
}

%end

void showUI() {
	TGExtra *ui = [TGExtra new];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:ui];

	UIWindow *window = UIApplication.sharedApplication.keyWindow;
	UIViewController *rootVC = window.rootViewController;
	if (rootVC) {
	    [rootVC presentViewController:navVC animated:YES completion:nil];
	}
}

void handleThreeFingerLongPress(UILongPressGestureRecognizer *gesture) {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        showUI();
    }
}

@implementation ThreeFingerGestureHandler
- (void)handleThreeFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    handleThreeFingerLongPress(gesture);
}
@end

static CGRect getContentFrameOfNode(ASDisplayNode *node) {
    if ([node respondsToSelector:@selector(contentFrame)]) {
        SEL sel = @selector(contentFrame);
        NSMethodSignature *sig = [node methodSignatureForSelector:sel];
        if (sig && strcmp([sig methodReturnType], @encode(CGRect)) == 0) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:node];
            [inv setSelector:sel];
            [inv invoke];
            CGRect rect;
            [inv getReturnValue:&rect];
            if (!CGRectIsEmpty(rect) && !CGRectIsNull(rect)) {
                return rect;
            }
        }
    }
    return node.bounds;
}

static void updateDeletedBadgeForNode(ASDisplayNode *node) {
    if (!node || !node.isNodeLoaded) return;
    UIView *v = node.view;
    if (!v) return;

    NSNumber *msgId = [NSClassFromString(@"TLParser") getMessageIdFromNode:node];
    BOOL isDel = (msgId != nil && [NSClassFromString(@"TLParser") isDeleted:msgId]);

    UILabel *badge = (UILabel *)[v viewWithTag:998855];
    if (!isDel) {
        if (badge) {
            badge.hidden = YES;
        }
        return;
    }

    if (!badge) {
        badge = [[UILabel alloc] init];
        badge.tag = 998855;
        badge.text = @"🗑️";
        badge.textAlignment = NSTextAlignmentCenter;
        badge.font = [UIFont systemFontOfSize:11];
        badge.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        badge.layer.cornerRadius = 9.0;
        badge.layer.masksToBounds = YES;
        badge.layer.zPosition = 1000;
        badge.userInteractionEnabled = NO;
        [v addSubview:badge];
    }

    badge.hidden = NO;
    CGRect bFrame = getContentFrameOfNode(node);
    CGFloat badgeSize = 18.0;
    CGFloat x = CGRectGetMaxX(bFrame) - badgeSize - 4.0;
    CGFloat y = CGRectGetMinY(bFrame) + 4.0;
    if (x < CGRectGetMinX(bFrame) + 2.0) {
        x = CGRectGetMinX(bFrame) + 2.0;
    }
    badge.frame = CGRectMake(x, y, badgeSize, badgeSize);
    [v bringSubviewToFront:badge];
}

static void refreshDeletedBadgesInView(UIView *view) {
    if (!view) return;
    NSString *className = NSStringFromClass([view class]);
    if ([className containsString:@"ChatMessage"]) {
        [view setNeedsLayout];
    }
    for (UIView *sub in view.subviews) {
        refreshDeletedBadgesInView(sub);
    }
}

%hook ASDisplayNode
%property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
%property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

- (void)didLoad {
    %orig;
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"InstantVideo"] || [className containsString:@"OverlayInstantVideoNode"]) {
        UIView *v = [(ASDisplayNode *)self view];
        if (v && ![v viewWithTag:998822]) {
            UIView *marker = [[UIView alloc] initWithFrame:CGRectZero];
            marker.tag = 998822;
            marker.hidden = YES;
            [v addSubview:marker];

            UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleInstantVideoDoubleTap:)];
            doubleTap.numberOfTapsRequired = 2;
            [v addGestureRecognizer:doubleTap];
        }
        [MediaSaver attachInstantVideoButtonToNode:self];
    } else if ([className containsString:@"ChatMessage"] && [className containsString:@"Item"] && ![className containsString:@"Content"]) {
        updateDeletedBadgeForNode(self);
    }
}

- (void)layout {
    %orig;
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"InstantVideo"] || [className containsString:@"OverlayInstantVideoNode"]) {
        [MediaSaver attachInstantVideoButtonToNode:self];
    } else if ([className containsString:@"ChatMessage"] && [className containsString:@"Item"] && ![className containsString:@"Content"]) {
        updateDeletedBadgeForNode(self);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"InstantVideo"] || [className containsString:@"OverlayInstantVideoNode"]) {
        UIView *v = [(ASDisplayNode *)self view];
        UIView *btn = [v viewWithTag:998833];
        if (btn && !btn.hidden && btn.alpha > 0.05 && btn.userInteractionEnabled) {
            CGPoint btnPoint = [v convertPoint:point toView:btn];
            if ([btn pointInside:btnPoint withEvent:event]) {
                return btn;
            }
        }
    }
    return %orig;
}

%new
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
		showUI();
    }
}

%new
- (void)__handle5PleTap {
	showUI();
}

%end

%hook TabBarNode

- (void)didEnterHierarchy {
	%orig;

	ASDisplayNode *mainNode = self;

    for (ASDisplayNode *child in mainNode.subnodes) {
		NSString *localizedTitle = @"Chats";

		NSString *resultTitle = [TGLocalizationShared get:@"DialogList.TabTitle"];
		if (resultTitle.length > 0 && ![resultTitle isEqualToString:@"DialogList.TabTitle"]) {
			localizedTitle = resultTitle;
		}

        if ([child.accessibilityLabel isEqualToString:localizedTitle]) {

			if (!child.tapGesture) {
				child.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:child action:@selector(__handle5PleTap)];
				child.tapGesture.numberOfTapsRequired = 5;
			}

			if (![child.view.gestureRecognizers containsObject:child.tapGesture]) {
                [child.view addGestureRecognizer:child.tapGesture];
			}
        }
    }
}

%end

%hook PeerInfoScreenItemNode

- (void)didEnterHierarchy {
    %orig;

    ASDisplayNode *mainNode = self;

	if (!mainNode.longPressGesture) {
		 mainNode.longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:mainNode action:@selector(__handleSettingsTabLongPress:)];
		 mainNode.longPressGesture.minimumPressDuration = 0.5;
	}

    // Check children for specific node: Telegram FAQ / Вопросы о Telegram / Support
    for (ASDisplayNode *child in mainNode.subnodes) {
        if ([NSStringFromClass([child class]) isEqualToString:@"Display.AccessibilityAreaNode"]) {
			NSString *label = child.accessibilityLabel;
			if (!label || label.length == 0) continue;

			BOOL isFAQ = NO;
			NSString *faqStr1 = [TGLocalizationShared get:@"Settings.FAQ"];
			NSString *faqStr2 = [TGLocalizationShared get:@"Settings_FAQ"];
			NSString *supportStr = [TGLocalizationShared get:@"Settings.Support"];

			if ((faqStr1.length > 0 && [label isEqualToString:faqStr1]) ||
			    (faqStr2.length > 0 && [label isEqualToString:faqStr2]) ||
			    (supportStr.length > 0 && [label isEqualToString:supportStr]) ||
			    [label rangeOfString:@"FAQ" options:NSCaseInsensitiveSearch].location != NSNotFound ||
			    [label rangeOfString:@"Вопросы" options:NSCaseInsensitiveSearch].location != NSNotFound ||
			    [label rangeOfString:@"ЧаВо" options:NSCaseInsensitiveSearch].location != NSNotFound ||
			    [label rangeOfString:@"Features" options:NSCaseInsensitiveSearch].location != NSNotFound) {
				isFAQ = YES;
			}

            if (isFAQ) {
				if (![mainNode.view.gestureRecognizers containsObject:mainNode.longPressGesture]) {
					[mainNode.view addGestureRecognizer:mainNode.longPressGesture];
				}
            }
        }
    }
}

%end

%group LoginQRGroup

@interface AuthorizationSequencePhoneEntryControllerNode : ASDisplayNode
@end

%hook AuthorizationSequencePhoneEntryControllerNode

- (void)didLoad {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        ASDisplayNode *node = (ASDisplayNode *)self;
        UIView *view = [node view];
        if (!view) return;

        if ([view viewWithTag:998877]) return;

        UIButton *qrButton = [UIButton buttonWithType:UIButtonTypeSystem];
        qrButton.tag = 998877;
        [qrButton setTitle:@"Log in with QR Code" forState:UIControlStateNormal];
        qrButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        qrButton.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
        qrButton.tintColor = [UIColor systemBlueColor];
        qrButton.layer.cornerRadius = 12;
        qrButton.clipsToBounds = YES;
        qrButton.translatesAutoresizingMaskIntoConstraints = NO;

        [qrButton addTarget:self action:@selector(__tweak_triggerQrLogin) forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:qrButton];

        [NSLayoutConstraint activateConstraints:@[
            [qrButton.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
            [qrButton.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor constant:-16],
            [qrButton.heightAnchor constraintEqualToConstant:40],
            [qrButton.widthAnchor constraintEqualToConstant:200]
        ]];
    });
}

%new
- (void)__tweak_triggerQrLogin {
    if ([self respondsToSelector:@selector(debugQrTap:)]) {
        [self performSelector:@selector(debugQrTap:) withObject:nil];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Log in with QR Code"
                                                                   message:@"Open Telegram on your PC or another device:\n1. Go to Settings → Devices\n2. Tap 'Link Desktop Device'\n3. Scan the QR code on your screen"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *rootVC = window.rootViewController;
    if (rootVC) {
        [rootVC presentViewController:alert animated:YES completion:nil];
    }
}

%end

%end

@interface LeadDownloadBoost : NSObject
+ (void)install;
@end

@interface _TtC12TelegramCore16TelegramMediaFile : NSObject
- (NSString *)mimeType;
@end

@interface _TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View : UIView
- (void)requestSave;
@end

%hook _TtC12TelegramCore16TelegramMediaFile

- (BOOL)isVoice {
    BOOL orig = %orig;
    if (orig) {
        return YES;
    }
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSendAsVoice]) {
        return orig;
    }
    NSString *mime = [self mimeType];
    if ([mime hasPrefix:@"audio/"]) {
        return YES;
    }
    return NO;
}

%end

%hook _TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View

- (void)didMoveToWindow {
    %orig;
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kDownloadStories]) return;
    UIView *view = (UIView *)self;
    if (!view.window) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kDownloadStories]) {
                if ([self respondsToSelector:@selector(requestSave)]) {
                    [self requestSave];
                }
            }
        } @catch (NSException *e) {}
    });
}

%end

%group GalleryNodeGroup

@interface GalleryControllerNode : ASDisplayNode
@end

%hook GalleryControllerNode

- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated {
    %orig;
    UIView *v = [(ASDisplayNode *)self view];
    UIView *btn = [v viewWithTag:998811] ?: [v.window viewWithTag:998811];
    if (btn) {
        if (animated) {
            [UIView animateWithDuration:0.20 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                btn.alpha = hidden ? 0.0 : 1.0;
                btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
            } completion:nil];
        } else {
            btn.alpha = hidden ? 0.0 : 1.0;
            btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
        }
    }
}

- (void)updateDismissTransition:(CGFloat)value {
    %orig;
    UIView *v = [(ASDisplayNode *)self view];
    UIView *btn = [v viewWithTag:998811] ?: [v.window viewWithTag:998811];
    if (btn) {
        btn.alpha = value;
        if (value < 0.99) {
            CGFloat scale = 0.85 + 0.15 * fmax(0.0, fmin(1.0, value));
            btn.transform = CGAffineTransformMakeScale(scale, scale);
        } else {
            btn.transform = CGAffineTransformIdentity;
        }
    }
}

- (void)animateOutWithAnimateContent:(BOOL)animateContent completion:(id)completion {
    UIView *v = [(ASDisplayNode *)self view];
    UIView *btn = [v viewWithTag:998811] ?: [v.window viewWithTag:998811];
    if (btn) {
        [UIView animateWithDuration:0.10 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            btn.alpha = 0.0;
            btn.transform = CGAffineTransformMakeScale(0.85, 0.85);
        } completion:^(BOOL finished) {
            [btn removeFromSuperview];
        }];
    }
    %orig;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    %orig;
    UIView *v = [(ASDisplayNode *)self view];
    UIView *btn = [v viewWithTag:998811] ?: [v.window viewWithTag:998811];
    if (btn && [scrollView isKindOfClass:[UIScrollView class]]) {
        CGFloat distanceFromEquilibrium = scrollView.contentOffset.y - scrollView.contentSize.height / 3.0;
        CGFloat transition = 1.0 - fmin(1.0, fmax(0.0, fabs(distanceFromEquilibrium) / 50.0));
        btn.alpha = transition;
        if (transition < 0.99) {
            CGFloat scale = 0.85 + 0.15 * fmax(0.0, fmin(1.0, transition));
            btn.transform = CGAffineTransformMakeScale(scale, scale);
        } else {
            btn.transform = CGAffineTransformIdentity;
        }
    }
}

%end

%end

%group DisplayViewGroup

@interface _ASDisplayView : UIView
@end

%hook _ASDisplayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *btn = [self viewWithTag:998833];
    if (btn && !btn.hidden && btn.alpha > 0.05 && btn.userInteractionEnabled) {
        CGPoint btnPoint = [self convertPoint:point toView:btn];
        if ([btn pointInside:btnPoint withEvent:event]) {
            return btn;
        }
    }
    return %orig;
}

%end

%end

%group InstantVideoGroup

@interface ChatMessageInteractiveInstantVideoNode : ASDisplayNode
@end

%hook ChatMessageInteractiveInstantVideoNode

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [(ASDisplayNode *)self view];
    UIView *btn = [v viewWithTag:998833];
    if (btn && !btn.hidden && btn.alpha > 0.05 && btn.userInteractionEnabled) {
        CGPoint btnPoint = [v convertPoint:point toView:btn];
        if ([btn pointInside:btnPoint withEvent:event]) {
            return btn;
        }
    }
    return %orig;
}

%end

%end

%group TapGestureGroup

@interface TapLongTapOrDoubleTapGestureRecognizer : UIGestureRecognizer
@end

%hook TapLongTapOrDoubleTapGestureRecognizer

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UIGestureRecognizer *rec = (UIGestureRecognizer *)self;
    UITouch *touch = [touches anyObject];
    UIView *recView = rec.view;
    if (touch && recView) {
        CGPoint loc = [touch locationInView:recView];
        UIView *btn = [recView viewWithTag:998833] ?: [recView viewWithTag:998811];
        if (btn && !btn.hidden && btn.alpha > 0.05) {
            CGPoint btnLoc = [recView convertPoint:loc toView:btn];
            if ([btn pointInside:btnLoc withEvent:event]) {
                rec.state = UIGestureRecognizerStateFailed;
                return;
            }
        }
    }
    %orig;
}

%end

%end

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [MediaSaver attachToController:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [MediaSaver detachFromController:self animated:animated];
}

%end

static Class findClassSubstr(const char *suffix) {
    int numClasses = objc_getClassList(NULL, 0);
    if (numClasses > 0) {
        Class *classes = (Class *)malloc(sizeof(Class) * numClasses);
        if (!classes) return Nil;
        numClasses = objc_getClassList(classes, numClasses);
        for (int i = 0; i < numClasses; i++) {
            const char *name = class_getName(classes[i]);
            if (name && strstr(name, suffix) != NULL) {
                Class found = classes[i];
                free(classes);
                return found;
            }
        }
        free(classes);
    }
    return Nil;
}

__attribute__((constructor))
static void hook() {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kDisableForwardRestriction: @YES,
        kAntiSelfDestruct: @YES,
        kAntiRevoke: @YES,
        kAntiAutoDelete: @YES,
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"LeadMessageDeletedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        (void)note;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            refreshDeletedBadgesInView(w);
        }
    }];

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
	 	%init(
		    TabBarNode = objc_getClass("TabBarUI.TabBarNode"),
            PeerInfoScreenItemNode = objc_getClass("PeerInfoScreen.PeerInfoScreenItemNode")
		);

        Class phoneEntryClass = objc_getClass("AuthorizationUI.AuthorizationSequencePhoneEntryControllerNode");
        if (!phoneEntryClass) {
            phoneEntryClass = objc_getClass("_TtC15AuthorizationUI45AuthorizationSequencePhoneEntryControllerNode");
        }
        if (!phoneEntryClass) {
            phoneEntryClass = findClassSubstr("AuthorizationSequencePhoneEntryControllerNode");
        }

        if (phoneEntryClass) {
            %init(LoginQRGroup, AuthorizationSequencePhoneEntryControllerNode = phoneEntryClass);
        }

        Class galleryNodeClass = objc_getClass("GalleryUI.GalleryControllerNode");
        if (!galleryNodeClass) {
            galleryNodeClass = objc_getClass("_TtC9GalleryUI21GalleryControllerNode");
        }
        if (!galleryNodeClass) {
            galleryNodeClass = findClassSubstr("GalleryControllerNode");
        }
        if (galleryNodeClass) {
            %init(GalleryNodeGroup, GalleryControllerNode = galleryNodeClass);
        }

        Class displayViewClass = objc_getClass("_ASDisplayView");
        if (!displayViewClass) {
            displayViewClass = findClassSubstr("_ASDisplayView");
        }
        if (displayViewClass) {
            %init(DisplayViewGroup, _ASDisplayView = displayViewClass);
        }

        Class instantVideoClass = objc_getClass("ChatMessageInteractiveInstantVideoNode.ChatMessageInteractiveInstantVideoNode");
        if (!instantVideoClass) {
            instantVideoClass = objc_getClass("_TtC41ChatMessageInteractiveInstantVideoNode41ChatMessageInteractiveInstantVideoNode");
        }
        if (!instantVideoClass) {
            instantVideoClass = findClassSubstr("ChatMessageInteractiveInstantVideoNode");
        }
        if (instantVideoClass) {
            %init(InstantVideoGroup, ChatMessageInteractiveInstantVideoNode = instantVideoClass);
        }

        Class tapGestureClass = objc_getClass("Display.TapLongTapOrDoubleTapGestureRecognizer");
        if (!tapGestureClass) {
            tapGestureClass = objc_getClass("_TtC7Display39TapLongTapOrDoubleTapGestureRecognizer");
        }
        if (!tapGestureClass) {
            tapGestureClass = findClassSubstr("TapLongTapOrDoubleTapGestureRecognizer");
        }
        if (tapGestureClass) {
            %init(TapGestureGroup, TapLongTapOrDoubleTapGestureRecognizer = tapGestureClass);
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [LeadDownloadBoost install];

            UIWindow *window = UIApplication.sharedApplication.keyWindow;
            if (window) {
                if (!gestureHandler) {
                    gestureHandler = [[ThreeFingerGestureHandler alloc] init];
                }

                UILongPressGestureRecognizer *threeFingerLongPress = [[UILongPressGestureRecognizer alloc]
                    initWithTarget:gestureHandler
                    action:@selector(handleThreeFingerLongPress:)];
                threeFingerLongPress.numberOfTouchesRequired = 3;
                threeFingerLongPress.minimumPressDuration = 0.5;

                [window addGestureRecognizer:threeFingerLongPress];
            }
        });
	});
}
