#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define LOG_TAG @"[DouyinBypass]"
#define DBLog(fmt, ...) NSLog(@"%@ " fmt, LOG_TAG, ##__VA_ARGS__)

#define BACKUP_DIR @"/var/mobile/Documents/DouyinAccountBackup"
#define BACKUP_FILENAME_FMT @"douyin_account_%@.zip"

#ifdef __cplusplus
extern "C" {
#endif

NSString *DBPrepareExportZip(void);
BOOL DBImportAccountFromPath(NSString *zipPath);
void DBHookIsAppStoreChannel(void);
void DBHookAppStoreMediator(void);

// Settings injection (called from %ctor via MSHookMessageEx or from %hook)
id DBMakeSettingsEntryItem(void);
id DBMakeSettingsSection(id entryItem);
NSArray *DBInjectSettingsSections(NSArray *originalSections);
void DBPresentControlPanel(void);

#ifdef __cplusplus
}
#endif

// Douyin settings model classes (declared here to keep .xm clean of block syntax)
@interface AWESettingItemModel : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *subTitle;
@property(nonatomic,copy) NSString *detail;
@property(nonatomic,copy) NSString *svgIconImageName;
@property(nonatomic,copy) NSString *iconImageName;
@property(nonatomic,assign) NSInteger cellType;
@property(nonatomic,assign) NSInteger colorStyle;
@property(nonatomic,assign) BOOL isEnable;
@property(nonatomic,assign) BOOL isSwitchOn;
@property(nonatomic,copy) void (^cellTappedBlock)(void);
@property(nonatomic,copy) void (^switchChangedBlock)(void);
@end

@interface AWESettingSectionModel : NSObject
@property(nonatomic,copy) NSString *sectionHeaderTitle;
@property(nonatomic,assign) CGFloat sectionHeaderHeight;
@property(nonatomic,copy) NSString *sectionFooterTitle;
@property(nonatomic,assign) NSInteger type;
@property(nonatomic,strong) NSArray *itemArray;
@end

@interface AWESettingsViewModel : NSObject
@property(nonatomic,strong) NSArray *sectionDataArray;
@property(nonatomic,assign) NSInteger colorStyle;
@end

// Bypass target classes
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
