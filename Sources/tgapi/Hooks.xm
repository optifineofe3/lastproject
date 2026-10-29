#import "Headers.h"
#import <QuartzCore/QuartzCore.h>

#define kChannelsReadHistory -871347913

%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {
	
	// Extract Function id 
	int32_t functionID;
	[payload getBytes:&functionID length:4];
	self.functionID = [NSNumber numberWithInt:functionID];
	
	id(^hooked_block)(NSData *) = ^(NSData *inputData) {
		NSNumber *functionIDNumber = [NSNumber numberWithUnsignedInt:functionID];
		NSData *parsed = [TLParser handleResponse:inputData functionID:functionIDNumber];
		id result;
		if (parsed) {
			result = responseParser(parsed);
		} else {
			result = responseParser(inputData);
		}
		return result;
	};
	
	switch (functionID) {
		case kAccountUpdateOnlineStatus:
		   handleOnlineStatus(self, payload);
		   break;
		case kMessagesSetTypingAction:
		   handleSetTyping(self, payload);
		   break;
		case kMessagesReadHistory:
		   handleMessageReadReceipt(self, payload);
		   break;
		case kStoriesReadStories:
		   handleStoriesReadReceipt(self, payload);
		   break;
		case kGetSponsoredMessages:
		   handleGetSponsoredMessages(self, payload);
		   break;
		case kChannelsReadHistory:
		   handleChannelsReadReceipt(self, payload);
		   break;
		default:
		   break;
	}
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableForwardRestriction]) {
		%orig(payload, metadata, shortMetadata, hooked_block);
	} else {
		%orig(payload, metadata, shortMetadata, responseParser);
	}
}

%end

// Manager which handles requests
%hook MTRequestMessageService

- (void)addRequest:(MTRequest *)request {
    if (request.fakeData) {
        @try {
             if (request.completed) {
                 NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

                 MTRequestResponseInfo *info = [[%c(MTRequestResponseInfo) alloc] initWithNetworkType:1 
					     timestamp:currentTime 
						  duration:0.045
					   ];
						
						id result = request.responseParser(request.fakeData);
						request.completed(result, info, nil);
             }
         } @catch (NSException *exception) {
             customLog2(@"Exception in MTRequestMessageService hook: %@", exception);
         }
        return;
    }
    %orig;
}

%end

// Disable screenshot & screen-recording restriction for protected content
extern void setLayerDisableScreenshots(CALayer *layer, bool disableScreenshots);

%hookf(void, setLayerDisableScreenshots, CALayer *layer, bool disableScreenshots) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableScreenshotRestriction]) {
        %orig(layer, false);
    } else {
        %orig(layer, disableScreenshots);
    }
}

// Disable screen blackout when switching apps / lock screen
%hook WindowCoveringView

- (void)didMoveToWindow {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableScreenBlackout]) {
        ((UIView *)self).hidden = YES;
    }
}

- (void)layoutSubviews {
    %orig;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kDisableScreenBlackout]) {
        ((UIView *)self).hidden = YES;
    }
}

%end

__attribute__((constructor))
static void initTweakHooks() {
    %init(
        WindowCoveringView = objc_getClass("Display.WindowCoveringView")
    );
}
