#import "Headers.h"
#import <objc/runtime.h>

@interface LanguageSelector ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *languages;
@end

@implementation LanguageSelector

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *filePath = jbroot(@"/Library/Application Support/Tweak/Tweak.bundle/langs.json");
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
		filePath = [NSString stringWithFormat:@"%@/Tweak.bundle/langs.json", [[NSBundle mainBundle] resourcePath]];
    }

    NSError *jsonDecodeError = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    NSArray *langs = nil;

    if (data) {
        langs = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonDecodeError];
    }

    if (jsonDecodeError || !langs) {
        self.languages = @[
           @{
               @"name": @"Русский",
               @"code": @"ru",
               @"flag": @"🇷🇺"
           },
           @{
               @"name": @"English",
               @"code": @"en",
               @"flag": @"🇺🇸"
           }
        ];
    } else {
        self.languages = langs;
    }

	self.title = @"Change Language";
	[self loadLanguages];
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

- (void)loadLanguages {
    NSMutableArray *languages = [NSMutableArray array];

    for (NSDictionary *language in self.languages) {
        NSString *localizationFilePath = [NSString stringWithFormat:@"%@/Tweak.bundle/%@.lproj/Localizable.strings", jbroot(@"/Library/Application Support/Tweak"), language[@"code"]];
        BOOL hasFile = [[NSFileManager defaultManager] fileExistsAtPath:localizationFilePath];

        if (!hasFile) {
            localizationFilePath = [NSString stringWithFormat:@"%@/Tweak.bundle/%@.lproj/Localizable.strings", [[NSBundle mainBundle] resourcePath], language[@"code"]];
            hasFile = (localizationFilePath != nil);
        }

        if (hasFile) {
            NSMutableDictionary *dict = [language mutableCopy];
            dict[@"path"] = localizationFilePath;
            [languages addObject:dict];
        }
    }
    self.languages = languages;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.languages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"LanguageCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];

    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }

    NSDictionary *language = self.languages[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", language[@"flag"], language[@"name"]];

    NSString *savedLanguage = [[NSUserDefaults standardUserDefaults] stringForKey:@"TweakLanguage"];
    if (!savedLanguage) {
        savedLanguage = @"ru";
    }

    if ([savedLanguage isEqualToString:language[@"code"]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *languageData = self.languages[indexPath.row];

    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:languageData[@"path"]];

    if (!dict) {
        [self showAlertWithTitle:@"Error" message:@"Failed to load language localization data"];
        return;
    }

    TGLocalization *localization = [[objc_getClass("TGLocalization") alloc] initWithVersion:96929692
                                                                   code:languageData[@"code"]
                                                                   dict:dict
                                                              isActive:YES];

    if (localization) {
        [TGExtraLocalization shared].localization = localization;

        [[NSUserDefaults standardUserDefaults] setObject:languageData[@"code"] forKey:@"TweakLanguage"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        [[NSNotificationCenter defaultCenter] postNotificationName:@"LanguageChangedNotification" object:nil];

        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        [tableView reloadData];
    } else {
        [self showAlertWithTitle:@"Error" message:@"Failed to load the language."];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];

    [alert addAction:okAction];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
