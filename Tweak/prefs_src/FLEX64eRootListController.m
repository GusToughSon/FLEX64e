#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <spawn.h>

#define PREFS_PATH @"/var/mobile/Library/Preferences/com.flex.flex64e.plist"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@interface FLEX64eRootListController : UIViewController <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *customTableView;
@property (nonatomic, strong) NSMutableDictionary *preferences;
@property (nonatomic, strong) NSArray *systemApps;
@property (nonatomic, strong) NSArray *userApps;
@property (nonatomic, strong) NSArray *filteredSystemApps;
@property (nonatomic, strong) NSArray *filteredUserApps;
@property (nonatomic, assign) BOOL isUserAppsExpanded;
@property (nonatomic, assign) BOOL isSystemAppsExpanded;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation FLEX64eRootListController



- (void)loadView {
    [super loadView];
    
    self.isUserAppsExpanded = NO;
    self.isSystemAppsExpanded = NO;
    
    self.preferences = [NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: [NSMutableDictionary dictionary];
    [self loadApplications];
    
    self.customTableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.customTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.customTableView.delegate = self;
    self.customTableView.dataSource = self;
    [self.view addSubview:self.customTableView];
    
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Applications";
    
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        self.customTableView.tableHeaderView = self.searchController.searchBar;
    }
    self.definesPresentationContext = YES;
}

- (void)loadApplications {
    Class LSApplicationWorkspace_class = NSClassFromString(@"LSApplicationWorkspace");
    if (!LSApplicationWorkspace_class) return;
    
    id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
    NSArray<LSApplicationProxy *> *apps = [workspace performSelector:@selector(allInstalledApplications)];
    
    NSMutableArray *system = [NSMutableArray array];
    NSMutableArray *user = [NSMutableArray array];
    
    for (LSApplicationProxy *app in apps) {
        NSString *type = [app performSelector:@selector(applicationType)];
        if ([type isEqualToString:@"System"]) {
            [system addObject:app];
        } else if ([type isEqualToString:@"User"]) {
            [user addObject:app];
        }
    }
    
    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:@"localizedName" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    self.systemApps = [system sortedArrayUsingDescriptors:@[sort]];
    self.userApps = [user sortedArrayUsingDescriptors:@[sort]];
    
    self.filteredSystemApps = self.systemApps;
    self.filteredUserApps = self.userApps;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text.lowercaseString;
    if (searchText.length == 0) {
        self.filteredUserApps = self.userApps;
        self.filteredSystemApps = self.systemApps;
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(LSApplicationProxy *app, NSDictionary *bindings) {
            return [[app.localizedName lowercaseString] containsString:searchText] || [[app.applicationIdentifier lowercaseString] containsString:searchText];
        }];
        self.filteredUserApps = [self.userApps filteredArrayUsingPredicate:predicate];
        self.filteredSystemApps = [self.systemApps filteredArrayUsingPredicate:predicate];
    }
    [self.customTableView reloadData];
}

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (void)savePreferencesAndRespring {
    [self.preferences writeToFile:PREFS_PATH atomically:YES];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring Required"
                                                                   message:@"Applying changes requires a respring. Save and Respring now?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Save & Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
        if (pid == 0) {
            posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)args, NULL);
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [self.customTableView reloadData];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)globalSwitchToggled:(UISwitch *)sender {
    self.preferences[@"globalEnabled"] = @(sender.isOn);
    [self savePreferencesAndRespring];
}

- (void)appSwitchToggled:(UISwitch *)sender {
    NSString *bundleID = objc_getAssociatedObject(sender, "bundleID");
    if (bundleID) {
        NSString *appKey = [NSString stringWithFormat:@"enabledApps-%@", bundleID];
        self.preferences[appKey] = @(sender.isOn);
        [self.preferences writeToFile:PREFS_PATH atomically:YES];
    }
}

- (void)toggleSection:(UITapGestureRecognizer *)gesture {
    NSInteger section = gesture.view.tag;
    if (section == 1) {
        self.isUserAppsExpanded = !self.isUserAppsExpanded;
    } else if (section == 2) {
        self.isSystemAppsExpanded = !self.isSystemAppsExpanded;
    }
    [self.customTableView reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationFade];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;
    
    if ([self isSearching]) {
        if (section == 1) return self.filteredUserApps.count;
        if (section == 2) return self.filteredSystemApps.count;
    } else {
        if (section == 1) return self.isUserAppsExpanded ? self.filteredUserApps.count : 0;
        if (section == 2) return self.isSystemAppsExpanded ? self.filteredSystemApps.count : 0;
    }
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 44)];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, tableView.bounds.size.width - 30, 44)];
    label.font = [UIFont boldSystemFontOfSize:17];
    label.textColor = [UIColor darkGrayColor];
    
    if (section == 1) {
        NSString *arrow = ([self isSearching] || self.isUserAppsExpanded) ? @"▼" : @"▶";
        label.text = [NSString stringWithFormat:@"%@ User Applications", arrow];
    } else if (section == 2) {
        NSString *arrow = ([self isSearching] || self.isSystemAppsExpanded) ? @"▼" : @"▶";
        label.text = [NSString stringWithFormat:@"%@ System Applications", arrow];
    }
    
    [headerView addSubview:label];
    headerView.tag = section;
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleSection:)];
    [headerView addGestureRecognizer:tap];
    
    return headerView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) return UITableViewAutomaticDimension;
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    if (indexPath.section == 0) {
        cell.textLabel.text = @"Global Enabled";
        cell.detailTextLabel.text = @"Inject FLEX into selected apps";
        cell.imageView.image = nil;
        
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [self.preferences[@"globalEnabled"] boolValue];
        [toggle addTarget:self action:@selector(globalSwitchToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    } else {
        LSApplicationProxy *app = (indexPath.section == 1) ? self.filteredUserApps[indexPath.row] : self.filteredSystemApps[indexPath.row];
        cell.textLabel.text = [app performSelector:@selector(localizedName)];
        NSString *bundleID = [app performSelector:@selector(applicationIdentifier)];
        cell.detailTextLabel.text = bundleID;
        
        // Load App Icon
        if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
            UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
            cell.imageView.image = icon;
        }
        
        UISwitch *toggle = [[UISwitch alloc] init];
        NSString *appKey = [NSString stringWithFormat:@"enabledApps-%@", bundleID];
        toggle.on = [self.preferences[appKey] boolValue];
        objc_setAssociatedObject(toggle, "bundleID", bundleID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(appSwitchToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
    }
    
    return cell;
}

@end
