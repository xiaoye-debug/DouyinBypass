#import "DBHelpers.h"
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <spawn.h>
#include <sys/wait.h>

// v2.2: DBMenuItem and DBRealSection removed (no longer needed with AWESettingsViewModel pattern)

NSDictionary *DBExtractAccountData(void) {
    NSMutableDictionary *data = [NSMutableDictionary dictionary];

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

extern char **environ;

static int DBSpawnAndWait(const char *path, char *const argv[]) {
    pid_t pid;
    int status = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    if (status != 0) return -1;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static BOOL DBCreateZipFromDirectory(NSString *srcDir, NSString *dstZip) {
    const char *argv[] = {"/usr/bin/zip", "-r", "-j", [dstZip UTF8String], [srcDir UTF8String], NULL};
    int ret = DBSpawnAndWait("/usr/bin/zip", (char *const *)argv);
    return ret == 0 && [[NSFileManager defaultManager] fileExistsAtPath:dstZip];
}

static BOOL DBUnzipToDirectory(NSString *srcZip, NSString *dstDir) {
    [[NSFileManager defaultManager] createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];
    const char *argv[] = {"/usr/bin/unzip", "-o", [srcZip UTF8String], "-d", [dstDir UTF8String], NULL};
    int ret = DBSpawnAndWait("/usr/bin/unzip", (char *const *)argv);
    return ret == 0;
}

NSString *DBPrepareExportZip(void) {
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

BOOL DBImportAccountFromPath(NSString *zipPath) {
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

    NSDictionary *udData = accountData[@"userDefaults"];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in udData) [defaults setObject:udData[key] forKey:key];
    [defaults synchronize];

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

    NSArray *cookieData = accountData[@"cookies"];
    NSHTTPCookieStorage *ckStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
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
        if (cookie) [ckStorage setCookie:cookie];
    }

    [fm removeItemAtPath:tempDir error:nil];
    DBLog(@"Import complete from: %@", zipPath);
    return YES;
}

static BOOL _db_isAppStoreChannel(id self, SEL _cmd) {
    return YES;
}

void DBHookIsAppStoreChannel(void) {
    NSArray *classNames = @[
        @"AWEAppEnvironment", @"AWESecUserModel", @"AWEConfigManager",
        @"BDUGCloudkitManager", @"AWEAppStoreMediator", @"TTAccountSDKSetup"
    ];
    for (NSString *clsName in classNames) {
        Class cls = NSClassFromString(clsName);
        if (cls && [cls instancesRespondToSelector:@selector(isAppStoreChannel)]) {
            MSHookMessageEx(cls, @selector(isAppStoreChannel),
                           (IMP)_db_isAppStoreChannel, NULL);
            DBLog(@"Hooked isAppStoreChannel on %@", clsName);
        }
        if (cls && [cls respondsToSelector:@selector(isAppStoreChannel)]) {
            MSHookMessageEx(object_getClass(cls), @selector(isAppStoreChannel),
                           (IMP)_db_isAppStoreChannel, NULL);
            DBLog(@"Hooked +isAppStoreChannel on %@", clsName);
        }
    }
}

// AWEAppStoreMediator hooks (moved from .xm to avoid Logos block-type parsing issues)
typedef void (^DBBoolCompletion)(BOOL);
typedef void (^DBIdCompletion)(id);

static void _db_openURL(id self, SEL _cmd, NSURL *url, DBBoolCompletion completion) {
    if (completion) completion(YES);
}

static void _db_initSKStore(id self, SEL _cmd, DBIdCompletion completion) {
    if (completion) completion(nil);
}

void DBHookAppStoreMediator(void) {
    Class cls = NSClassFromString(@"AWEAppStoreMediator");
    if (!cls) return;
    MSHookMessageEx(cls, @selector(openURL:completion:), (IMP)_db_openURL, NULL);
    MSHookMessageEx(cls, @selector(initSKStoreProductVCWithCompletion:), (IMP)_db_initSKStore, NULL);
    DBLog(@"Hooked AWEAppStoreMediator openURL + initSKStore");
}



@interface DBDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@end

// ============================================================
#pragma mark - Settings Panel & Entry Item (DY-tools pattern)
// ============================================================

static UIViewController *DBTopViewController(void) {
    UIWindow *window = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
        }
        if (window) break;
    }
    if (!window) window = [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

void DBPresentControlPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = DBTopViewController();
        if (!presenter) return;

        UIAlertController *panel = [UIAlertController alertControllerWithTitle:@"DouyinBypass 账号管理"
            message:@"选择操作" preferredStyle:UIAlertControllerStyleActionSheet];

        [panel addAction:[UIAlertAction actionWithTitle:@"导出当前账号信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSString *zipPath = DBPrepareExportZip();
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!zipPath) {
                        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"导出失败" message:@"请检查日志" preferredStyle:UIAlertControllerStyleAlert];
                        [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [DBTopViewController() presentViewController:err animated:YES completion:nil];
                        return;
                    }
                    NSURL *fileURL = [NSURL fileURLWithPath:zipPath];
                    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[fileURL]];
                    picker.modalPresentationStyle = UIModalPresentationFormSheet;
                    objc_setAssociatedObject(picker, "db_export_zip_path", zipPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    // Use a delegate proxy to handle the picker result
                    DBDocumentPickerDelegate *del = [[DBDocumentPickerDelegate alloc] init];
                    picker.delegate = del;
                    objc_setAssociatedObject(picker, "db_delegate_retain", del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [DBTopViewController() presentViewController:picker animated:YES completion:nil];
                });
            });
        }]];

        [panel addAction:[UIAlertAction actionWithTitle:@"导入账号信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSArray<UTType *> *types = @[[UTType typeWithIdentifier:@"com.pkware.zip-archive"] ?: UTTypeData, UTTypeData];
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
            picker.modalPresentationStyle = UIModalPresentationFormSheet;
            picker.allowsMultipleSelection = NO;
            DBDocumentPickerDelegate *del = [[DBDocumentPickerDelegate alloc] init];
            picker.delegate = del;
            objc_setAssociatedObject(picker, "db_delegate_retain", del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [DBTopViewController() presentViewController:picker animated:YES completion:nil];
        }]];

        [panel addAction:[UIAlertAction actionWithTitle:@"查看备份列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
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
            NSString *msg = info.count > 0 ? [[info reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n\n"] : @"暂无备份文件";
            UIAlertController *list = [UIAlertController alertControllerWithTitle:@"备份列表" message:msg preferredStyle:UIAlertControllerStyleAlert];
            if (info.count > 0) {
                [list addAction:[UIAlertAction actionWithTitle:@"清除所有备份" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *aa) {
                    [fm removeItemAtPath:BACKUP_DIR error:nil];
                    [fm createDirectoryAtPath:BACKUP_DIR withIntermediateDirectories:YES attributes:nil error:nil];
                }]];
            }
            [list addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            [DBTopViewController() presentViewController:list animated:YES completion:nil];
        }]];

        [panel addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

        if (panel.popoverPresentationController) {
            panel.popoverPresentationController.sourceView = presenter.view;
            panel.popoverPresentationController.sourceRect = CGRectMake(presenter.view.bounds.size.width/2, presenter.view.bounds.size.height/2, 1, 1);
        }
        [presenter presentViewController:panel animated:YES completion:nil];
    });
}

// Document picker delegate (separate class to avoid block-in-.xm issues)

@implementation DBDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *exportZip = objc_getAssociatedObject(controller, "db_export_zip_path");
    if (exportZip) {
        objc_setAssociatedObject(controller, "db_export_zip_path", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *msg = [NSString stringWithFormat:@"已保存到:\n%@", urls.firstObject.path];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出成功" message:msg preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [DBTopViewController() presentViewController:a animated:YES completion:nil];
        return;
    }

    NSURL *pickedURL = urls.firstObject;
    if (!pickedURL) return;
    BOOL scoped = [pickedURL startAccessingSecurityScopedResource];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *tempPath = [BACKUP_DIR stringByAppendingPathComponent:@"import_picked.zip"];
        [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
        NSError *copyErr = nil;
        [[NSFileManager defaultManager] copyItemAtURL:pickedURL toURL:[NSURL fileURLWithPath:tempPath] error:&copyErr];
        if (scoped) [pickedURL stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (copyErr) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入失败" message:copyErr.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [DBTopViewController() presentViewController:a animated:YES completion:nil];
                return;
            }
            BOOL ok = DBImportAccountFromPath(tempPath);
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
            if (ok) {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入成功" message:@"账号信息已恢复，请重启抖音以生效。" preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *aa) { exit(0); }]];
                [a addAction:[UIAlertAction actionWithTitle:@"稍后重启" style:UIAlertActionStyleCancel handler:nil]];
                [DBTopViewController() presentViewController:a animated:YES completion:nil];
            } else {
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导入失败" message:@"文件格式不正确或已损坏" preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [DBTopViewController() presentViewController:a animated:YES completion:nil];
            }
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    objc_setAssociatedObject(controller, "db_export_zip_path", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

id DBMakeSettingsEntryItem(void) {
    Class itemClass = NSClassFromString(@"AWESettingItemModel");
    if (!itemClass) return nil;

    AWESettingItemModel *item = [itemClass new];
    item.identifier = @"DouyinBypassAccountManager";
    item.title = @"账号管理";
    item.subTitle = @"导出/导入账号登录信息";
    item.detail = @"v2.2";
    item.iconImageName = @"ic_gearsimplify_outlined_20";
    item.svgIconImageName = @"ic_gearsimplify_outlined_20";
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = NO;
    item.cellTappedBlock = ^{
        DBPresentControlPanel();
    };
    return item;
}

id DBMakeSettingsSection(id entryItem) {
    Class sectionClass = NSClassFromString(@"AWESettingSectionModel");
    if (!sectionClass || !entryItem) return nil;

    AWESettingSectionModel *section = [sectionClass new];
    section.sectionHeaderTitle = @"DouyinBypass";
    section.sectionHeaderHeight = 40.0;
    section.sectionFooterTitle = @"";
    section.type = 0;
    section.itemArray = @[entryItem];
    return section;
}

NSArray *DBInjectSettingsSections(NSArray *originalSections) {
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    // Check if already injected
    for (id section in originalSections) {
        NSArray *items = nil;
        @try { items = [section valueForKey:@"itemArray"]; } @catch (__unused NSException *e) {}
        for (id item in items) {
            NSString *identifier = nil;
            @try { identifier = [item valueForKey:@"identifier"]; } @catch (__unused NSException *e) {}
            if ([identifier isEqualToString:@"DouyinBypassAccountManager"]) return originalSections;
        }
    }

    id entry = DBMakeSettingsEntryItem();
    id section = DBMakeSettingsSection(entry);
    if (!entry || !section) return originalSections;

    NSMutableArray *result = [originalSections mutableCopy];
    if (!result) result = [NSMutableArray array];
    [result insertObject:section atIndex:0];
    return [result copy];
}



