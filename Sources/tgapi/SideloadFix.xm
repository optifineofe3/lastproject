#import "SideloadFix.h"

static NSString *originalAppName = nil;
static NSString *originalBundleID = nil;
static NSURL *fakeGroupContainerURL = nil;
static NSString *keychainAccessGroup = nil;

static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);
static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef*);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef*);

// Helper function to sanitize keychain query dictionaries
static CFDictionaryRef sanitizedQuery(CFDictionaryRef query) {
    if (!query) return NULL;
    if (!CFDictionaryContainsKey(query, kSecAttrAccessGroup)) {
        return (CFDictionaryRef)CFRetain(query);
    }

    CFMutableDictionaryRef mutableQuery = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
    if (keychainAccessGroup && keychainAccessGroup.length > 0) {
        CFDictionarySetValue(mutableQuery, kSecAttrAccessGroup, (__bridge void*)keychainAccessGroup);
    } else {
        // In sideloaded/LiveContainer environments without entitlements, removing the access group
        // allows the query to fall back to the app's accessible partition rather than throwing -34018
        CFDictionaryRemoveValue(mutableQuery, kSecAttrAccessGroup);
    }
    return mutableQuery;
}

static OSStatus hook_SecItemAdd(CFDictionaryRef attributes, CFTypeRef* result) {
    CFDictionaryRef cleanAttrs = sanitizedQuery(attributes);
    OSStatus status = orig_SecItemAdd(cleanAttrs ? cleanAttrs : attributes, result);
    if (cleanAttrs) CFRelease(cleanAttrs);
    return status;
}

static OSStatus hook_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef* result) {
    CFDictionaryRef cleanQuery = sanitizedQuery(query);
    OSStatus status = orig_SecItemCopyMatching(cleanQuery ? cleanQuery : query, result);
    if (cleanQuery) CFRelease(cleanQuery);
    return status;
}

static OSStatus hook_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    CFDictionaryRef cleanQuery = sanitizedQuery(query);
    CFDictionaryRef cleanAttrs = sanitizedQuery(attributesToUpdate);
    OSStatus status = orig_SecItemUpdate(cleanQuery ? cleanQuery : query, cleanAttrs ? cleanAttrs : attributesToUpdate);
    if (cleanQuery) CFRelease(cleanQuery);
    if (cleanAttrs) CFRelease(cleanAttrs);
    return status;
}

static OSStatus hook_SecItemDelete(CFDictionaryRef query) {
    CFDictionaryRef cleanQuery = sanitizedQuery(query);
    OSStatus status = orig_SecItemDelete(cleanQuery ? cleanQuery : query);
    if (cleanQuery) CFRelease(cleanQuery);
    return status;
}

static void createDirectoryIfNotExists(NSURL* URL) {
    if (!URL) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:URL.path]) {
        [fm createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

static void loadKeychainAccessGroup() {
    NSDictionary* dummyItem = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount : @"dummyItem",
        (__bridge id)kSecAttrService : @"dummyService",
        (__bridge id)kSecReturnAttributes : @YES,
    };

    CFTypeRef result = NULL;
    OSStatus ret = SecItemCopyMatching((__bridge CFDictionaryRef)dummyItem, &result);
    if (ret == -25300 /* errSecItemNotFound */) {
        ret = SecItemAdd((__bridge CFDictionaryRef)dummyItem, &result);
    }

    if (ret == 0 && result) {
        NSDictionary* resultDict = (__bridge id)result;
        keychainAccessGroup = [resultDict[(__bridge id)kSecAttrAccessGroup] copy];
        CFRelease(result);
    }
}

// MARK: - Fake CloudKit Database & Container (Prevents CKException crash in LiveContainer)

@interface FakeCKDatabase : NSObject
@end

@implementation FakeCKDatabase

- (void)fetchRecordWithID:(id)recordID completionHandler:(void (^)(id record, NSError *error))completionHandler {
    if (completionHandler) {
        // Return CKErrorNetworkUnavailable (code 1) so Telegram catches it gracefully
        NSError *err = [NSError errorWithDomain:@"CKErrorDomain" code:1 userInfo:@{NSLocalizedDescriptionKey: @"CloudKit unavailable in container"}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            completionHandler(nil, err);
        });
    }
}

- (void)fetchWithRecordID:(id)recordID completionHandler:(void (^)(id record, NSError *error))completionHandler {
    [self fetchRecordWithID:recordID completionHandler:completionHandler];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    return nil;
}

@end

@interface FakeCKContainer : NSObject
+ (instancetype)sharedFake;
@end

@implementation FakeCKContainer

+ (instancetype)sharedFake {
    static FakeCKContainer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FakeCKContainer alloc] init];
    });
    return instance;
}

- (id)databaseWithDatabaseScope:(long long)databaseScope {
    return [[FakeCKDatabase alloc] init];
}

- (id)databaseWith:(long long)databaseScope {
    return [[FakeCKDatabase alloc] init];
}

- (id)publicCloudDatabase {
    return [[FakeCKDatabase alloc] init];
}

- (id)privateCloudDatabase {
    return [[FakeCKDatabase alloc] init];
}

- (id)sharedCloudDatabase {
    return [[FakeCKDatabase alloc] init];
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    return nil;
}

@end

// MARK: - NSFileManager Swizzling for AppGroup Redirection

@interface NSFileManager (SideloadFixCategory)
- (NSURL *)swizzled_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier;
@end

@implementation NSFileManager (SideloadFixCategory)

- (NSURL *)swizzled_containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier && groupIdentifier.length > 0) {
        if (!fakeGroupContainerURL) {
            fakeGroupContainerURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FakeGroupContainers"] isDirectory:YES];
        }
        NSURL *fakeURL = [fakeGroupContainerURL URLByAppendingPathComponent:groupIdentifier];
        createDirectoryIfNotExists(fakeURL);
        createDirectoryIfNotExists([fakeURL URLByAppendingPathComponent:@"Library"]);
        createDirectoryIfNotExists([fakeURL URLByAppendingPathComponent:@"Library/Caches"]);
        createDirectoryIfNotExists([fakeURL URLByAppendingPathComponent:@"Documents"]);
        return fakeURL;
    }
    return [self swizzled_containerURLForSecurityApplicationGroupIdentifier:groupIdentifier];
}

@end

// MARK: - SideloadFix Initialization

void initSideloadedFixes(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fakeGroupContainerURL = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FakeGroupContainers"] isDirectory:YES];
        createDirectoryIfNotExists(fakeGroupContainerURL);

        loadKeychainAccessGroup();

        // 1. Rebind Keychain functions with fishhook
        rebind_symbols(
            (struct rebinding[]){
                {"SecItemAdd", (void*)hook_SecItemAdd, (void**)&orig_SecItemAdd},
                {"SecItemCopyMatching", (void*)hook_SecItemCopyMatching, (void**)&orig_SecItemCopyMatching},
                {"SecItemUpdate", (void*)hook_SecItemUpdate, (void**)&orig_SecItemUpdate},
                {"SecItemDelete", (void*)hook_SecItemDelete, (void**)&orig_SecItemDelete},
            },
            4
        );

        // 2. Swizzle NSFileManager containerURLForSecurityApplicationGroupIdentifier:
        Method origMethod = class_getInstanceMethod([NSFileManager class], @selector(containerURLForSecurityApplicationGroupIdentifier:));
        Method swizMethod = class_getInstanceMethod([NSFileManager class], @selector(swizzled_containerURLForSecurityApplicationGroupIdentifier:));
        if (origMethod && swizMethod) {
            method_exchangeImplementations(origMethod, swizMethod);
        }

        // 3. Cache original App bundle info
        NSDictionary *infoDictionary = [NSBundle mainBundle].infoDictionary;
        originalBundleID = infoDictionary[@"CFBundleIdentifier"] ?: @"ph.telegra.Telegraph";
        originalAppName = infoDictionary[@"CFBundleDisplayName"] ?: (infoDictionary[@"CFBundleName"] ?: @"Telegram");

        // 4. Hook CKContainer if CloudKit is in runtime
        Class ckClass = objc_getClass("CKContainer");
        if (!ckClass) {
            dlopen("/System/Library/Frameworks/CloudKit.framework/CloudKit", RTLD_NOW);
            ckClass = objc_getClass("CKContainer");
        }
        if (ckClass) {
            Method defaultContainerMethod = class_getClassMethod(ckClass, @selector(defaultContainer));
            if (defaultContainerMethod) {
                method_setImplementation(defaultContainerMethod, imp_implementationWithBlock(^id(id selfClass) {
                    return [FakeCKContainer sharedFake];
                }));
            }
            Method containerWithIdMethod = class_getClassMethod(ckClass, @selector(containerWithIdentifier:));
            if (containerWithIdMethod) {
                method_setImplementation(containerWithIdMethod, imp_implementationWithBlock(^id(id selfClass, id identifier) {
                    return [FakeCKContainer sharedFake];
                }));
            }
        }

        // 5. Hook INPreferences if Intents is in runtime to prevent missing Siri entitlement crash
        Class inPreferencesClass = objc_getClass("INPreferences");
        if (!inPreferencesClass) {
            dlopen("/System/Library/Frameworks/Intents.framework/Intents", RTLD_NOW);
            inPreferencesClass = objc_getClass("INPreferences");
        }
        if (inPreferencesClass) {
            Method authMethod = class_getClassMethod(inPreferencesClass, @selector(siriAuthorizationStatus));
            if (authMethod) {
                method_setImplementation(authMethod, imp_implementationWithBlock(^NSInteger(id selfClass) {
                    return 2; // INSiriAuthorizationStatusDenied
                }));
            }
            Method reqMethod = class_getClassMethod(inPreferencesClass, @selector(requestSiriAuthorization:));
            if (reqMethod) {
                method_setImplementation(reqMethod, imp_implementationWithBlock(^void(id selfClass, void (^handler)(NSInteger)) {
                    if (handler) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            handler(2); // INSiriAuthorizationStatusDenied
                        });
                    }
                }));
            }
            Method langMethod = class_getClassMethod(inPreferencesClass, @selector(siriLanguageCode));
            if (langMethod) {
                method_setImplementation(langMethod, imp_implementationWithBlock(^id(id selfClass) {
                    return @"en-US";
                }));
            }
            SEL verifySel = sel_registerName("_verifyEntitlements");
            Method verifyMethod = class_getInstanceMethod(inPreferencesClass, verifySel);
            if (verifyMethod) {
                method_setImplementation(verifyMethod, imp_implementationWithBlock(^void(id selfInstance) {
                    // Suppress entitlement verification throw
                }));
            }
        }
    });
}

// MARK: - Forward Declarations

@interface BuildConfig : NSObject
- (bool)isSiriEnabled;
- (bool)isICloudEnabled;
+ (NSString *)bundleSeedId;
@end

@interface INPreferences : NSObject
+ (NSInteger)siriAuthorizationStatus;
+ (void)requestSiriAuthorization:(void (^)(NSInteger status))handler;
+ (id)siriLanguageCode;
- (void)_verifyEntitlements;
@end

// MARK: - Logos Hooks

%hook NSBundle

- (NSString *)bundleIdentifier {
    Dl_info info;
    NSArray *address = [NSThread callStackReturnAddresses];
    if (address.count > 2 && dladdr((void *)[address[2] longLongValue], &info) != 0) {
        NSString *path = [NSString stringWithUTF8String:info.dli_fname];
        if ([path hasPrefix:NSBundle.mainBundle.bundlePath] && originalBundleID) {
            return originalBundleID;
        }
    }
    return %orig;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"CFBundleIdentifier"] && originalBundleID) {
        return originalBundleID;
    }
    if (([key isEqualToString:@"CFBundleDisplayName"] || [key isEqualToString:@"CFBundleName"]) && originalAppName) {
        return originalAppName;
    }
    return %orig;
}

%end

// Hook BuildConfig to ensure bundleSeedId never returns nil, and disable Siri & iCloud which lack sideload entitlements
%hook BuildConfig

- (bool)isSiriEnabled {
    return false;
}

- (bool)isICloudEnabled {
    return false;
}

+ (NSString *)bundleSeedId {
    NSString *orig = %orig;
    if (orig && orig.length > 0) {
        return orig;
    }
    if (keychainAccessGroup && keychainAccessGroup.length > 0) {
        NSArray *components = [keychainAccessGroup componentsSeparatedByString:@"."];
        if (components.count > 0 && [components[0] length] > 0) {
            return components[0];
        }
    }
    return @"1234567890";
}

%end

// Hook INPreferences to prevent NSInternalInconsistencyException when com.apple.developer.siri entitlement is missing
%hook INPreferences

+ (NSInteger)siriAuthorizationStatus {
    return 2; // INSiriAuthorizationStatusDenied
}

+ (void)requestSiriAuthorization:(void (^)(NSInteger status))handler {
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(2);
        });
    }
}

+ (id)siriLanguageCode {
    return @"en-US";
}

- (void)_verifyEntitlements {
}

- (instancetype)init {
    return self;
}

%end

%ctor {
    initSideloadedFixes();
    %init;
}
