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
