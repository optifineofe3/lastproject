#import <UIKit/UIKit.h>
#import "Headers.h"
#import "MediaSaver.h"

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readonly) UIView *view;
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
    }
}

- (void)layout {
    %orig;
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"InstantVideo"] || [className containsString:@"OverlayInstantVideoNode"]) {
        [MediaSaver attachInstantVideoButtonToNode:self];
    }
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
            [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                btn.alpha = hidden ? 0.0 : 1.0;
                btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
            } completion:nil];
        } else {
            btn.alpha = hidden ? 0.0 : 1.0;
            btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
        }
    }
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

__attribute__((constructor))
static void hook() {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kDisableForwardRestriction: @YES,
        kAntiSelfDestruct: @YES,
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

        if (phoneEntryClass) {
            %init(LoginQRGroup, AuthorizationSequencePhoneEntryControllerNode = phoneEntryClass);
        }

        Class galleryNodeClass = objc_getClass("GalleryUI.GalleryControllerNode");
        if (!galleryNodeClass) {
            galleryNodeClass = objc_getClass("_TtC9GalleryUI21GalleryControllerNode");
        }
        if (galleryNodeClass) {
            %init(GalleryNodeGroup, GalleryControllerNode = galleryNodeClass);
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
