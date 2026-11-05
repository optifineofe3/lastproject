#import <UIKit/UIKit.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#import "Headers.h"
#import "../Headers.h"
#import "MediaSaver.h"
#import <os/lock.h>

// Menu Open
@interface ASDisplayNode : NSObject
@property (atomic, assign, readwrite) CGRect frame;
@property (atomic, assign, readonly) CGRect bounds;
@property (atomic, assign, readonly) UIView *view;
@property (atomic, assign, readonly) BOOL isNodeLoaded;
@property (atomic, copy, readonly) NSArray *subnodes;
@property (atomic, assign, readonly) ASDisplayNode *supernode;
@property (atomic, copy, readwrite) NSString *accessibilityLabel;
- (void)didLoad;
- (void)layout;
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
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback prepare];
    [feedback impactOccurred];

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
        
        const char *cls = class_getName([cur class]);
        if (cls) {
            if (strstr(cls, "ChatMessageBackground") != NULL) {
                return cur;
            }
            if (!mediaNode && (strstr(cls, "TransformImageNode") != NULL ||
                               strstr(cls, "InstantVideo") != NULL ||
                               strstr(cls, "VideoNode") != NULL ||
                               strstr(cls, "OverlayInstantVideoNode") != NULL)) {
                mediaNode = cur;
            }
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
                    const char *hCls = class_getName([h class]);
                    if (hCls && strstr(hCls, "Date") != NULL) {
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
                const char *hCls = class_getName([h class]);
                if (hCls && strstr(hCls, "Date") != NULL) {
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

static CFMutableSetRef sMainMessageClasses = NULL;
static CFMutableSetRef sNonMessageClasses = NULL;
static os_unfair_lock sClassCacheLock = OS_UNFAIR_LOCK_INIT;

static BOOL isMainMessageNode(ASDisplayNode *node) {
    if (!node) return NO;
    Class cls = [node class];
    if (!cls) return NO;

    os_unfair_lock_lock(&sClassCacheLock);
    if (!sMainMessageClasses) {
        sMainMessageClasses = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
        sNonMessageClasses = CFSetCreateMutable(kCFAllocatorDefault, 0, NULL);
    }
    if (CFSetContainsValue(sMainMessageClasses, (__bridge const void *)cls)) {
        os_unfair_lock_unlock(&sClassCacheLock);
        return YES;
    }
    if (CFSetContainsValue(sNonMessageClasses, (__bridge const void *)cls)) {
        os_unfair_lock_unlock(&sClassCacheLock);
        return NO;
    }
    os_unfair_lock_unlock(&sClassCacheLock);

    const char *name = class_getName(cls);
    BOOL isMain = NO;
    if (name && strstr(name, "ChatMessage") != NULL) {
        if (strstr(name, "Content") == NULL &&
            strstr(name, "Button") == NULL &&
            strstr(name, "Accessory") == NULL &&
            strstr(name, "AuthorContext") == NULL &&
            strstr(name, "TodoItemNode") == NULL) {
            if (strstr(name, "BubbleItemNode") != NULL ||
                strstr(name, "ChatMessageItemView") != NULL ||
                strstr(name, "AnimatedStickerItemNode") != NULL ||
                strstr(name, "StickerItemNode") != NULL ||
                strstr(name, "InstantVideoItemNode") != NULL) {
                isMain = YES;
            }
        }
    }

    os_unfair_lock_lock(&sClassCacheLock);
    if (isMain) {
        CFSetAddValue(sMainMessageClasses, (__bridge const void *)cls);
    } else {
        CFSetAddValue(sNonMessageClasses, (__bridge const void *)cls);
    }
    os_unfair_lock_unlock(&sClassCacheLock);

    return isMain;
}

static BOOL doesNodeHaveMedia(ASDisplayNode *node) {
    if (!node) return NO;
    const char *className = class_getName([node class]);
    if (className && (strstr(className, "Media") != NULL ||
                      strstr(className, "InstantVideo") != NULL ||
                      strstr(className, "Sticker") != NULL)) {
        return YES;
    }
    @try {
        id contentNodes = [node valueForKey:@"contentNodes"];
        if ([contentNodes isKindOfClass:[NSArray class]]) {
            for (id subNode in (NSArray *)contentNodes) {
                const char *subCls = class_getName([subNode class]);
                if (subCls && (strstr(subCls, "Media") != NULL ||
                               strstr(subCls, "File") != NULL ||
                               strstr(subCls, "InstantVideo") != NULL ||
                               strstr(subCls, "Image") != NULL ||
                               strstr(subCls, "Poll") != NULL)) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}
    return NO;
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

static BOOL isNodeOutgoing(ASDisplayNode *node, CGRect bFrame, CGFloat rowWidth) {
    if (!node) return NO;
    
    @try {
        id bgType = [node valueForKey:@"backgroundType"];
        if (bgType) {
            NSString *desc = [[bgType description] lowercaseString];
            if ([desc containsString:@"outgoing"]) return YES;
            if ([desc containsString:@"incoming"]) return NO;
        }
    } @catch (NSException *e) {}
    
    @try {
        id item = [node valueForKey:@"item"];
        if (item) {
            id bgType = [item valueForKey:@"backgroundType"];
            if (bgType) {
                NSString *desc = [[bgType description] lowercaseString];
                if ([desc containsString:@"outgoing"]) return YES;
                if ([desc containsString:@"incoming"]) return NO;
            }
        }
    } @catch (NSException *e) {}
    
    // Geometrical layout check:
    // Outgoing messages are pinned to the right edge (space on left is much larger than space on right).
    // Incoming messages are pinned to the left edge (space on right is much larger than space on left).
    CGFloat spaceOnLeft = bFrame.origin.x;
    CGFloat spaceOnRight = rowWidth - CGRectGetMaxX(bFrame);
    
    return (spaceOnLeft > spaceOnRight);
}

static char kBubbleTapAttachedKey;
static char kTweakBadgeStateKey;

static void updateDeletedBadgeForNode(ASDisplayNode *node) {
    if (![NSThread isMainThread] || !node || !node.isNodeLoaded) return;
    if (!isMainMessageNode(node)) return;
    UIView *v = node.view;
    if (!v) return;

    // Attach single-tap recognizer to message node for showing edit history on tap
    if (!objc_getAssociatedObject(v, &kBubbleTapAttachedKey)) {
        UITapGestureRecognizer *bubbleTap = [[UITapGestureRecognizer alloc] initWithTarget:[MediaSaver shared] action:@selector(handleBubbleTap:)];
        bubbleTap.cancelsTouchesInView = NO;
        bubbleTap.delegate = (id<UIGestureRecognizerDelegate>)[MediaSaver shared];
        [v addGestureRecognizer:bubbleTap];
        objc_setAssociatedObject(v, &kBubbleTapAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Always fetch fresh msgId directly from the node's current model (handles cell reuse correctly)
    NSNumber *msgId = [NSClassFromString(@"TLParser") getMessageIdFromNode:node];
    BOOL isDel = (msgId != nil && [NSClassFromString(@"TLParser") isDeleted:msgId]);
    BOOL isEdit = (msgId != nil && [NSClassFromString(@"TLParser") isNodeEdited:node]);

    // Fast path: if unedited and undeleted, hide existing badges and exit instantly (smooth 120 FPS scrolling)
    uint64_t msgIdVal = msgId ? [msgId unsignedIntValue] : 0;
    uint64_t stateKey = msgIdVal | ((uint64_t)(isDel ? 1 : 0) << 32) | ((uint64_t)(isEdit ? 1 : 0) << 33);
    NSNumber *cachedState = objc_getAssociatedObject(v, &kTweakBadgeStateKey);

    if (!isDel && !isEdit) {
        if (cachedState && [cachedState unsignedLongLongValue] == stateKey) {
            return;
        }
        objc_setAssociatedObject(v, &kTweakBadgeStateKey, @(stateKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *sub in v.subviews) {
            if (sub.tag == 998855 || sub.tag == 998856 || sub.tag == 998866) {
                sub.hidden = YES;
            }
        }
        return;
    }

    // Find direct badges on v and remove any duplicate badges
    UILabel *delBadge = nil;
    UILabel *editBadge = nil;
    NSMutableArray<UIView *> *extraBadges = nil;
    for (UIView *sub in v.subviews) {
        if (sub.tag == 998855) {
            if (!delBadge && [sub isKindOfClass:[UILabel class]]) {
                delBadge = (UILabel *)sub;
            } else {
                if (!extraBadges) extraBadges = [NSMutableArray array];
                [extraBadges addObject:sub];
            }
        } else if (sub.tag == 998856) {
            if (!editBadge && [sub isKindOfClass:[UILabel class]]) {
                editBadge = (UILabel *)sub;
            } else {
                if (!extraBadges) extraBadges = [NSMutableArray array];
                [extraBadges addObject:sub];
            }
        }
    }
    for (UIView *extra in extraBadges) {
        [extra removeFromSuperview];
    }

    UIView *origView = [v viewWithTag:998866];
    if (origView) origView.hidden = YES;

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

    BOOL isOutgoing = isNodeOutgoing(node, bFrame, rowWidth);

    CGFloat availableSpace = isOutgoing ? bFrame.origin.x : (rowWidth - CGRectGetMaxX(bFrame));
    BOOL hasPlentyOfSpace = (availableSpace >= 85.0);

    BOOL hasMedia = doesNodeHaveMedia(node);
    BOOL isMultiLine = hasMedia || (bFrame.size.height > 55.0);

    // Check single-line crowding: only if crowded (not plenty of space) and text is long (>= 34 chars)
    BOOL isSingleLineCrowded = NO;
    if (!isMultiLine && isDel && isEdit && !hasPlentyOfSpace) {
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
    // (multi-line without plenty of space, OR crowded single-line)
    BOOL shouldStack = (isDel && isEdit) && (!hasPlentyOfSpace && (isMultiLine || isSingleLineCrowded));

    // Edit badge text: EDT when stacked or multi-line without space; EDITED on uncrowded or when plenty of space
    NSString *editText = (shouldStack || (!hasPlentyOfSpace && isMultiLine)) ? @"EDT" : @"EDITED";
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

        if (isOutgoing) {
            // OUTGOING: stacked vertically on the LEFT of the row
            CGFloat delX = minX;
            CGFloat editX = minX;
            delBadge.frame = CGRectMake(delX, startY, delW, badgeHeight);
            editBadge.frame = CGRectMake(editX, startY + badgeHeight + stackGap, editW, badgeHeight);
        } else {
            // INCOMING: stacked vertically on the RIGHT of the row
            CGFloat delX = maxX - delW;
            if (delX < minX) delX = minX;
            delBadge.frame = CGRectMake(delX, startY, delW, badgeHeight);

            CGFloat editX = maxX - editW;
            if (editX < minX) editX = minX;
            editBadge.frame = CGRectMake(editX, startY + badgeHeight + stackGap, editW, badgeHeight);
        }

        if (v.subviews.lastObject != editBadge) {
            [v bringSubviewToFront:delBadge];
            [v bringSubviewToFront:editBadge];
        }
    } else {
        CGFloat y = centerY - badgeHeight / 2.0;

        if (isDel && isEdit) {
            // Side-by-side on short single-line message or plenty of space
            delBadge.layer.cornerRadius = badgeHeight / 2.0;
            editBadge.layer.cornerRadius = badgeHeight / 2.0;

            if (isOutgoing) {
                // OUTGOING: side-by-side on the LEFT (DEL then EDIT)
                CGFloat delX = minX;
                CGFloat editX = delX + delW + 3.0;
                delBadge.frame = CGRectMake(delX, y, delW, badgeHeight);
                editBadge.frame = CGRectMake(editX, y, editW, badgeHeight);
            } else {
                // INCOMING: side-by-side on the RIGHT
                CGFloat editX = maxX - editW;
                if (editX < minX) editX = minX;
                editBadge.frame = CGRectMake(editX, y, editW, badgeHeight);

                CGFloat delX = editX - delW - 3.0;
                if (delX < minX) delX = minX;
                delBadge.frame = CGRectMake(delX, y, delW, badgeHeight);
            }

            if (v.subviews.lastObject != editBadge) {
                [v bringSubviewToFront:delBadge];
                [v bringSubviewToFront:editBadge];
            }
        } else if (isDel) {
            // Single DEL badge, centered vertically
            delBadge.layer.cornerRadius = badgeHeight / 2.0;
            if (isOutgoing) {
                // OUTGOING: single DEL on the LEFT
                CGFloat x = minX;
                delBadge.frame = CGRectMake(x, y, delW, badgeHeight);
            } else {
                // INCOMING: single DEL on the RIGHT
                CGFloat x = maxX - delW;
                if (x < minX) x = minX;
                delBadge.frame = CGRectMake(x, y, delW, badgeHeight);
            }
            if (v.subviews.lastObject != delBadge) {
                [v bringSubviewToFront:delBadge];
            }
        } else if (isEdit) {
            // Single EDT/EDITED badge, centered vertically
            editBadge.layer.cornerRadius = badgeHeight / 2.0;
            if (isOutgoing) {
                // OUTGOING: single EDT/EDITED on the LEFT
                CGFloat x = minX;
                editBadge.frame = CGRectMake(x, y, editW, badgeHeight);
            } else {
                // INCOMING: single EDT/EDITED on the RIGHT
                CGFloat x = maxX - editW;
                if (x < minX) x = minX;
                editBadge.frame = CGRectMake(x, y, editW, badgeHeight);
            }
            if (v.subviews.lastObject != editBadge) {
                [v bringSubviewToFront:editBadge];
            }
        }
    }

    objc_setAssociatedObject(v, &kTweakBadgeStateKey, @(stateKey), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void updateVisibleBadgesForChangedIds(NSArray *changedIds) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            updateVisibleBadgesForChangedIds(changedIds);
        });
        return;
    }

    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    if (!window) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
    }
    if (!window && UIApplication.sharedApplication.windows.count > 0) {
        window = UIApplication.sharedApplication.windows.firstObject;
    }
    if (!window) return;

    // Traverse visible subviews in key window and update only message cells matching changedIds
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (v.isHidden || v.alpha < 0.01) continue;

        ASDisplayNode *node = nil;
        if ([v respondsToSelector:@selector(asyncdisplaykit_node)]) {
            node = (ASDisplayNode *)[v asyncdisplaykit_node];
        }
        if (node && isMainMessageNode(node)) {
            NSNumber *mid = [NSClassFromString(@"TLParser") getMessageIdFromNode:node];
            if (mid) {
                BOOL matches = NO;
                if (!changedIds || changedIds.count == 0) {
                    matches = YES;
                } else {
                    for (id cid in changedIds) {
                        if ([cid respondsToSelector:@selector(intValue)] && [cid intValue] == [mid intValue]) {
                            matches = YES;
                            break;
                        }
                    }
                }
                if (matches) {
                    objc_setAssociatedObject(v, &kTweakBadgeStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    updateDeletedBadgeForNode(node);
                }
            }
            continue; // Do not recurse into message node's internal subviews
        }

        for (UIView *sub in v.subviews) {
            [queue addObject:sub];
        }
    }
}

%hook ASDisplayNode

- (void)didLoad {
    %orig;
    const char *className = class_getName([self class]);
    if (className && (strstr(className, "InstantVideo") != NULL || strstr(className, "OverlayInstantVideoNode") != NULL)) {
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
    const char *className = class_getName([self class]);
    if (className && (strstr(className, "InstantVideo") != NULL || strstr(className, "OverlayInstantVideoNode") != NULL)) {
        [MediaSaver attachInstantVideoButtonToNode:self];
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    const char *className = class_getName([self class]);
    if (className && (strstr(className, "InstantVideo") != NULL || strstr(className, "OverlayInstantVideoNode") != NULL)) {
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

static char kTabTapGestureKey;
static char kSettingsLpGestureKey;

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
            UITapGestureRecognizer *tap = objc_getAssociatedObject(child, &kTabTapGestureKey);
			if (!tap) {
				tap = [[UITapGestureRecognizer alloc] initWithTarget:child action:@selector(__handle5PleTap)];
				tap.numberOfTapsRequired = 5;
                objc_setAssociatedObject(child, &kTabTapGestureKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			}

			if (![child.view.gestureRecognizers containsObject:tap]) {
                [child.view addGestureRecognizer:tap];
			}
        }
    }
}

%end

%hook PeerInfoScreenItemNode

- (void)didEnterHierarchy {
    %orig;

    ASDisplayNode *mainNode = self;
    UILongPressGestureRecognizer *lp = objc_getAssociatedObject(mainNode, &kSettingsLpGestureKey);
	if (!lp) {
		lp = [[UILongPressGestureRecognizer alloc] initWithTarget:mainNode action:@selector(__handleSettingsTabLongPress:)];
		lp.minimumPressDuration = 0.5;
        objc_setAssociatedObject(mainNode, &kSettingsLpGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
				if (![mainNode.view.gestureRecognizers containsObject:lp]) {
					[mainNode.view addGestureRecognizer:lp];
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

static UIView *findStoryDownloadButton(UIView *fromView) {
    if (!fromView) return nil;
    UIView *btn = [fromView viewWithTag:998811];
    if (btn) return btn;
    if (fromView.window) {
        btn = [fromView.window viewWithTag:998811];
        if (btn) return btn;
    }
    UIResponder *r = fromView.nextResponder;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)r;
            if (vc.isViewLoaded) {
                btn = [vc.view viewWithTag:998811];
                if (btn) return btn;
            }
        }
        r = r.nextResponder;
    }
    return nil;
}

static void animateOutStoryDownloadButton(UIView *btn, NSTimeInterval duration) {
    if (!btn || btn.alpha <= 0.01) return;
    [UIView animateWithDuration:(duration > 0 ? duration : 0.18)
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        btn.alpha = 0.0;
        btn.transform = CGAffineTransformMakeScale(0.85, 0.85);
    } completion:^(BOOL finished) {
        if (btn.alpha <= 0.05) {
            [btn removeFromSuperview];
        }
    }];
}

%group StoryItemGroup

@interface StoryItemSetContainerComponentView : UIView
@end

%hook StoryItemSetContainerComponentView

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

- (void)closePressed {
    UIView *btn = findStoryDownloadButton((UIView *)self);
    if (btn && btn.alpha > 0.05) {
        animateOutStoryDownloadButton(btn, 0.18);
    }
    %orig;
}

- (void)viewListDismissPanGesture:(UIPanGestureRecognizer *)recognizer {
    %orig;
    
    UIView *btn = findStoryDownloadButton((UIView *)self);
    if (!btn) return;
    
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [recognizer translationInView:(UIView *)self];
        if (translation.y > 0) {
            CGFloat threshold = 150.0;
            CGFloat progress = fmax(0.0, fmin(1.0, translation.y / threshold));
            CGFloat value = 1.0 - progress;
            btn.alpha = value;
            CGFloat scale = 0.85 + 0.15 * value;
            btn.transform = CGAffineTransformMakeScale(scale, scale);
        } else {
            btn.alpha = 1.0;
            btn.transform = CGAffineTransformIdentity;
        }
    } else if (recognizer.state == UIGestureRecognizerStateEnded || recognizer.state == UIGestureRecognizerStateCancelled) {
        CGPoint translation = [recognizer translationInView:(UIView *)self];
        CGPoint velocity = [recognizer velocityInView:(UIView *)self];
        
        BOOL shouldDismiss = (translation.y > 180.0) || (translation.y > 5.0 && velocity.y > 200.0);
        if (shouldDismiss) {
            animateOutStoryDownloadButton(btn, 0.18);
        } else {
            [UIView animateWithDuration:0.22 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                btn.alpha = 1.0;
                btn.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }
}

%end

%end

%group StoryContainerGroup

@interface StoryContainerScreen : UIViewController
@end

%hook StoryContainerScreen

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
    UIViewController *vc = (UIViewController *)self;
    UIView *btn = [vc.view viewWithTag:998811] ?: [vc.view.window viewWithTag:998811];
    if (btn && btn.alpha > 0.05) {
        animateOutStoryDownloadButton(btn, 0.18);
    }
    [MediaSaver detachFromController:vc animated:YES];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(id)completion {
    customLog2(@"[Stories] StoryContainerScreen dismissViewControllerAnimated: animated=%d", flag);
    UIViewController *vc = (UIViewController *)self;
    UIView *btn = [vc.view viewWithTag:998811] ?: [vc.view.window viewWithTag:998811];
    if (btn && btn.alpha > 0.05) {
        animateOutStoryDownloadButton(btn, 0.18);
    }
    %orig;
}

%end

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
    if (![NSThread isMainThread]) return;
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
        UIView *btn = [recView viewWithTag:998833] ?: ([recView viewWithTag:998811] ?: ([recView viewWithTag:998855] ?: ([recView viewWithTag:998856] ?: [recView viewWithTag:998866])));
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

static void initStoryHooks(void) {
    static BOOL initialized = NO;
    if (initialized) return;

    Class storyItemViewClass = objc_getClass("_TtCC20StoryContainerScreen30StoryItemSetContainerComponent4View");
    if (!storyItemViewClass) {
        storyItemViewClass = objc_getClass("StoryContainerScreen.StoryItemSetContainerComponent.View");
    }
    if (!storyItemViewClass) {
        storyItemViewClass = findClassSubstr("StoryItemSetContainerComponent4View");
    }
    if (storyItemViewClass) {
        %init(StoryItemGroup, StoryItemSetContainerComponentView = storyItemViewClass);
    }

    Class storyContainerClass = objc_getClass("_TtC20StoryContainerScreen20StoryContainerScreen");
    if (!storyContainerClass) {
        storyContainerClass = objc_getClass("StoryContainerScreen.StoryContainerScreen");
    }
    if (!storyContainerClass) {
        storyContainerClass = findClassSubstr("StoryContainerScreen");
    }
    if (storyContainerClass) {
        %init(StoryContainerGroup, StoryContainerScreen = storyContainerClass);
    }

    if (storyItemViewClass && storyContainerClass) {
        initialized = YES;
    }
}

__attribute__((constructor))
static void hook() {
    initStoryHooks();
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kDisableForwardRestriction: @YES,
        kAntiSelfDestruct: @YES,
        kAntiRevoke: @YES,
        kAntiAutoDelete: @YES,
        kAntiEdit: @YES,
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"LeadMessageDeletedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray *ids = note.userInfo ? note.userInfo[@"ids"] : nil;
        updateVisibleBadgesForChangedIds(ids);
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TweakMessageDeletedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray *ids = note.userInfo ? note.userInfo[@"ids"] : nil;
        updateVisibleBadgesForChangedIds(ids);
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"LeadMessageEditedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray *ids = note.userInfo ? note.userInfo[@"ids"] : nil;
        updateVisibleBadgesForChangedIds(ids);
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:@"TweakMessageEditedRealtime" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        NSArray *ids = note.userInfo ? note.userInfo[@"ids"] : nil;
        updateVisibleBadgesForChangedIds(ids);
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

        initStoryHooks();

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
