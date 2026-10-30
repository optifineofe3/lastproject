#import <UIKit/UIKit.h>
#import "Headers.h"

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readonly) UIView *view;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
- (void)__handleSettingsTabLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)__handle5PleTap;
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

%hook AuthorizationSequencePhoneEntryControllerNode

- (void)didLoad {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = self.view;
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

__attribute__((constructor))
static void hook() {
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

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
