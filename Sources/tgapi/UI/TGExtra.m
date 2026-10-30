#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Icons.h"
#import "Headers.h"

#define TGLoc(key) [TGExtraLocalization localizedStringForKey:(key)]

@interface TGExtra ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSString *cacheSize;
@end

@implementation TGExtra

- (void)viewDidLoad {
	[super viewDidLoad];

	[self setupTableView];
	[self setupIconAsHeader];
	[self setupApplyButton];
	self.title = @"Tweak";

	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeFakeLocation)
                                                 name:@"LeadLocationChanged"
                                               object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeFakeLocation)
                                                 name:@"TweakLocationChanged"
                                               object:nil];
}

- (void)didChangeFakeLocation {
	NSIndexSet *section = [NSIndexSet indexSetWithIndex:4];
	[self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)setupTableView {
	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	self.tableView.delegate = self;
	self.tableView.dataSource = self;
	self.tableView.translatesAutoresizingMaskIntoConstraints = NO;

	[self.view addSubview:self.tableView];

	[NSLayoutConstraint activateConstraints:@[
    	[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
	]];
}

- (void)setupIconAsHeader {
    UIView *logoContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.frame.size.width, 110)];

    UIImageView *iconView = [[UIImageView alloc] init];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:40 weight:UIImageSymbolWeightMedium];
    iconView.image = [UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:config];
    iconView.tintColor = [UIColor systemBlueColor];
    iconView.contentMode = UIViewContentModeCenter;
    iconView.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.12];
    iconView.layer.cornerRadius = 22;
    iconView.clipsToBounds = YES;

    [logoContainer addSubview:iconView];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerYAnchor constraintEqualToAnchor:logoContainer.centerYAnchor],
        [iconView.centerXAnchor constraintEqualToAnchor:logoContainer.centerXAnchor],
        [iconView.widthAnchor constraintEqualToConstant:76],
        [iconView.heightAnchor constraintEqualToConstant:76]
    ]];

    self.tableView.tableHeaderView = logoContainer;
}

- (void)setupApplyButton {
	UIButton *applyChangesButton = [UIButton buttonWithType:UIButtonTypeSystem];
	UIImage *applyImage = [UIImage systemImageNamed:@"checkmark.circle.fill"];
	applyImage = [applyImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	applyChangesButton.tintColor = [UIColor systemBlueColor];
	[applyChangesButton setImage:applyImage forState:UIControlStateNormal];
	[applyChangesButton addTarget:self action:@selector(applyChanges) forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem *applyButtonItem = [[UIBarButtonItem alloc] initWithCustomView:applyChangesButton];
	self.navigationItem.rightBarButtonItems = @[applyButtonItem];
}

- (void)applyChanges {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"APPLY")
                                                                   message:TGLoc(@"APPLY_CHANGES")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
		[[UIApplication sharedApplication] performSelector:@selector(suspend)];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			exit(0);
		});
	}];

    [alert addAction:okAction];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:TGLoc(@"CANCEL")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UIColor *)dynamicColorBW {
    static dispatch_once_t token;
    static UIColor *cached;
    dispatch_once(&token, ^{
        cached = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull trait) {
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return [UIColor whiteColor];
            } else {
                return [UIColor blackColor];
            }
        }];
    });
    return cached;
}

# pragma mark - UITableViewDataSource

typedef NS_ENUM(NSInteger, TABLE_VIEW_SECTIONS) {
    GHOST_MODE = 0,
    READ_RECEIPT = 1,
    MISC = 2,
    FILE_FIXER = 3,
    FAKE_LOCATION = 4,
};

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case GHOST_MODE:
		   return 17;
		case READ_RECEIPT:
		   return 2;
		case MISC:
		   return 8;
		case FILE_FIXER:
		   return 2;
		case FAKE_LOCATION:
		   return 2;
		default:
		   return 0;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
		case GHOST_MODE:
		   return TGLoc(@"GHOST_MODE_SECTION_HEADER");
		case READ_RECEIPT:
		   return TGLoc(@"READ_RECEIPT_SECTION_HEADER");
		case MISC:
		   return TGLoc(@"MISC_SECTION_HEADER");
		case FILE_FIXER:
		   return TGLoc(@"FILE_FIXER_SECTION_HEADER");
		case FAKE_LOCATION:
		   return TGLoc(@"FAKE_LOCATION_SECTION_HEADER");
		default:
		   return nil;
	}
	return nil;
}

- (UITableViewCell *)switchCellFromTableView:(UITableView *)tableView {
	UITableViewCell *switchCell = [tableView dequeueReusableCellWithIdentifier:@"switchCell"];
	if (!switchCell) {
		switchCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"switchCell"];
	}
	return switchCell;
}

- (UITableViewCell *)normalCellFromTableView:(UITableView *)tableView {
	UITableViewCell *normalCell = [tableView dequeueReusableCellWithIdentifier:@"normalCell"];
	if (!normalCell) {
		normalCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"normalCell"];
	}
	return normalCell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;

	if (indexPath.section == 0) { // Ghost Mode
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		switch (indexPath.row) {
			case 0:
			    cell.textLabel.text = TGLoc(@"DISABLE_ONLINE_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_ONLINE_STATUS_SUBTITLE");
				break;
			case 1:
			    cell.textLabel.text = TGLoc(@"DISABLE_TYPING_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_TYPING_STATUS_SUBTITLE");
				break;
			case 2:
			    cell.textLabel.text = TGLoc(@"DISABLE_RECORDING_VIDEO_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE");
				break;
			case 3:
			    cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_VIDEO_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE");
				break;
			case 4:
			    cell.textLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE");
				break;
			case 5:
			    cell.textLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE");
				break;
			case 6:
			    cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_PHOTO_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE");
				break;
			case 7:
			    cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_FILE_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE");
				break;
			case 8:
			    cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_LOCATION_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE");
				break;
			case 9:
			    cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_CONTACT_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_CONTACT_SUBTITLE");
				break;
			case 10:
			    cell.textLabel.text = TGLoc(@"DISABLE_PLAYING_GAME_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_PLAYING_GAME_STATUS_SUBTITLE");
				break;
			case 11:
			    cell.textLabel.text = TGLoc(@"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE");
				break;
			case 12:
			    cell.textLabel.text = TGLoc(@"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE");
				cell.detailTextLabel.text = nil;
				break;
			case 13:
			    cell.textLabel.text = TGLoc(@"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE");
				break;
			case 14:
			    cell.textLabel.text = TGLoc(@"DISABLE_CHOOSING_STICKER_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE");
				break;
			case 15:
			    cell.textLabel.text = TGLoc(@"DISABLE_EMOJI_INTERACTION_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE");
				break;
			case 16:
			    cell.textLabel.text = TGLoc(@"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE");
				cell.detailTextLabel.text = TGLoc(@"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE");
				break;
			default:
			    break;
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section * 1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}
	else if (indexPath.section == 1) { // Read Receipt
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		if (indexPath.row == 0) {
			cell.textLabel.text = TGLoc(@"DISABLE_MESSAGE_READ_RECEIPT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_MESSAGE_READ_RECEIPT_SUBTITLE");
		}
		else if (indexPath.row == 1) {
			cell.textLabel.text = TGLoc(@"DISABLE_STORY_READ_RECEIPT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_STORY_READ_RECEIPT_SUBTITLE");
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section * 1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}
	else if (indexPath.section == 2) { // MISC
		cell = [self switchCellFromTableView:tableView];
		cell.imageView.image = nil;

		if (indexPath.row == 0) {
			cell.imageView.image = [UIImage systemImageNamed:@"nosign"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"DISABLE_ALL_ADS_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DISABLE_ALL_ADS_SUBTITLE");
		}
		else if (indexPath.row == 1) {
			cell.imageView.image = [UIImage systemImageNamed:@"lock.open.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ENABLE_SAVING_PROTECTED_CONTENT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ENABLE_SAVING_PROTECTED_CONTENT_SUBTITLE");
		}
		else if (indexPath.row == 2) {
			cell.imageView.image = [UIImage systemImageNamed:@"trash.slash.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ANTI_REVOKE_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ANTI_REVOKE_SUBTITLE");
		}
		else if (indexPath.row == 3) {
			cell.imageView.image = [UIImage systemImageNamed:@"clock.arrow.circlepath"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ANTI_AUTO_DELETE_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ANTI_AUTO_DELETE_SUBTITLE");
		}
		else if (indexPath.row == 4) {
			cell.imageView.image = [UIImage systemImageNamed:@"camera.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ANTI_SCREENSHOT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ANTI_SCREENSHOT_SUBTITLE");
		}
		else if (indexPath.row == 5) {
			cell.imageView.image = [UIImage systemImageNamed:@"eye.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ANTI_SELF_DESTRUCT_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ANTI_SELF_DESTRUCT_SUBTITLE");
		}
		else if (indexPath.row == 6) {
			cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"DOWNLOAD_STORIES_TITLE");
			cell.detailTextLabel.text = TGLoc(@"DOWNLOAD_STORIES_SUBTITLE");
		}
		else if (indexPath.row == 7) {
			cell.imageView.image = [UIImage systemImageNamed:@"mic.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"SEND_AS_VOICE_TITLE");
			cell.detailTextLabel.text = TGLoc(@"SEND_AS_VOICE_SUBTITLE");
		}

		UISwitch *toggle = (UISwitch *)cell.accessoryView;
		if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
			toggle = [[UISwitch alloc] init];
		}

		NSString *switchKey = [self switchKeyForIndexPath:indexPath];
		toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
		[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
		toggle.tag = 1000 + (indexPath.section * 1000) + indexPath.row;
		cell.accessoryView = toggle;

		cell.textLabel.numberOfLines = 0;
		cell.detailTextLabel.numberOfLines = 0;
		return cell;
	}
	else if (indexPath.section == 3) { // File Picker Fix
		if (indexPath.row == 0) {
			cell = [self switchCellFromTableView:tableView];

			cell.imageView.image = [UIImage systemImageNamed:@"folder.fill.badge.gear"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"FIX_FILE_PICKER_TITLE");
			cell.detailTextLabel.text = TGLoc(@"FIX_FILE_PICKER_SUBTITLE");

			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
				toggle = [[UISwitch alloc] init];
			}

			NSString *switchKey = [self switchKeyForIndexPath:indexPath];
			toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
			[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
			toggle.tag = 1000 + (indexPath.section * 1000) + indexPath.row;
			cell.accessoryView = toggle;

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}
		if (indexPath.row == 1) {
			cell = [self normalCellFromTableView:tableView];
			cell.imageView.image = nil;

		    cell.textLabel.text = TGLoc(@"CLEAR_FILE_PICKER_CACHE_TITLE");
		    cell.detailTextLabel.text = TGLoc(@"CLEAR_FILE_PICKER_CACHE_SUBTITLE");
		    cell.imageView.image = [UIImage systemImageNamed:@"trash"];
		    cell.imageView.tintColor = [UIColor redColor];

		    UIActivityIndicatorView *loadingIcon = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
		    [loadingIcon startAnimating];
		    cell.accessoryView = loadingIcon;

		    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
				if (!self.cacheSize) {
					self.cacheSize = [self sizeOfUglyFileFixDirectory];
				}

		        dispatch_async(dispatch_get_main_queue(), ^{
					UITableViewCell *currentCell = [tableView cellForRowAtIndexPath:indexPath];
					if (currentCell == cell) {
						UILabel *sizeLabel = [[UILabel alloc] init];
						sizeLabel.text = self.cacheSize;
						cell.accessoryView = sizeLabel;
					}
		        });
		    });

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}
	}
	else if (indexPath.section == 4) { // Fake Location
		if (indexPath.row == 0) {
			cell = [self switchCellFromTableView:tableView];

			cell.imageView.image = [UIImage systemImageNamed:@"location.circle.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];
			cell.textLabel.text = TGLoc(@"ENABLE_FAKE_LOCATION_TITLE");
			cell.detailTextLabel.text = TGLoc(@"ENABLE_FAKE_LOCATION_SUBTITLE");

			UISwitch *toggle = (UISwitch *)cell.accessoryView;
			if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
				toggle = [[UISwitch alloc] init];
			}

			NSString *switchKey = [self switchKeyForIndexPath:indexPath];
			toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:switchKey];
			[toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
			toggle.tag = 1000 + (indexPath.section * 1000) + indexPath.row;
			cell.accessoryView = toggle;

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}

		if (indexPath.row == 1) {
			cell = [self normalCellFromTableView:tableView];

			CGFloat savedLongitude = [[NSUserDefaults standardUserDefaults] floatForKey:FAKE_LONGITUDE_KEY];
			CGFloat savedLatitude = [[NSUserDefaults standardUserDefaults] floatForKey:FAKE_LATITUDE_KEY];

			cell.textLabel.text = TGLoc(@"SELECT_FAKE_LOCATION_TITLE");
			if (savedLongitude && savedLatitude) {
				cell.detailTextLabel.text = [NSString stringWithFormat:@"Lat: %.4f, Lon: %.4f", savedLatitude, savedLongitude];
			} else {
				cell.detailTextLabel.text = nil;
			}

			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			cell.accessoryView = nil;
			cell.imageView.image = [UIImage systemImageNamed:@"map.fill"];
			cell.imageView.tintColor = [self dynamicColorBW];

			cell.textLabel.numberOfLines = 0;
			cell.detailTextLabel.numberOfLines = 0;
			return cell;
		}
	}

    return cell;
}

# pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

	if (indexPath.section == FILE_FIXER) {
		if (indexPath.row == 1) {
			[self clearFilePickerFixCache];
		}
	}

	if (indexPath.section == FAKE_LOCATION) {
		if (indexPath.row == 1) {
			[self showLocationSelector];
		}
	}
}

- (void)switchChanged:(UISwitch *)sender {
    NSInteger adjustedTag = sender.tag - 1000;
    NSInteger section = adjustedTag / 1000;
    NSInteger row = adjustedTag % 1000;

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
    NSString *switchKey = [self switchKeyForIndexPath:indexPath];

    if (switchKey) {
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:switchKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (NSString *)switchKeyForIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0: return kDisableOnlineStatus;
                case 1: return kDisableTypingStatus;
                case 2: return kDisableRecordingVideoStatus;
                case 3: return kDisableUploadingVideoStatus;
                case 4: return kDisableRecordingVoiceStatus;
                case 5: return kDisableUploadingVoiceStatus;
                case 6: return kDisableUploadingPhotoStatus;
                case 7: return kDisableUploadingFileStatus;
                case 8: return kDisableChoosingLocationStatus;
                case 9: return kDisableChoosingContactStatus;
                case 10: return kDisablePlayingGameStatus;
                case 11: return kDisableRecordingRoundVideoStatus;
                case 12: return kDisableUploadingRoundVideoStatus;
                case 13: return kDisableSpeakingInGroupCallStatus;
                case 14: return kDisableChoosingStickerStatus;
                case 15: return kDisableEmojiInteractionStatus;
                case 16: return kDisableEmojiAcknowledgementStatus;
                default: return nil;
            }
        case 1:
            switch (indexPath.row) {
                case 0: return kDisableMessageReadReceipt;
                case 1: return kDisableStoriesReadReceipt;
                default: return nil;
            }
        case 2:
            switch (indexPath.row) {
                case 0: return kDisableAllAds;
                case 1: return kDisableForwardRestriction;
                case 2: return kAntiRevoke;
                case 3: return kAntiAutoDelete;
                case 4: return kDisableScreenshotNotification;
                case 5: return kAntiSelfDestruct;
                case 6: return kDownloadStories;
                case 7: return kSendAsVoice;
                default: return nil;
            }
        case 3:
            switch (indexPath.row) {
                case 0: return FILE_PICKER_FIX_KEY;
                default: return nil;
            }
        case 4:
            switch (indexPath.row) {
                case 0: return FAKE_LOCATION_ENABLED_KEY;
                default: return nil;
            }
        default:
            return nil;
    }
}

- (NSString *)sizeOfUglyFileFixDirectory {
	NSString *uglyFixDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:FILE_PICKER_PATH];

    unsigned long long totalSize = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *contents = [fileManager subpathsAtPath:uglyFixDirectory];

    for (NSString *path in contents) {
        NSString *fullPath = [uglyFixDirectory stringByAppendingPathComponent:path];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
            if (!isDirectory) {
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:nil];
                totalSize += [attributes fileSize];
            }
        }
    }

    NSString *formattedSize;
    if (totalSize >= 1024 * 1024 * 1024) {
        formattedSize = [NSString stringWithFormat:@"%.2f GB", totalSize / (1024.0 * 1024.0 * 1024.0)];
    } else {
        formattedSize = [NSString stringWithFormat:@"%.2f MB", totalSize / (1024.0 * 1024.0)];
    }
	return formattedSize;
}

- (void)showLocationSelector {
	LocationSelector *ui = [LocationSelector new];
	UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:ui];
	[self presentViewController:navVC animated:YES completion:nil];
}

- (void)clearFilePickerFixCache {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:TGLoc(@"CACHE_CLEAR_WARNING_TITLE")
                                                                   message:TGLoc(@"CACHE_CLEAR_WARNING_MESSAGE")
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:TGLoc(@"OK")
                                                       style:UIAlertActionStyleDestructive
                                                     handler:^(UIAlertAction *action) {
        NSString *uglyFixDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:FILE_PICKER_PATH];

        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:uglyFixDirectory error:&error];

        if (error) {
            NSLog(@"Failed to remove cache directory: %@", error.localizedDescription);
        } else {
            NSLog(@"Successfully cleared cache: %@", uglyFixDirectory);
        }

		self.cacheSize = @"Cleared";

        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexSet *section = [NSIndexSet indexSetWithIndex:FILE_FIXER];
            [self.tableView reloadSections:section withRowAnimation:UITableViewRowAnimationAutomatic];
        });
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:TGLoc(@"CANCEL")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [alert addAction:cancelAction];
    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"TweakLocationChanged" object:nil];
}

@end
