#import "Headers.h"

bool shouldFixFilePicker() {
	return [[NSUserDefaults standardUserDefaults] boolForKey:FILE_PICKER_FIX_KEY];
}

%hook LegacyMediaPickerDocumentViewController 

- (id)initForOpeningContentTypes:(id)types  asCopy:(BOOL)copy {
	if (!shouldFixFilePicker()) {
		return %orig;
	}
	
	return %orig(types, YES);
}

- (id)initWithDocumentTypes:(id)types  inMode:(NSUInteger)mode {
	if (!shouldFixFilePicker()) {
		return %orig;
	}
	
	return %orig(types, 0); // Copy Mode
}

%end

%hook LegacyMediaPickerUIICloudFileController

- (void)documentPicker:(id)picker didPickDocumentAtURL:(NSURL *)docUrl {
	
	if (!shouldFixFilePicker()) {
		%orig;
		return;
	}
		
    if (!docUrl) return;
    
    NSURL *url = docUrl;
    
    NSString *customFolderName = [NSString stringWithFormat:@"choco-%@", [[NSUUID UUID] UUIDString]];
	NSString *uglyHackPath = [NSTemporaryDirectory() stringByAppendingPathComponent:FILE_PICKER_PATH];
	NSString *ourPath = [uglyHackPath stringByAppendingPathComponent:customFolderName];
		
    
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:ourPath]) {
        [manager createDirectoryAtPath:ourPath
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];
    }
    
    NSString *fileName = [url lastPathComponent];
    NSString *destinationPath = [ourPath stringByAppendingPathComponent:fileName];
    NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
    
    [manager moveItemAtURL:url toURL:destinationURL error:nil];
    
    %orig(picker, destinationURL);
}

- (void)documentPicker:(id)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
	if (!shouldFixFilePicker()) {
		%orig;
		return;
	}
	
    NSMutableArray *newURLs = [NSMutableArray array];
	
    if (urls.count > 0) {
        NSString *customFolderName = [NSString stringWithFormat:@"choco-%@", [[NSUUID UUID] UUIDString]];
        NSString *uglyHackPath = [NSTemporaryDirectory() stringByAppendingPathComponent:FILE_PICKER_PATH];
		NSString *ourPath = [uglyHackPath stringByAppendingPathComponent:customFolderName];
        
        NSFileManager *manager = [NSFileManager defaultManager];
        if (![manager fileExistsAtPath:ourPath]) {
            [manager createDirectoryAtPath:ourPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
        }

        for (NSURL *url in urls) {
            NSString *fileName = [url lastPathComponent];
            NSString *destinationPath = [ourPath stringByAppendingPathComponent:fileName];
            NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
			
            [manager moveItemAtURL:url toURL:destinationURL error:nil];
            [newURLs addObject:destinationURL];
        }
    }
	
    %orig(picker, newURLs);
}

%end


%hook NSURL

- (BOOL)startAccessingSecurityScopedResource {
	if (!shouldFixFilePicker()) {
		return %orig;
	}
		
    if ([self.path containsString:FILE_PICKER_PATH]) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if ([fm fileExistsAtPath:self.path]) {
            return YES;
        } else {
            return NO;
        }
    }
    return %orig;
}

%end

__attribute__((constructor))
static void initFileHooks() {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),	^{
		Class DocumentPickerViewController = objc_getClass("_TtC19LegacyMediaPickerUIP33_64C09C3310C8117D77D0819BBA77FD8A28DocumentPickerViewController");
		Class LegacyICloudFileController = objc_getClass("_TtC19LegacyMediaPickerUIP33_64C09C3310C8117D77D0819BBA77FD8A26LegacyICloudFileController");
		
		if (!DocumentPickerViewController || !LegacyICloudFileController) {
			int numClasses = objc_getClassList(NULL, 0);
			if (numClasses > 0) {
				Class *classes = (__unsafe_unretained Class *)malloc(sizeof(Class) * numClasses);
				if (classes) {
					numClasses = objc_getClassList(classes, numClasses);
					for (int i = 0; i < numClasses; i++) {
						Class cls = classes[i];
						const char *name = class_getName(cls);
						if (name && strstr(name, "LegacyMediaPickerUI") != NULL) {
							if (!DocumentPickerViewController && strstr(name, "DocumentPickerViewController") != NULL) {
								DocumentPickerViewController = cls;
							} else if (!LegacyICloudFileController && strstr(name, "LegacyICloudFileController") != NULL) {
								LegacyICloudFileController = cls;
							}
						}
						if (DocumentPickerViewController && LegacyICloudFileController) break;
					}
					free(classes);
				}
			}
		}
		
		if (DocumentPickerViewController && LegacyICloudFileController) {
			%init(
				LegacyMediaPickerDocumentViewController = DocumentPickerViewController,
				LegacyMediaPickerUIICloudFileController = LegacyICloudFileController
			);
		} else {
			customLog2(@"Failed to find required classes.");
		}
	});
}