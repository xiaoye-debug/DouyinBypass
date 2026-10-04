#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonCrypto.h>
#import <mach-o/dyld.h>

// DouyinBypass v2.1.0
// Target: com.ss.iphone.ugc.Aweme (Douyin)
//        com.ss.iphone.ugc.aweme.lite (Douyin Lite)
// Features:
//   1. Bypass version check / resign detection
//   2. Account backup & restore (ZIP export/import via document picker)
//   3. Native-style settings section injection (like Aweme Pro)

#define LOG_TAG @"[DouyinBypass]"
#define DBLog(fmt, ...) NSLog(@"%@ " fmt, LOG_TAG, ##__VA_ARGS__)

#define BACKUP_DIR @"/var/mobile/Documents/DouyinAccountBackup"
#define BACKUP_FILENAME_FMT @"douyin_account_%@.zip"

// Injected section index (always section 0, pushing original sections down by 1)
#define DB_INJECTED_SECTION 0
#define DB_SECTION_ROW_COUNT 3  // Export, Import, Backup List

// ============================================================
#pragma mark - Part 1: Original Bypass Hooks
// ============================================================

@interface BDUGCloudkitManager : NSObject
- (BOOL)isValidMobileProvision;
- (void)setupCloudKit;
@end

%hook BDUGCloudkitManager
- (BOOL)isValidMobileProvision { return YES; }
- (void)setupCloudKit {}
%end

@interface AWEAccountForceUpgradeManager : NSObject
+ (instancetype)sharedInstance;
- (void)checkForceUpgrade;
- (void)showForceUpgradeDialog;
- (BOOL)shouldForceUpgrade;
@end

%hook AWEAccountForceUpgradeManager
- (void)checkForceUpgrade {}
- (void)showForceUpgradeDialog {}
- (BOOL)shouldForceUpgrade { return NO; }
%end

%hook NSObject
- (BOOL)isAppStoreChannel {
    if ([self respondsToSelector:@selector(isAppStoreChannel)]) return YES;
    return %orig;
}
%end

@interface AWEAppStoreMediator : NSObject
+ (instancetype)sharedInstance;
- (void)openURL:(NSURL *)url completion:(void(^)(BOOL))completion;
- (void)initSKStoreProductVCWithCompletion:(void(^)(id))completion;
@end

%hook AWEAppStoreMediator
- (void)openURL:(NSURL *)url completion:(void(^)(BOOL))completion {
    if (completion) completion(YES);
}
- (void)initSKStoreProductVCWithCompletion:(void(^)(id))completion {
    if (completion) completion(nil);
}
%end

@interface TTAccountSDKSetup : NSObject
+ (void)startWithConfig:(id)config;
@end

%hook TTAccountSDKSetup
+ (void)startWithConfig:(id)config { %orig; }
%end

// ============================================================
#pragma mark - Part 2: Account Data Extraction
// ============================================================

static NSDictionary *DBExtractAccountData(void) {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

    // 1. UserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *accountKeys = @[
        @"session_key", @"session_secret", @"uid", @"user_id",
        @"device_id", @"install_id", @"iid", @"aid",
        @"tt_token", @"access_token", @"refresh_token",
        @"login_type", @"login_time", @"bind_phone",
        @"nickname", @"avatar_url", @"sec_uid",
        @"unique_id", @"short_id", @"account_sdk_source",
        @"ss_region_code", @"ss_mcc_mnc", @"ss_carrier_region",
        @"app_language", @"channel", @"update_version_code",
        @"last_login_uid", @"last_login_type"
    ];
    NSMutableDictionary *udData = [NSMutableDictionary dictionary];
    for (NSString *key in accountKeys) {
        id val = [defaults objectForKey:key];
        if (val) udData[key] = val;
    }
    NSDictionary *allUD = [defaults dictionaryRepresentation];
    for (NSString *key in allUD.allKeys) {
        NSString *lower = key.lowercaseString;
        if ([lower containsString:@"session"] || [lower containsString:@"token"] ||
            [lower containsString:@"login"] || [lower containsString:@"account"] ||
            [lower containsString:@"uid"] || [lower containsString:@"device"] ||
            [lower containsString:@"cookie"] || [lower containsString:@"auth"]) {
            if (!udData[key]) udData[key] = allUD[key];
        }
    }
    data[@"userDefaults"] = udData;

    // 2. Keychain
    NSMutableArray *keychainItems = [NSMutableArray array];
    NSArray *secClasses = @[(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecClassInternetPassword];
    for (id secClass in secClasses) {
        NSDictionary *query = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
        };
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status == errSecSuccess && result) {
            NSArray *items = (__bridge NSArray *)result;
            for (NSDictionary *item in items) {
                NSString *svc = item[(__bridge id)kSecAttrService] ?: @"";
                NSString *acct = item[(__bridge id)kSecAttrAccount] ?: @"";
                NSData *d = item[(__bridge id)kSecValueData];
                NSString *lowerSvc = svc.lowercaseString;
                NSString *lowerAcct = acct.lowercaseString;
                BOOL relevant = [lowerSvc containsString:@"douyin"] || [lowerSvc containsString:@"aweme"] ||
                                [lowerSvc containsString:@"bytedance"] || [lowerSvc containsString:@"toutiao"] ||
                                [lowerSvc containsString:@"tiktok"] || [lowerSvc containsString:@"ss_"] ||
                                [lowerAcct containsString:@"session"] || [lowerAcct containsString:@"token"] ||
                                [lowerAcct containsString:@"account"];
                if (relevant && d.length > 0) {
                    [keychainItems addObject:@{
                        @"service": svc, @"account": acct,
                        @"data_base64": [d base64EncodedStringWithOptions:0],
                        @"class": secClass
                    }];
                }
            }
            CFRelease(result);
        }
    }
    data[@"keychain"] = keychainItems;

    // 3. Cookies
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSMutableArray *cookies = [NSMutableArray array];
    for (NSHTTPCookie *cookie in storage.cookies) {
        NSString *domain = cookie.domain.lowercaseString;
        if ([domain containsString:@"douyin"] || [domain containsString:@"snssdk"] ||
            [domain containsString:@"bytedance"] || [domain containsString:@"pstatp"] ||
            [domain containsString:@"amemv"] || [domain containsString:@"ixigua"] ||
            [domain containsString:@"toutiao"] || [domain containsString:@"byteimg"]) {
            [cookies addObject:@{
                @"name": cookie.name, @"value": cookie.value,
                @"domain": cookie.domain, @"path": cookie.path ?: @"/",
                @"secure": @(cookie.isSecure),
                @"expiresDate": cookie.expiresDate ? @([cookie.expiresDate timeIntervalSince1970]) : @(-1)
            }];
        }
    }
    data[@"cookies"] = cookies;

    // 4. Metadata
    data[@"metadata"] = @{
        @"exportTime": @([[NSDate date] timeIntervalSince1970]),
        @"appVersion": [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown",
        @"bundleId": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown",
        @"deviceModel": [[UIDevice currentDevice] model] ?: @"unknown",
        @"systemVersion": [[UIDevice currentDevice] systemVersion] ?: @"unknown"
    };

    DBLog(@"Extracted: UD=%lu KC=%lu CK=%lu",
          (unsigned long)udData.count, (unsigned long)keychainItems.count, (unsigned long)cookies.count);
    return [data copy];
}

// ============================================================
#pragma mark - Part 3: ZIP Helpers
// ============================================================

static BOOL DBCreateZipFromDirectory(NSString *srcDir, NSString *dstZip) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/zip";
    task.arguments = @[@"-r", @"-j", dstZip, srcDir];
    task.currentDirectoryPath = [srcDir stringByDeletingLastPathComponent];
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0 && [[NSFileManager defaultManager] fileExistsAtPath:dstZip];
}

static BOOL DBUnzipToDirectory(NSString *srcZip, NSString *dstDir) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/unzip";
    task.arguments = @[@"-o", srcZip, @"-d", dstDir];
    [task launch];
    [task waitUntilExit];
    return task.terminationStatus == 0;
}

// ============================================================
#pragma mark - Part 4: Export & Import Logic
// ============================================================

static NSString *DBPrepareExportZip(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:BACKUP_DIR withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
    NSString *tempDir = [BACKUP_DIR stringByAppendingPathComponent:[NSString stringWithFormat:@"temp_%@", timestamp]];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *accountData = DBExtractAccountData();
    NSString *jsonPath = [tempDir stringByAppendingPathComponent:@"account_data.json"];
    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:accountData options:NSJSONWritingPrettyPrinted error:&err];
    if (!jsonData) { DBLog(@"JSON failed: %@", err); return nil; }
    [jsonData writeToFile:jsonPath atomically:YES];

    NSString *zipName = [NSString stringWithFormat:BACKUP_FILENAME_FMT, timestamp];
    NSString *zipPath = [BACKUP_DIR stringByAppendingPathComponent:zipName];
    if (!DBCreateZipFromDirectory(tempDir, zipPath)) { DBLog(@"ZIP failed"); return nil; }

    [fm removeItemAtPath:tempDir error:nil];
    DBLog(@"Export prepared: %@", zipPath);
    return zipPath;
}

static BOOL DBImportAccountFromPath(NSString *zipPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:zipPath]) return NO;

    NSString *tempDir = [BACKUP_DIR stringByAppendingPathComponent:@"import_temp"];
    [fm removeItemAtPath:tempDir error:nil];
    if (!DBUnzipToDirectory(zipPath, tempDir)) return NO;

    NSString *jsonPath = [tempDir stringByAppendingPathComponent:@"account_data.json"];
    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
    if (!jsonData) return NO;

    NSError *err = nil;
    NSDictionary *accountData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&err];
    if (!accountData) return NO;

    // Restore UserDefaults
    NSDictionary *udData = accountData[@"userDefaults"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in udData) [defaults setObject:udData[key] forKey:key];
    [defaults synchronize];

    // Restore Keychain
    NSArray *kcItems = accountData[@"keychain"];
    for (NSDictionary *item in kcItems) {
        NSString *svc = item[@"service"];
        NSString *acct = item[@"account"];
        NSData *d = [[NSData alloc] initWithBase64EncodedString:item[@"data_base64"] options:0];
        id secClass = item[@"class"];
        if (!svc || !d) continue;
        NSDictionary *delQ = @{(__bridge id)kSecClass: secClass, (__bridge id)kSecAttrService: svc, (__bridge id)kSecAttrAccount: acct};
        SecItemDelete((__bridge CFDictionaryRef)delQ);
        NSMutableDictionary *addQ = [@{(__bridge id)kSecClass: secClass, (__bridge id)kSecAttrService: svc,
                                       (__bridge id)kSecAttrAccount: acct, (__bridge id)kSecValueData: d} mutableCopy];
        addQ[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        SecItemAdd((__bridge CFDictionaryRef)addQ, NULL);
    }

    // Restore Cookies
    NSArray *cookieData = accountData[@"cookies"];
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSDictionary *cd in cookieData) {
        NSMutableDictionary *props = [NSMutableDictionary dictionary];
        props[NSHTTPCookieName] = cd[@"name"];
        props[NSHTTPCookieValue] = cd[@"value"];
        props[NSHTTPCookieDomain] = cd[@"domain"];
        props[NSHTTPCookiePath] = cd[@"path"] ?: @"/";
        if ([cd[@"secure"] boolValue]) props[NSHTTPCookieSecure] = @"TRUE";
        double exp = [cd[@"expiresDate"] doubleValue];
        if (exp > 0) props[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSince1970:exp];
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:props];
        if (cookie) [storage setCookie:cookie];
    }

    [fm removeItemAtPath:tempDir error:nil];
    DBLog(@"Import complete from: %@", zipPath);
    return YES;
}

// ============================================================
#pragma mark - Part 5: Settings Section Injection (Native Style)
// ============================================================
// We inject a new section at index 0 that looks exactly like
// the "Aweme Pro" section in the screenshot:
//   Header: "♪ DouyinBypass"
//   Row 0:  icon + "导出账号"    right: "保存"  >
//   Row 1:  icon + "导入账号"    right: "选择"  >
//   Row 2:  icon + "备份列表"    right: count  >

// Menu item definitions for our injected section
typedef struct {
    const char *icon;
    const char *title;
    const char *detail;
} DBMenuItem;

static DBMenuItem gDBMenuItems[] = {
    {"♡", "导出账号信息", "保存"},
    {"☆", "导入账号信息", "选择"},
    {"☁", "查看备份列表", "管理"},
};

// Forward declaration for the settings VC hook
static NSInteger db_originalSectionCount(id self, SEL _cmd, UITableView *tv);
static NSInteger db_originalRowCount(id self, SEL _cmd, UITableView *tv, NSInteger section);

// We store original IMPs
static NSInteger (*orig_numberOfSections)(id, SEL, UITableView *);
static NSInteger (*orig_numberOfRows)(id, SEL, UITableView *, NSInteger);
static UITableViewCell *(*orig_cellForRow)(id, SEL, UITableView *, NSIndexPath *);
static NSString *(*orig_headerTitle)(id, SEL, UITableView *, NSInteger);
static void (*orig_didSelectRow)(id, SEL, UITableView *, NSIndexPath *);
static CGFloat (*orig_heightForHeader)(id, SEL, UITableView *, NSInteger);
static UIView *(*orig_viewForHeader)(id, SEL, UITableView *, NSInteger);

// Helper: get the real (original) section from the displayed section
static NSInteger DBRealSection(NSInteger displaySection) {
    return displaySection - 1; // our section is 0, originals shift by +1
}

%hook AWESettingsViewController

- (void)viewDidLoad {
    %orig;
    DBLog(@"Settings VC loaded, injecting native section");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    NSInteger orig = %orig;
    return orig + 1; // add our section at top
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        return DB_SECTION_ROW_COUNT;
    }
    // For all other sections, delegate to original with shifted index
    // But since Logos %orig calls the original method, and the original
    // doesn't know about our extra section, we need to pass the real section.
    // The trick: the original method receives whatever section the table view asks for.
    // Since we added 1 section at top, sections 1..N map to original 0..N-1.
    // But %orig will receive the same section number the table view passes.
    // We need to temporarily adjust. Use a thread-local flag.
    return %orig(tv, DBRealSection(section));
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == DB_INJECTED_SECTION) {
        return [self db_cellForInjectedRow:tv indexPath:ip];
    }
    NSIndexPath *realIP = [NSIndexPath indexPathForRow:ip.row inSection:DBRealSection(ip.section)];
    return %orig(tv, realIP);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        return @"♪ DouyinBypass";
    }
    return %orig(tv, DBRealSection(section));
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        return %orig(tv, 0); // use same height as original first section header
    }
    return %orig(tv, DBRealSection(section));
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        // Return nil to use default grouped style header (titleForHeaderInSection)
        return nil;
    }
    return %orig(tv, DBRealSection(section));
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == DB_INJECTED_SECTION) {
        [tv deselectRowAtIndexPath:ip animated:YES];
        [self db_handleInjectedSelection:ip.row fromVC:self tableView:tv];
        return;
    }
    NSIndexPath *realIP = [NSIndexPath indexPathForRow:ip.row inSection:DBRealSection(ip.section)];
    %orig(tv, realIP);
}

// === New methods for injected section ===

%new
- (UITableViewCell *)db_cellForInjectedRow:(UITableView *)tv indexPath:(NSIndexPath *)ip {
    static NSString *reuseId = @"DBInjectedCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:reuseId];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseId];
    }

    DBMenuItem item = gDBMenuItems[ip.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%s  %s", item.icon, item.title];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.textColor = [UIColor labelColor];

    // Dynamic detail for backup list row
    if (ip.row == 2) {
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:BACKUP_DIR error:nil];
        NSInteger zipCount = 0;
        for (NSString *f in files) { if ([f hasSuffix:@".zip"]) zipCount++; }
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)zipCount];
    } else {
        cell.detailTextLabel.text = [NSString stringWithUTF8String:item.detail];
    }
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    // Match Douyin's background
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    return cell;
}

%new
- (void)db_handleInjectedSelection:(NSInteger)row fromVC:(UIViewController *)vc tableView:(UITableView *)tv {
    if (row == 0) {
        // Export: prepare ZIP then let user pick save location
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *zipPath = DBPrepareExportZip();
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!zipPath) {
                    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出失败" message:@"请检查日志" preferredStyle:UIAlertControllerStyleAlert];
                    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [vc presentViewController:a animated:YES completion:nil];
                    return;
                }
                NSURL *fileURL = [NSURL fileURLWithPath:zipPath];
                UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL]];
                picker.delegate = (id<UIDocumentPickerDelegate>)vc;
                picker.modalPresentationStyle = UIModalPresentationFormSheet;
                // Store zip path for later cleanup
                objc_setAssociatedObject(vc, "db_export_zip_path", zipPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [vc presentViewController:picker animated:YES completion:nil];
            });
        });
    }
    else if (row == 1) {
        // Import: let user pick a ZIP file from anywhere
        NSArray *types = @[@"com.pkware.zip-archive", @"public.zip-archive", @"public.data"];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
        picker.delegate = (id<UIDocumentPickerDelegate>)vc;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        picker.allowsMultipleSelection = NO;
        [vc presentViewController:picker animated:YES completion:nil];
    }
    else if (row == 2) {
        // Show backup list
        [self db_showBackupListFromVC:vc];
    }
}

%new
- (void)db_showBackupListFromVC:(UIViewController *)vc {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:BACKUP_DIR error:nil];
    NSMutableArray *info = [NSMutableArray array];
    for (NSString *f in files) {
        if ([f hasSuffix:@".zip"]) {
            NSString *full = [BACKUP_DIR stringByAppendingPathComponent:f];
            NSDictionary *attr = [fm attributesOfItemAtPath:full error:nil];
            unsigned long long size = attr.fileSize;
            NSDate *date = attr.fileModificationDate;
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"yyyy-MM-dd HH:mm";
            [info addObject:[NSString stringWithFormat:@"%@  (%.1f KB, %@)", f, size/1024.0, [fmt stringFromDate:date]]];
        }
    }
    [info sortUsingSelector:@selector(compare:)];
    [info reverseObjectEnumerator];

    NSString *msg = info.count > 0 ? [info componentsJoinedByString:@"\n\n"] : @"暂无备份文件\n\n请先导出账号信息";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"备份列表" message:msg preferredStyle:UIAlertControllerStyleAlert];

    if (info.count > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"清除所有备份" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            NSError *err = nil;
            [fm removeItemAtPath:BACKUP_DIR error:&err];
            [fm createDirectoryAtPath:BACKUP_DIR withIntermediateDirectories:YES attributes:nil error:nil];
            [tv reloadData];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

%end

// ============================================================
#pragma mark - Part 6: UIDocumentPickerDelegate on Settings VC
// ============================================================

%hook AWESettingsViewController

// Handle export completion (file saved to user-chosen location)
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    // Check if this is an export (we stored the zip path)
    NSString *exportZip = objc_getAssociatedObject(self, "db_export_zip_path");
    if (exportZip) {
        objc_setAssociatedObject(self, "db_export_zip_path", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // File was already copied by the system to user's chosen location
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出成功"
            message:[NSString stringWithFormat:@"已保存到:\n%@", urls.firstObject.path]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    // This is an import
    NSURL *pickedURL = urls.firstObject;
    if (!pickedURL) return;

    // Security-scoped resource access
    BOOL scoped = [pickedURL startAccessingSecurityScopedResource];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // Copy to local temp first (security-scoped URLs can be tricky)
        NSString *tempPath = [BACKUP_DIR stringByAppendingPathComponent:@"import_picked.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
        NSError *copyErr = nil;
        [[NSFileManager defaultManager] copyItemAtURL:pickedURL toURL:[NSURL fileURLWithPath:tempPath] error:&copyErr];

        if (scoped) [pickedURL stopAccessingSecurityScopedResource];

        if (copyErr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入失败" message:copyErr.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            });
            return;
        }

        BOOL ok = DBImportAccountFromPath(tempPath);
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (ok) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入成功"
                    message:@"账号信息已恢复，请重启抖音以生效。"
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *aa) {
                    exit(0);
                }]];
                [a addAction:[UIAlertAction actionWithTitle:@"稍后重启" style:UIAlertActionStyleCancel handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            } else {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入失败"
                    message:@"文件格式不正确或已损坏"
                    preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:a animated:YES completion:nil];
            }
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // Cleanup export temp if cancelled
    NSString *exportZip = objc_getAssociatedObject(self, "db_export_zip_path");
    if (exportZip) {
        objc_setAssociatedObject(self, "db_export_zip_path", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

// ============================================================
#pragma mark - Constructor
// ============================================================

%ctor {
    DBLog(@"DouyinBypass v2.1.0 loaded");
    DBLog(@"Features: bypass + account backup/restore + native settings injection");
    [[NSFileManager defaultManager] createDirectoryAtPath:BACKUP_DIR
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}
