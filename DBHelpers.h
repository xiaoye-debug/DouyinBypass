#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define LOG_TAG @"[DouyinBypass]"
#define DBLog(fmt, ...) NSLog(@"%@ " fmt, LOG_TAG, ##__VA_ARGS__)

#define BACKUP_DIR @"/var/mobile/Documents/DouyinAccountBackup"
#define BACKUP_FILENAME_FMT @"douyin_account_%@.zip"
#define DB_INJECTED_SECTION 0
#define DB_SECTION_ROW_COUNT 3

typedef struct {
    const char *icon;
    const char *title;
    const char *detail;
} DBMenuItem;

extern DBMenuItem gDBMenuItems[];

NSInteger DBRealSection(NSInteger displaySection);
NSDictionary *DBExtractAccountData(void);
NSString *DBPrepareExportZip(void);
BOOL DBImportAccountFromPath(NSString *zipPath);
void DBHookIsAppStoreChannel(void);

// Class declarations with block-typed parameters (must be outside .xm to avoid Logos parsing issues)
@interface BDUGCloudkitManager : NSObject
- (BOOL)isValidMobileProvision;
- (void)setupCloudKit;
@end

@interface AWEAccountForceUpgradeManager : NSObject
+ (instancetype)sharedInstance;
- (void)checkForceUpgrade;
- (void)showForceUpgradeDialog;
- (BOOL)shouldForceUpgrade;
@end

@interface AWEAppStoreMediator : NSObject
+ (instancetype)sharedInstance;
- (void)openURL:(NSURL *)url completion:(void(^)(BOOL))completion;
- (void)initSKStoreProductVCWithCompletion:(void(^)(id))completion;
@end

@interface TTAccountSDKSetup : NSObject
+ (void)startWithConfig:(id)config;
@end

@interface AWESettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>
- (UITableViewCell *)db_cellForInjectedRow:(UITableView *)tv indexPath:(NSIndexPath *)ip;
- (void)db_handleInjectedSelection:(NSInteger)row fromVC:(UIViewController *)vc tableView:(UITableView *)tv;
- (void)db_showBackupListFromVC:(UIViewController *)vc;
@end
void DBHookAppStoreMediator(void);

