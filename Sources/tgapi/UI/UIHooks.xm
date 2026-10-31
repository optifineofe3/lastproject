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

    // Attach single-tap recognizer to message node for showing edit history on tap
    if (![v viewWithTag:998850]) {
        UIView *marker = [[UIView alloc] initWithFrame:CGRectZero];
        marker.tag = 998850;
        marker.hidden = YES;
        [v addSubview:marker];

        UITapGestureRecognizer *bubbleTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleBubbleTap:)];
        bubbleTap.cancelsTouchesInView = NO;
        bubbleTap.delegate = (id<UIGestureRecognizerDelegate>)[MediaSaver shared];
        [v addGestureRecognizer:bubbleTap];
    }
    objc_setAssociatedObject(v, "TweakMessageNode", node, OBJC_ASSOCIATION_ASSIGN);

    NSNumber *msgId = [NSClassFromString(@"TLParser") getMessageIdFromNode:node];
    BOOL isDel = (msgId != nil && [NSClassFromString(@"TLParser") isDeleted:msgId]);
    BOOL isEdit = [NSClassFromString(@"TLParser") isNodeEdited:node];

    UILabel *delBadge = (UILabel *)[v viewWithTag:998855];
    UILabel *editBadge = (UILabel *)[v viewWithTag:998856];
    UIView *origView = [v viewWithTag:998866];
    if (origView) origView.hidden = YES;

    if (!isDel && !isEdit) {
        if (delBadge) delBadge.hidden = YES;
        if (editBadge) editBadge.hidden = YES;
        return;
    }

    if (isDel) {
        if (!delBadge) {
            delBadge = [[UILabel alloc] init];
            delBadge.tag = 998855;
            delBadge.textAlignment = NSTextAlignmentCenter;
            delBadge.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
            delBadge.textColor = [UIColor whiteColor];
            delBadge.backgroundColor = [UIColor colorWithRed:0.85 green:0.20 blue:0.20 alpha:0.90];
            delBadge.layer.masksToBounds = YES;
            delBadge.layer.zPosition = 1000;
            delBadge.userInteractionEnabled = NO;
            [v addSubview:delBadge];
        }
        delBadge.text = @"DEL";
        delBadge.hidden = NO;
        if (msgId) {
            objc_setAssociatedObject(delBadge, "TweakBadgeMsgId", msgId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else {
        if (delBadge) delBadge.hidden = YES;
    }

    if (isEdit) {
        if (!editBadge) {
            editBadge = [[UILabel alloc] init];
            editBadge.tag = 998856;
            editBadge.textAlignment = NSTextAlignmentCenter;
            editBadge.font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
            editBadge.textColor = [UIColor whiteColor];
            editBadge.backgroundColor = [UIColor colorWithRed:0.18 green:0.52 blue:0.92 alpha:0.90];
            editBadge.layer.masksToBounds = YES;
            editBadge.layer.zPosition = 1000;
            editBadge.userInteractionEnabled = YES;

            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleEditBadgeTap:)];
            [editBadge addGestureRecognizer:tap];

            [v addSubview:editBadge];
        }
        editBadge.text = @"EDITED";
        editBadge.hidden = NO;
        if (msgId) {
            objc_setAssociatedObject(editBadge, "TweakBadgeMsgId", msgId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(editBadge, "TweakBadgeNode", node, OBJC_ASSOCIATION_ASSIGN);
    } else {
        if (editBadge) editBadge.hidden = YES;
    }

    CGRect bFrame = getContentFrameOfNode(node);
    CGFloat badgeHeight = 15.0;
    CGFloat y = CGRectGetMinY(bFrame) + (bFrame.size.height - badgeHeight) / 2.0;

    CGFloat maxX = CGRectGetMaxX(bFrame) - 4.0;
    CGFloat minX = CGRectGetMinX(bFrame) + 2.0;

    UIFont *font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
    CGSize delSize = [@"DEL" sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat delW = MAX(delSize.width + 10.0, 26.0);

    BOOL isLarge = (bFrame.size.height >= 44.0 || bFrame.size.width >= 200.0);
    if (isDel && isEdit && (maxX - minX < 120.0)) {
        isLarge = YES;
    }
    NSString *editText = isLarge ? @"EDT" : @"EDITED";
    if (editBadge) {
        editBadge.text = editText;
    }

    CGSize editSize = [editText sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat editW = MAX(editSize.width + 8.0, isLarge ? 26.0 : 42.0);

    if (isDel && isEdit) {
        delBadge.layer.cornerRadius = badgeHeight / 2.0;
        editBadge.layer.cornerRadius = badgeHeight / 2.0;

        CGFloat editX = maxX - editW;
        if (editX < minX) editX = minX;
        editBadge.frame = CGRectMake(editX, y, editW, badgeHeight);

        CGFloat delX = editX - delW - 3.0;
        if (delX < minX) delX = minX;
        delBadge.frame = CGRectMake(delX, y, delW, badgeHeight);

        [v bringSubviewToFront:delBadge];
        [v bringSubviewToFront:editBadge];
    } else if (isDel) {
        delBadge.layer.cornerRadius = badgeHeight / 2.0;
        CGFloat x = maxX - delW;
        if (x < minX) x = minX;
        delBadge.frame = CGRectMake(x, y, delW, badgeHeight);
        [v bringSubviewToFront:delBadge];
    } else if (isEdit) {
        editBadge.layer.cornerRadius = badgeHeight / 2.0;
        CGFloat x = maxX - editW;
        if (x < minX) x = minX;
        editBadge.frame = CGRectMake(x, y, editW, badgeHeight);
        [v bringSubviewToFront:editBadge];
    }
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

@interface _TtC12TelegramCore12TelegramUser : NSObject
@end

@interface _TtC7Display19SparseContainerView : UIView
@end

@interface _TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View : UIView
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

%hook _TtC12TelegramCore12TelegramUser

- (id)initWithDecoder:(id)decoder {
    id res = %orig(decoder);
    if (res) {
        Ivar ivar = class_getInstanceVariable([res class], "flags");
        if (ivar) {
            ptrdiff_t offset = ivar_getOffset(ivar);
            int32_t *flagsPtr = (int32_t *)((uint8_t *)(__bridge void *)res + offset);
            *flagsPtr |= (1 << 4); // UserInfoFlags.isPremium
        }
    }
    return res;
}

- (BOOL)isPremium {
    return YES;
}

%end

%hook _TtC7Display19SparseContainerView

- (void)setAlpha:(CGFloat)alpha {
    %orig(alpha);
    
    UIView *parent = self.superview;
    while (parent && ![NSStringFromClass([parent class]) containsString:@"StoryItemSetContainerComponent"]) {
        parent = parent.superview;
    }
    if (parent) {
        UIResponder *r = self.nextResponder;
        while (r && ![r isKindOfClass:[UIViewController class]]) {
            r = r.nextResponder;
        }
        UIViewController *ctrl = (UIViewController *)r;
        UIView *root = (ctrl && ctrl.isViewLoaded) ? ctrl.view : self.window;
        UIView *btn = [root viewWithTag:998811] ?: [self.window viewWithTag:998811];
        if (btn) {
            BOOL hidden = (alpha < 0.1);
            if (hidden && btn.alpha <= 0.05) return;
            if (!hidden && btn.alpha >= 0.95) return;
            
            [UIView animateWithDuration:0.20 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                btn.alpha = hidden ? 0.0 : 1.0;
                btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
            } completion:nil];
        }
    }
}

- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    
    UIView *parent = self.superview;
    while (parent && ![NSStringFromClass([parent class]) containsString:@"StoryItemSetContainerComponent"]) {
        parent = parent.superview;
    }
    if (parent) {
        UIResponder *r = self.nextResponder;
        while (r && ![r isKindOfClass:[UIViewController class]]) {
            r = r.nextResponder;
        }
        UIViewController *ctrl = (UIViewController *)r;
        UIView *root = (ctrl && ctrl.isViewLoaded) ? ctrl.view : self.window;
        UIView *btn = [root viewWithTag:998811] ?: [self.window viewWithTag:998811];
        if (btn) {
            if (hidden && btn.alpha <= 0.05) return;
            if (!hidden && btn.alpha >= 0.95) return;
            
            [UIView animateWithDuration:0.20 delay:0.0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
                btn.alpha = hidden ? 0.0 : 1.0;
                btn.transform = hidden ? CGAffineTransformMakeScale(0.85, 0.85) : CGAffineTransformIdentity;
            } completion:nil];
        }
    }
}

%end

%hook _TtCC20StoryContainerScreen32StoryItemSetContainerComponent4View

- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    if (!view.window) return;
    UIResponder *r = view.nextResponder;
    while (r && ![r isKindOfClass:[UIViewController class]]) {
        r = r.nextResponder;
    }
    if ([r isKindOfClass:[UIViewController class]]) {
        [MediaSaver attachToController:(UIViewController *)r];
    }
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
        UIView *btn = [recView viewWithTag:998833] ?: ([recView viewWithTag:998811] ?: ([recView viewWithTag:998855] ?: [recView viewWithTag:998866]));
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

%group SecretMediaGroup

@interface SecretMediaPreviewControllerNode : ASDisplayNode
@end

%hook SecretMediaPreviewControllerNode

- (void)didLoad {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiSelfDestruct]) {
        UIView *v = [(ASDisplayNode *)self view];
        if (v) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                for (UIView *sub in v.subviews) {
                    if ([NSStringFromClass([sub class]) containsString:@"RadialStatus"]) {
                        sub.hidden = YES;
                    }
                }
            });
        }
    }
}

- (void)layout {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kAntiSelfDestruct]) {
        UIView *v = [(ASDisplayNode *)self view];
        if (v) {
            for (UIView *sub in v.subviews) {
                if ([NSStringFromClass([sub class]) containsString:@"RadialStatus"]) {
                    sub.hidden = YES;
                }
            }
        }
    }
}

%end

%end

__attribute__((constructor))
static void hook() {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kDisableForwardRestriction: @YES,
        kAntiSelfDestruct: @YES,
        kAntiRevoke: @YES,
        kAntiAutoDelete: @YES,
        kAntiEdit: @YES,
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TweakMessageDeletedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        (void)note;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            refreshDeletedBadgesInView(w);
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"LeadMessageDeletedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        (void)note;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            refreshDeletedBadgesInView(w);
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TweakMessageEditedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        (void)note;
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            refreshDeletedBadgesInView(w);
        }
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"LeadMessageEditedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
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

        Class secretMediaNodeClass = objc_getClass("GalleryUI.SecretMediaPreviewControllerNode");
        if (!secretMediaNodeClass) {
            secretMediaNodeClass = findClassSubstr("SecretMediaPreviewControllerNode");
        }
        if (secretMediaNodeClass) {
            %init(SecretMediaGroup, SecretMediaPreviewControllerNode = secretMediaNodeClass);
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
