#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Headers.h"
#import "../Headers.h"
#import "MediaSaver.h"

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readwrite) CGRect frame;
@property (atomic, assign, readonly) CGRect bounds;
@property (atomic, assign, readonly) UIView *view;
@property (atomic, assign, readonly) BOOL isNodeLoaded;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, assign, readonly) ASDisplayNode *supernode;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPressGesture;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;
- (void)didLoad;
- (void)layout;
- (void)layoutDidFinish;
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

static ASDisplayNode *findPrimaryContentNode(ASDisplayNode *node) {
    if (!node) return nil;
    
    @try {
        id bg = [node valueForKey:@"backgroundNode"];
        if (bg && [bg isKindOfClass:NSClassFromString(@"ASDisplayNode")]) {
            return (ASDisplayNode *)bg;
        }
    } @catch (NSException *e) {}
    
    NSMutableArray<ASDisplayNode *> *queue = [NSMutableArray arrayWithObject:node];
    ASDisplayNode *mediaNode = nil;
    while (queue.count > 0) {
        ASDisplayNode *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        
        NSString *cls = NSStringFromClass([cur class]);
        if ([cls containsString:@"ChatMessageBackground"]) {
            return cur;
        }
        if (!mediaNode && ([cls containsString:@"TransformImageNode"] ||
                           [cls containsString:@"InstantVideo"] ||
                           [cls containsString:@"VideoNode"] ||
                           [cls containsString:@"OverlayInstantVideoNode"])) {
            mediaNode = cur;
        }
        
        for (ASDisplayNode *sub in cur.subnodes) {
            [queue addObject:sub];
        }
    }
    return mediaNode;
}

static CGRect getFrameOfSubnodeInAncestor(ASDisplayNode *child, ASDisplayNode *ancestor) {
    if (!child || !ancestor) return CGRectZero;
    
    // 1. If views are loaded and attached, try UIKit coordinate conversion
    if (child.isNodeLoaded && ancestor.isNodeLoaded) {
        UIView *cv = child.view;
        UIView *av = ancestor.view;
        if (cv && av) {
            if (cv.window && av.window && cv.window == av.window) {
                CGRect r = [av convertRect:cv.bounds fromView:cv];
                if (r.size.width > 5.0 && r.size.height > 5.0) {
                    return r;
                }
            }
            CGRect r = cv.bounds;
            UIView *cur = cv;
            BOOL reached = NO;
            while (cur && cur != av) {
                r.origin.x += cur.frame.origin.x;
                r.origin.y += cur.frame.origin.y;
                cur = cur.superview;
                if (cur == av) {
                    reached = YES;
                    break;
                }
            }
            if (reached && r.size.width > 5.0 && r.size.height > 5.0) {
                return r;
            }
        }
    }
    
    // 2. Walk ASDisplayNode supernode hierarchy
    CGRect r = child.frame;
    ASDisplayNode *cur = child.supernode;
    BOOL reached = NO;
    while (cur) {
        if (cur == ancestor) {
            reached = YES;
            break;
        }
        CGRect curFrame = cur.frame;
        r.origin.x += curFrame.origin.x;
        r.origin.y += curFrame.origin.y;
        cur = cur.supernode;
    }
    if (reached && r.size.width > 5.0 && r.size.height > 5.0) {
        return r;
    }
    
    if (child.frame.size.width > 5.0 && child.frame.size.height > 5.0) {
        return child.frame;
    }
    
    return CGRectZero;
}

static CGFloat getAttachedDateHeaderInset(ASDisplayNode *node) {
    if (!node) return 0.0;
    
    // 1. Check item.headers on ChatMessageItem
    @try {
        id item = [node valueForKey:@"item"];
        if (item) {
            id headers = [item valueForKey:@"headers"];
            if ([headers isKindOfClass:[NSArray class]] && [(NSArray *)headers count] > 0) {
                for (id h in (NSArray *)headers) {
                    NSString *hCls = NSStringFromClass([h class]);
                    if ([hCls containsString:@"Date"]) {
                        return 34.0;
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    
    // 2. Check attachedHeaderNodes on ListViewItemNode
    @try {
        id headers = [node valueForKey:@"attachedHeaderNodes"];
        if ([headers isKindOfClass:[NSArray class]] && [(NSArray *)headers count] > 0) {
            for (id h in (NSArray *)headers) {
                NSString *hCls = NSStringFromClass([h class]);
                if ([hCls containsString:@"Date"]) {
                    return 34.0;
                }
            }
        }
    } @catch (NSException *e) {}
    
    // 3. Check attachedDateHeaderInset selector
    @try {
        SEL sel = NSSelectorFromString(@"attachedDateHeaderInset");
        if ([node respondsToSelector:sel]) {
            NSMethodSignature *sig = [node methodSignatureForSelector:sel];
            if (sig && strcmp([sig methodReturnType], @encode(CGFloat)) == 0) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:node];
                [inv setSelector:sel];
                [inv invoke];
                CGFloat inset = 0.0;
                [inv getReturnValue:&inset];
                if (inset > 0.0) return inset;
            }
        }
    } @catch (NSException *e) {}
    
    // 4. Check sibling date header in list view
    @try {
        UIView *v = node.isNodeLoaded ? node.view : nil;
        if (v && v.superview) {
            for (UIView *sibling in v.superview.subviews) {
                NSString *sCls = NSStringFromClass([sibling class]);
                if ([sCls containsString:@"ChatMessageDateHeader"] || [sCls containsString:@"DateHeader"]) {
                    if (fabs(CGRectGetMaxY(sibling.frame) - CGRectGetMinY(v.frame)) < 45.0 ||
                        fabs(CGRectGetMinY(sibling.frame) - CGRectGetMinY(v.frame)) < 45.0) {
                        return 34.0;
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    
    return 0.0;
}

static CGRect getContentFrameOfNode(ASDisplayNode *node) {
    if (!node) return CGRectZero;
    
    CGFloat topInset = getAttachedDateHeaderInset(node);
    
    // 1. Try finding primary content node (ChatMessageBackground, image/video node)
    ASDisplayNode *target = findPrimaryContentNode(node);
    if (target) {
        CGRect r = getFrameOfSubnodeInAncestor(target, node);
        if (r.size.width > 10.0 && r.size.height > 10.0) {
            if (topInset > 0.0 && r.origin.y < topInset * 0.7) {
                r.origin.y += topInset;
            }
            return r;
        }
    }
    
    // 2. Try contentFrame selector
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
            if (rect.size.width > 10.0 && rect.size.height > 10.0) {
                if (topInset > 0.0 && rect.origin.y < topInset * 0.7) {
                    rect.origin.y += topInset;
                }
                return rect;
            }
        }
    }
    
    // 3. Fallback to node.bounds adjusted for any attached date header
    CGRect b = node.bounds;
    if (topInset > 0.0 && b.size.height > topInset + 20.0) {
        b.origin.y += topInset;
        b.size.height -= topInset;
    }
    return b;
}

static BOOL isMainMessageNode(ASDisplayNode *node) {
    if (!node) return NO;
    NSString *className = NSStringFromClass([node class]);
    if (![className containsString:@"ChatMessage"]) return NO;
    if ([className containsString:@"Content"]) return NO;
    if ([className containsString:@"Button"]) return NO;
    if ([className containsString:@"Accessory"]) return NO;
    if ([className containsString:@"AuthorContext"]) return NO;
    if ([className containsString:@"TodoItemNode"]) return NO;
    if ([className containsString:@"BubbleItemNode"] || [className containsString:@"ChatMessageItemView"] || [className containsString:@"AnimatedStickerItemNode"] || [className containsString:@"StickerItemNode"] || [className containsString:@"InstantVideoItemNode"]) {
        return YES;
    }
    return NO;
}

static BOOL doesNodeHaveMedia(ASDisplayNode *node) {
    if (!node) return NO;
    NSString *className = NSStringFromClass([node class]);
    if ([className containsString:@"Media"] || [className containsString:@"InstantVideo"] || [className containsString:@"Sticker"]) {
        return YES;
    }
    @try {
        id contentNodes = [node valueForKey:@"contentNodes"];
        if ([contentNodes isKindOfClass:[NSArray class]]) {
            for (id subNode in (NSArray *)contentNodes) {
                NSString *subCls = NSStringFromClass([subNode class]);
                if ([subCls containsString:@"Media"] || [subCls containsString:@"File"] || [subCls containsString:@"InstantVideo"] || [subCls containsString:@"Image"] || [subCls containsString:@"Poll"]) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

static void cleanRogueBadges(UIView *view, UIView *keepDel, UIView *keepEdit) {
    if (!view) return;
    for (UIView *sub in [view.subviews copy]) {
        if (sub.tag == 998855 && sub != keepDel) {
            [sub removeFromSuperview];
        } else if (sub.tag == 998856 && sub != keepEdit) {
            [sub removeFromSuperview];
        } else {
            cleanRogueBadges(sub, keepDel, keepEdit);
        }
    }
}

static NSString *getNodeText(ASDisplayNode *node) {
    if (!node || !node.isNodeLoaded) return nil;
    UIView *v = node.view;
    if (!v) return nil;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:v];
    while (queue.count > 0) {
        UIView *cur = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (cur.tag == 998855 || cur.tag == 998856 || cur.tag == 998866 || cur.tag == 998811 || cur.tag == 998850) continue;
        if ([cur isKindOfClass:[UILabel class]]) {
            NSString *t = [(UILabel *)cur text];
            if (t.length > 0 && ![t isEqualToString:@"DEL"] && ![t isEqualToString:@"EDT"] && ![t isEqualToString:@"EDITED"]) {
                return t;
            }
        }
        for (UIView *sub in cur.subviews) {
            [queue addObject:sub];
        }
    }
    return nil;
}

static void updateDeletedBadgeForNode(ASDisplayNode *node) {
    if (!node || !node.isNodeLoaded) return;
    if (!isMainMessageNode(node)) return;
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

    // Find direct badges on v and remove any duplicates or rogue badges in subviews
    UILabel *delBadge = nil;
    UILabel *editBadge = nil;
    NSMutableArray<UIView *> *extraBadges = [NSMutableArray array];
    for (UIView *sub in v.subviews) {
        if (sub.tag == 998855) {
            if (!delBadge && [sub isKindOfClass:[UILabel class]]) {
                delBadge = (UILabel *)sub;
            } else {
                [extraBadges addObject:sub];
            }
        } else if (sub.tag == 998856) {
            if (!editBadge && [sub isKindOfClass:[UILabel class]]) {
                editBadge = (UILabel *)sub;
            } else {
                [extraBadges addObject:sub];
            }
        }
    }
    for (UIView *extra in extraBadges) {
        [extra removeFromSuperview];
    }
    cleanRogueBadges(v, delBadge, editBadge);

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
        editBadge.hidden = NO;
        if (msgId) {
            objc_setAssociatedObject(editBadge, "TweakBadgeMsgId", msgId, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(editBadge, "TweakBadgeNode", node, OBJC_ASSOCIATION_ASSIGN);
    } else {
        if (editBadge) editBadge.hidden = YES;
    }

    CGRect bFrame = getContentFrameOfNode(node);
    CGFloat badgeHeight = 13.5;

    CGFloat rowWidth = node.bounds.size.width;
    if (rowWidth < 50.0 && v) {
        rowWidth = v.bounds.size.width;
    }
    if (rowWidth < 50.0) {
        rowWidth = [UIScreen mainScreen].bounds.size.width;
    }

    CGFloat maxX = rowWidth - 5.0;
    CGFloat minX = 5.0;

    CGFloat spaceOnRight = rowWidth - CGRectGetMaxX(bFrame);
    BOOL hasPlentyOfSpaceOnRight = (spaceOnRight >= 85.0);

    BOOL hasMedia = doesNodeHaveMedia(node);
    BOOL isMultiLine = hasMedia || (bFrame.size.height > 55.0);

    // Check single-line crowding: only if crowded on the right (not plenty of space) and text is long (>= 34 chars)
    BOOL isSingleLineCrowded = NO;
    if (!isMultiLine && isDel && isEdit && !hasPlentyOfSpaceOnRight) {
        NSString *nodeText = nil;
        if (msgId) {
            nodeText = (NSString *)[NSClassFromString(@"TLParser") getOriginalTextForId:msgId];
        }
        if (!nodeText) {
            nodeText = getNodeText(node);
        }
        if (nodeText && nodeText.length >= 34) {
            isSingleLineCrowded = YES;
        }
    }

    // Stacked mode applies when both badges exist AND space is tight:
    // (multi-line without plenty of space on right, OR crowded single-line)
    BOOL shouldStack = (isDel && isEdit) && (!hasPlentyOfSpaceOnRight && (isMultiLine || isSingleLineCrowded));

    // Edit badge text: EDT when stacked or multi-line without space; EDITED on uncrowded or when plenty of space
    NSString *editText = (shouldStack || (!hasPlentyOfSpaceOnRight && isMultiLine)) ? @"EDT" : @"EDITED";
    if (editBadge) {
        editBadge.text = editText;
    }

    UIFont *font = [UIFont systemFontOfSize:8.5 weight:UIFontWeightBold];
    CGSize delSize = [@"DEL" sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat delW = MAX(delSize.width + 8.0, 26.0);

    CGSize editSize = [editText sizeWithAttributes:@{NSFontAttributeName: font}];
    CGFloat editW = MAX(editSize.width + 8.0, 26.0);

    CGFloat centerY = CGRectGetMidY(bFrame);

    if (shouldStack) {
        // Stacked vertically: DEL on top, EDT on bottom, centered vertically on message bubble
        CGFloat stackGap = 2.0;
        CGFloat totalHeight = badgeHeight * 2.0 + stackGap;
        CGFloat startY = centerY - totalHeight / 2.0;

        delBadge.layer.cornerRadius = badgeHeight / 2.0;
        editBadge.layer.cornerRadius = badgeHeight / 2.0;

        CGFloat delX = maxX - delW;
        if (delX < minX) delX = minX;
        delBadge.frame = CGRectMake(delX, startY, delW, badgeHeight);

        CGFloat editX = maxX - editW;
        if (editX < minX) editX = minX;
        editBadge.frame = CGRectMake(editX, startY + badgeHeight + stackGap, editW, badgeHeight);

        [v bringSubviewToFront:delBadge];
        [v bringSubviewToFront:editBadge];
    } else {
        CGFloat y = centerY - badgeHeight / 2.0;

        if (isDel && isEdit) {
            // Side-by-side on short single-line message
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
            // Single DEL badge, centered vertically
            delBadge.layer.cornerRadius = badgeHeight / 2.0;
            CGFloat x = maxX - delW;
            if (x < minX) x = minX;
            delBadge.frame = CGRectMake(x, y, delW, badgeHeight);
            [v bringSubviewToFront:delBadge];
        } else if (isEdit) {
            // Single EDT/EDITED badge, centered vertically
            editBadge.layer.cornerRadius = badgeHeight / 2.0;
            CGFloat x = maxX - editW;
            if (x < minX) x = minX;
            editBadge.frame = CGRectMake(x, y, editW, badgeHeight);
            [v bringSubviewToFront:editBadge];
        }
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
    } else if (isMainMessageNode(self)) {
        updateDeletedBadgeForNode(self);
    }
}

- (void)layout {
    %orig;
    NSString *className = NSStringFromClass([self class]);
    if ([className containsString:@"InstantVideo"] || [className containsString:@"OverlayInstantVideoNode"]) {
        [MediaSaver attachInstantVideoButtonToNode:self];
    } else if (isMainMessageNode(self)) {
        updateDeletedBadgeForNode(self);
    }
}

- (void)layoutDidFinish {
    %orig;
    if (isMainMessageNode(self)) {
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
    customLog2(@"[Stories] StoryItemSetContainerComponent.View didMoveToWindow: window=%@", view.window);
    if (!view.window) return;
    UIResponder *r = view.nextResponder;
    while (r && ![r isKindOfClass:[UIViewController class]]) {
        r = r.nextResponder;
    }
    if ([r isKindOfClass:[UIViewController class]]) {
        customLog2(@"[Stories] Attaching MediaSaver to %@", NSStringFromClass([r class]));
        [MediaSaver attachToController:(UIViewController *)r];
    }
}

%end

@interface _TtC20StoryContainerScreen20StoryContainerScreen : UIViewController
@end

%hook _TtC20StoryContainerScreen20StoryContainerScreen

- (void)viewDidLoad {
    %orig;
    customLog2(@"[Stories] StoryContainerScreen viewDidLoad");
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    customLog2(@"[Stories] StoryContainerScreen viewWillAppear: animated=%d", animated);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    customLog2(@"[Stories] StoryContainerScreen viewDidAppear: animated=%d", animated);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    customLog2(@"[Stories] StoryContainerScreen viewWillDisappear: animated=%d", animated);
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
- (ASDisplayNode *)asyncdisplaykit_node;
@end

%hook _ASDisplayView

- (void)layoutSubviews {
    %orig;
    ASDisplayNode *node = nil;
    @try {
        if ([self respondsToSelector:@selector(asyncdisplaykit_node)]) {
            node = [(_ASDisplayView *)self asyncdisplaykit_node];
        }
    } @catch (NSException *e) {}
    if (node && isMainMessageNode(node)) {
        updateDeletedBadgeForNode(node);
    }
}

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
