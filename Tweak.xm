#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "DBHelpers.h"

// DouyinBypass v2.1.0
// All @interface declarations are in DBHelpers.h to avoid Logos block-parsing issues

// ============================================================
#pragma mark - Bypass Hooks
// ============================================================

%hook BDUGCloudkitManager
- (BOOL)isValidMobileProvision {
    return YES;
}
- (void)setupCloudKit {
}
%end

%hook AWEAccountForceUpgradeManager
- (void)checkForceUpgrade {
}
- (void)showForceUpgradeDialog {
}
- (BOOL)shouldForceUpgrade {
    return NO;
}
%end


%hook TTAccountSDKSetup
+ (void)startWithConfig:(id)config {
    %orig;
}
%end

// ============================================================
#pragma mark - Settings Section Injection (Native Style)
// ============================================================

%hook AWESettingsViewController

- (void)viewDidLoad {
    %orig;
    DBLog(@"Settings VC loaded, injecting native section");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    NSInteger orig = %orig;
    return orig + 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        return DB_SECTION_ROW_COUNT;
    }
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
        return @"\u266A DouyinBypass";
    }
    return %orig(tv, DBRealSection(section));
}

- (CGFloat)tableView:(UITableView *)tv heightForHeaderInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
        return UITableViewAutomaticDimension;
    }
    return %orig(tv, DBRealSection(section));
}

- (UIView *)tableView:(UITableView *)tv viewForHeaderInSection:(NSInteger)section {
    if (section == DB_INJECTED_SECTION) {
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
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.contentView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    return cell;
}

%new
- (void)db_handleInjectedSelection:(NSInteger)row fromVC:(UIViewController *)vc tableView:(UITableView *)tv {
    if (row == 0) {
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
                objc_setAssociatedObject(vc, "db_export_zip_path", zipPath, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [vc presentViewController:picker animated:YES completion:nil];
            });
        });
    }
    else if (row == 1) {
        NSArray<UTType *> *types = @[[UTType typeWithIdentifier:@"com.pkware.zip-archive"] ?: UTTypeData, UTTypeData];
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        picker.delegate = (id<UIDocumentPickerDelegate>)vc;
        picker.modalPresentationStyle = UIModalPresentationFormSheet;
        picker.allowsMultipleSelection = NO;
        [vc presentViewController:picker animated:YES completion:nil];
    }
    else if (row == 2) {
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

    NSString *msg = info.count > 0 ? [[info reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n\n"] : @"暂无备份文件\n\n请先导出账号信息";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"备份列表" message:msg preferredStyle:UIAlertControllerStyleAlert];

    if (info.count > 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"清除所有备份" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [fm removeItemAtPath:BACKUP_DIR error:nil];
            [fm createDirectoryAtPath:BACKUP_DIR withIntermediateDirectories:YES attributes:nil error:nil];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

%end

// ============================================================
#pragma mark - UIDocumentPickerDelegate
// ============================================================

%hook AWESettingsViewController

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSString *exportZip = objc_getAssociatedObject(self, "db_export_zip_path");
    if (exportZip) {
        objc_setAssociatedObject(self, "db_export_zip_path", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出成功"
            message:[NSString stringWithFormat:@"已保存到:\n%@", urls.firstObject.path]
            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
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
    DBHookIsAppStoreChannel();
    DBHookAppStoreMediator();
}



