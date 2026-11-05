#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "Headers.h"

#define TGLoc(key) [TGExtraLocalization localizedStringForKey:(key)]

typedef struct {
    __unsafe_unretained NSString *key;
    __unsafe_unretained NSString *titleKey;
    __unsafe_unretained NSString *subtitleKey;
} ActivityItem;

static const ActivityItem kActivityItems[] = {
    { kDisableRecordingVideoStatus, @"DISABLE_RECORDING_VIDEO_STATUS_TITLE", @"DISABLE_RECORDING_VIDEO_STATUS_SUBTITLE" },
    { kDisableUploadingVideoStatus, @"DISABLE_UPLOADING_VIDEO_STATUS_TITLE", @"DISABLE_UPLOADING_VIDEO_STATUS_SUBTITLE" },
    { kDisableRecordingVoiceStatus, @"DISABLE_VC_MESSAGE_RECORDING_STATUS_TITLE", @"DISABLE_VC_MESSAGE_RECORDING_STATUS_SUBTITLE" },
    { kDisableUploadingVoiceStatus, @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_TITLE", @"DISABLE_VC_MESSAGE_UPLOADING_STATUS_SUBTITLE" },
    { kDisableUploadingPhotoStatus, @"DISABLE_UPLOADING_PHOTO_STATUS_TITLE", @"DISABLE_UPLOADING_PHOTO_STATUS_SUBTITLE" },
    { kDisableUploadingFileStatus, @"DISABLE_UPLOADING_FILE_STATUS_TITLE", @"DISABLE_UPLOADING_FILE_STATUS_SUBTITLE" },
    { kDisableRecordingRoundVideoStatus, @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_TITLE", @"DISABLE_RECORDING_ROUND_VIDEO_STATUS_SUBTITLE" },
    { kDisableUploadingRoundVideoStatus, @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_TITLE", @"DISABLE_UPLOADING_ROUND_VIDEO_STATUS_SUBTITLE" },
    { kDisableChoosingLocationStatus, @"DISABLE_CHOOSING_LOCATION_STATUS_TITLE", @"DISABLE_CHOOSING_LOCATION_STATUS_SUBTITLE" },
    { kDisableChoosingContactStatus, @"DISABLE_CHOOSING_CONTACT_TITLE", @"DISABLE_CHOOSING_CONTACT_SUBTITLE" },
    { kDisableChoosingStickerStatus, @"DISABLE_CHOOSING_STICKER_STATUS_TITLE", @"DISABLE_CHOOSING_STICKER_STATUS_SUBTITLE" },
    { kDisablePlayingGameStatus, @"DISABLE_PLAYING_GAME_STATUS_TITLE", @"DISABLE_PLAYING_GAME_STATUS_SUBTITLE" },
    { kDisableSpeakingInGroupCallStatus, @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_TITLE", @"DISABLE_SPEAKING_IN_GROUP_CALL_STATUS_SUBTITLE" },
    { kDisableEmojiInteractionStatus, @"DISABLE_EMOJI_INTERACTION_STATUS_TITLE", @"DISABLE_EMOJI_INTERACTION_STATUS_SUBTITLE" },
    { kDisableEmojiAcknowledgementStatus, @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_TITLE", @"DISABLE_EMOJI_ACKNOWLEDGEMENT_STATUS_SUBTITLE" },
};

static const NSInteger kActivityItemsCount = sizeof(kActivityItems) / sizeof(kActivityItems[0]);

@interface TGOtherActivities ()
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation TGOtherActivities

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = TGLoc(@"OTHER_ACTIVITIES_TITLE");
    [self setupTableView];
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

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return kActivityItemsCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return TGLoc(@"OTHER_ACTIVITIES_SECTION_HEADER");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"activitySwitchCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"activitySwitchCell"];
    }

    cell.imageView.image = nil;

    if (indexPath.row >= 0 && indexPath.row < kActivityItemsCount) {
        ActivityItem item = kActivityItems[indexPath.row];
        cell.textLabel.text = TGLoc(item.titleKey);
        cell.detailTextLabel.text = item.subtitleKey ? TGLoc(item.subtitleKey) : nil;

        UISwitch *toggle = (UISwitch *)cell.accessoryView;
        if (!toggle || ![toggle isKindOfClass:[UISwitch class]]) {
            toggle = [[UISwitch alloc] init];
        }
        toggle.onTintColor = [UIColor systemBlueColor];
        toggle.on = [[NSUserDefaults standardUserDefaults] boolForKey:item.key];
        toggle.tag = indexPath.row;
        [toggle removeTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [toggle addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }

    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSInteger row = sender.tag;
    if (row >= 0 && row < kActivityItemsCount) {
        NSString *key = kActivityItems[row].key;
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
