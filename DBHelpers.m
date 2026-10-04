#import "DBHelpers.h"
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <zlib.h>

static NSString *DBAppDocumentsDir(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *DBAppLibraryDir(void) {
    return NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *DBCacheDir(void) {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tmp = NSTemporaryDirectory();
        if (!tmp) tmp = @"/tmp";
        dir = [tmp stringByAppendingPathComponent:@"DouyinBypass"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    });
    return dir;
}

NSString *DBGetBackupDir(void) { return DBCacheDir(); }

static NSArray *DBDocumentsIncludePaths(void) {
    return @[
        @"ttaccountSDKUserInfo.archiver", @"ttaccount_token_guard_data.archiver",
        @"tt_net_config.config", @"hostcache_v1", @"hostcache_sync_v1",
        @"bd.turing", @"bbox_acc", @"frontier_qos", @"poi_params_verify",
        @"applog.tttracker", @"kBDUGLocationCachePathName",
        @"Aweme.db", @"Aweme.db-shm", @"Aweme.db-wal",
        @"DBWorkspace", @"UserProfile", @"mmkv",
        @"kBDUGDeviceUnionCachePathname", @"BDUGFlowCacheManagerPathName",
        @"BDUGSyncSDK_kDocument", @"TIMXSDKWorkplace", @"IMFTS",
        @"AWEIMRoot/attachment", @"AWEIMRoot/Share",
        @"AWEIMRoot/IMUser", @"AWEIMRoot/UsersRoot",
        @"AWEIMRoot/incentive_chat_store_v2"
    ];
}

static NSArray *DBLibraryIncludePaths(void) {
    return @[
        @"loginData.dat", @"defaults.db", @"BDXBridgeAuthConfig",
        @"passportStorage", @"Cookies", @"Pitaya", @"tma", @"tmaABTest",
        @"alog", @"StarkContainer", @"AWEOfflineCenter", @"Jato",
        @"LaunchCache", @"IESWebViewMonitorX", @"AWEFeedCacheData",
        @"unisus/plugins", @"SyncedPreferences", @"unisus/settings", @"unisus/cloud",
        @"AWEIMRoot/IMUser", @"AWEIMRoot/UsersRoot",
        @"AWEIMRoot/incentive_chat_store_v2", @"AWEIMRoot/Sticker",
        @"AWEDataLayer/Data/Shared/Value", @"PIAMMKV",
        @"AWEStorage/FilePermanent",
        @"AWEStorage/UnifyStorage.sqlite", @"AWEStorage/UnifyStorage.sqlite-shm", @"AWEStorage/UnifyStorage.sqlite-wal",
        @"Preferences/BDXBridgeStorage.plist",
        @"Preferences/com.apple.AppAttest.client.plist",
        @"Preferences/com.apple.AdSupport.plist",
        @"Preferences/com.ss.iphone.ugc.Aweme.plist",
        @"Preferences/group.com.ss.iphone.ugc.Aweme.extension.plist",
        @"HTTPStorages/com.ss.iphone.ugc.Aweme",
        @"Preferences/bullet-133479643231288.plist"
    ];
}

static NSInteger DBCopyFilesFromRoot(NSString *rootDir, NSArray *includePaths, NSString *destDir, NSString *prefix) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSInteger count = 0;
    for (NSString *relPath in includePaths) {
        NSString *srcPath = [rootDir stringByAppendingPathComponent:relPath];
        NSString *dstPath = [destDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@/%@", prefix, relPath]];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:srcPath isDirectory:&isDir]) continue;
        if (isDir) {
            [fm createDirectoryAtPath:dstPath withIntermediateDirectories:YES attributes:nil error:nil];
            NSDirectoryEnumerator *en = [fm enumeratorAtPath:srcPath];
            NSString *sub;
            while ((sub = [en nextObject])) {
                NSString *ss = [srcPath stringByAppendingPathComponent:sub];
                NSString *sd = [dstPath stringByAppendingPathComponent:sub];
                BOOL sd2 = NO;
                if ([fm fileExistsAtPath:ss isDirectory:&sd2]) {
                    if (sd2) { [fm createDirectoryAtPath:sd withIntermediateDirectories:YES attributes:nil error:nil]; }
                    else { [fm createDirectoryAtPath:[sd stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]; [fm copyItemAtPath:ss toPath:sd error:nil]; count++; }
                }
            }
        } else {
            [fm createDirectoryAtPath:[dstPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
            if ([fm copyItemAtPath:srcPath toPath:dstPath error:nil]) count++;
        }
    }
    return count;
}

static NSInteger DBRestoreFilesToRoot(NSString *srcDir, NSString *rootDir, NSString *prefix) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *prefixDir = [srcDir stringByAppendingPathComponent:prefix];
    if (![fm fileExistsAtPath:prefixDir]) return 0;
    NSInteger count = 0;
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:prefixDir];
    NSString *rel;
    while ((rel = [en nextObject])) {
        NSString *sp = [prefixDir stringByAppendingPathComponent:rel];
        NSString *dp = [rootDir stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:sp isDirectory:&isDir]) {
            if (isDir) { [fm createDirectoryAtPath:dp withIntermediateDirectories:YES attributes:nil error:nil]; }
            else { [fm createDirectoryAtPath:[dp stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil]; [fm removeItemAtPath:dp error:nil]; if ([fm copyItemAtPath:sp toPath:dp error:nil]) count++; }
        }
    }
    return count;
}

static void DBW16(FILE *f, uint16_t v) { fwrite(&v, 2, 1, f); }
static void DBW32(FILE *f, uint32_t v) { fwrite(&v, 4, 1, f); }

typedef struct { char name[512]; uint32_t offset, size, compSize, crc; uint16_t nameLen; } DBZipEntry;

static NSData *DBDeflateData(NSData *input) {
    if (input.length == 0) return [NSData data];
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)input.bytes;
    strm.avail_in = (uInt)input.length;
    NSMutableData *out = [NSMutableData dataWithLength:deflateBound(&strm, (uLong)input.length)];
    strm.next_out = (Bytef *)out.mutableBytes;
    strm.avail_out = (uInt)out.length;
    if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) return nil;
    deflate(&strm, Z_FINISH);
    deflateEnd(&strm);
    out.length = strm.total_out;
    return out;
}

static BOOL DBCreateZip(NSString *srcDir, NSString *dstZip) {
    NSFileManager *fm = [NSFileManager defaultManager];
    FILE *zf = fopen([dstZip UTF8String], "wb");
    if (!zf) return NO;
    NSMutableArray *entries = [NSMutableArray array];
    NSDirectoryEnumerator *en = [fm enumeratorAtPath:srcDir];
    NSString *rel;
    while ((rel = [en nextObject])) {
        NSString *fp = [srcDir stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:fp isDirectory:&isDir] || isDir) continue;
        NSData *d = [NSData dataWithContentsOfFile:fp];
        if (!d) continue;
        NSData *comp = DBDeflateData(d);
        if (!comp) comp = d; // fallback to store
        uint16_t compMethod = (comp.length < d.length) ? 8 : 0;
        NSData *writeData = (compMethod == 8) ? comp : d;

        DBZipEntry e; memset(&e, 0, sizeof(e));
        strncpy(e.name, [rel UTF8String], sizeof(e.name)-1);
        e.nameLen = (uint16_t)strlen(e.name);
        e.size = (uint32_t)d.length;
        e.compSize = (uint32_t)writeData.length;
        e.crc = (uint32_t)crc32(crc32(0L, Z_NULL, 0), (const Bytef *)d.bytes, (uInt)d.length);
        e.offset = (uint32_t)ftell(zf);

        DBW32(zf, 0x04034b50); DBW16(zf, 20); DBW16(zf, 0); DBW16(zf, compMethod);
        DBW16(zf, 0); DBW16(zf, 0);
        DBW32(zf, e.crc); DBW32(zf, e.compSize); DBW32(zf, e.size);
        DBW16(zf, e.nameLen); DBW16(zf, 0);
        fwrite(e.name, 1, e.nameLen, zf);
        fwrite(writeData.bytes, 1, writeData.length, zf);
        [entries addObject:[NSValue valueWithBytes:&e objCType:@encode(DBZipEntry)]];
    }
    uint32_t cdOff = (uint32_t)ftell(zf);
    for (NSValue *v in entries) {
        DBZipEntry e; [v getValue:&e];
        uint16_t cm = (e.compSize < e.size) ? 8 : 0;
        DBW32(zf, 0x02014b50); DBW16(zf, 20); DBW16(zf, 20); DBW16(zf, 0); DBW16(zf, cm);
        DBW16(zf, 0); DBW16(zf, 0);
        DBW32(zf, e.crc); DBW32(zf, e.compSize); DBW32(zf, e.size);
        DBW16(zf, e.nameLen); DBW16(zf, 0); DBW16(zf, 0); DBW16(zf, 0); DBW16(zf, 0);
        DBW32(zf, 0); DBW32(zf, e.offset);
        fwrite(e.name, 1, e.nameLen, zf);
    }
    uint32_t cdSz = (uint32_t)ftell(zf) - cdOff;
    DBW32(zf, 0x06054b50); DBW16(zf, 0); DBW16(zf, 0);
    DBW16(zf, (uint16_t)entries.count); DBW16(zf, (uint16_t)entries.count);
    DBW32(zf, cdSz); DBW32(zf, cdOff); DBW16(zf, 0);
    fclose(zf);
    DBLog(@"ZIP created: %lu files", (unsigned long)entries.count);
    return YES;
}

static NSData *DBInflateData(const void *compData, size_t compSize, size_t uncompSize) {
    if (uncompSize == 0) return [NSData data];
    NSMutableData *out = [NSMutableData dataWithLength:uncompSize];
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in = (Bytef *)compData;
    strm.avail_in = (uInt)compSize;
    strm.next_out = (Bytef *)out.mutableBytes;
    strm.avail_out = (uInt)uncompSize;
    // -15 = raw deflate (no zlib/gzip header)
    if (inflateInit2(&strm, -15) != Z_OK) return nil;
    int ret = inflate(&strm, Z_FINISH);
    inflateEnd(&strm);
    if (ret != Z_STREAM_END && ret != Z_OK) return nil;
    out.length = strm.total_out;
    return out;
}

static BOOL DBExtractZip(NSString *zipPath, NSString *dstDir) {
    FILE *zf = fopen([zipPath UTF8String], "rb");
    if (!zf) { DBLog(@"Cannot open zip: %@", zipPath); return NO; }
    fseek(zf, 0, SEEK_END);
    long fsz = ftell(zf);
    DBLog(@"ZIP file size: %ld", fsz);
    if (fsz < 22) { DBLog(@"ZIP too small"); fclose(zf); return NO; }
    long ss = fsz - 65557; if (ss < 0) ss = 0;
    uint8_t *buf = (uint8_t *)malloc(fsz - ss);
    fseek(zf, ss, SEEK_SET);
    fread(buf, 1, fsz - ss, zf);
    long eo = -1;
    for (long i = (fsz-ss)-22; i >= 0; i--) {
        if (buf[i]==0x50 && buf[i+1]==0x4b && buf[i+2]==0x05 && buf[i+3]==0x06) { eo = ss+i; break; }
    }
    free(buf);
    if (eo < 0) { DBLog(@"EOCD not found"); fclose(zf); return NO; }
    DBLog(@"EOCD at offset: %ld", eo);
    fseek(zf, eo+10, SEEK_SET); // total entries
    uint16_t tot; fread(&tot, 2, 1, zf);
    fseek(zf, 6, SEEK_CUR);
    uint32_t cdOff; fread(&cdOff, 4, 1, zf);
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dstDir withIntermediateDirectories:YES attributes:nil error:nil];
    fseek(zf, cdOff, SEEK_SET);
    for (int i = 0; i < tot; i++) {
        uint32_t sig; fread(&sig, 4, 1, zf);
        if (sig != 0x02014b50) break;
        fseek(zf, 4, SEEK_CUR); // skip version made by + version needed
        // Read compression method from central directory
        uint16_t cdFlags, cdComp;
        fread(&cdFlags, 2, 1, zf);
        fread(&cdComp, 2, 1, zf);
        fseek(zf, 8, SEEK_CUR); // skip mod time/date + crc
        uint32_t csz; fread(&csz, 4, 1, zf);
        uint32_t usz; fread(&usz, 4, 1, zf);
        uint16_t nl, el, cl;
        fread(&nl, 2, 1, zf); fread(&el, 2, 1, zf); fread(&cl, 2, 1, zf);
        fseek(zf, 8, SEEK_CUR);
        uint32_t lho; fread(&lho, 4, 1, zf);
        char nm[1024] = {0}; fread(nm, 1, nl, zf);
        fseek(zf, el+cl, SEEK_CUR);
        long sv = ftell(zf);

        // Read local header to get actual compression info
        fseek(zf, lho+4, SEEK_SET);
        uint16_t lhFlags, lhComp;
        fread(&lhFlags, 2, 1, zf);
        fread(&lhComp, 2, 1, zf);
        fseek(zf, 12, SEEK_CUR); // skip crc + sizes + nameLen offset
        // Re-read from lho+26 for name/extra lengths
        fseek(zf, lho+26, SEEK_SET);
        uint16_t lnl, lel; fread(&lnl, 2, 1, zf); fread(&lel, 2, 1, zf);
        fseek(zf, lnl+lel, SEEK_CUR);

        // Use central directory values (more reliable than local header when data descriptor is used)
        uint16_t compMethod = cdComp;

        if (csz > 0 || usz > 0) {
            NSString *op = [dstDir stringByAppendingPathComponent:[NSString stringWithUTF8String:nm]];
            [fm createDirectoryAtPath:[op stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];

            if (compMethod == 0) {
                // Store: read directly
                uint8_t *dd = (uint8_t *)malloc(csz > 0 ? csz : usz);
                size_t readSize = csz > 0 ? csz : usz;
                fread(dd, 1, readSize, zf);
                FILE *of = fopen([op UTF8String], "wb");
                if (of) { fwrite(dd, 1, readSize, of); fclose(of); }
                free(dd);
            } else if (compMethod == 8) {
                // Deflate: read compressed data and inflate
                uint8_t *cd2 = (uint8_t *)malloc(csz);
                fread(cd2, 1, csz, zf);
                NSData *inflated = DBInflateData(cd2, csz, usz);
                free(cd2);
                if (inflated) {
                    [inflated writeToFile:op atomically:YES];
                } else {
                    DBLog(@"Inflate failed for: %s", nm);
                }
            } else {
                DBLog(@"Unsupported compression %d for: %s", compMethod, nm);
            }
        }
        fseek(zf, sv, SEEK_SET);
    }
    fclose(zf);
    DBLog(@"ZIP extracted: %d files to %@", tot, dstDir);
    return YES;
}

NSString *DBPrepareExportJson(void) {
    @try {
        NSString *cacheDir = DBCacheDir();
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:@"yyyyMMdd_HHmmss"];
        NSString *ts = [fmt stringFromDate:[NSDate date]];
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
        NSString *zipName = [NSString stringWithFormat:@"DouyinAccount_%@_%@_%@.zip", bid, ver, ts];
        NSString *zipPath = [cacheDir stringByAppendingPathComponent:zipName];
        NSString *stageDir = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"stage_%@", ts]];
        [[NSFileManager defaultManager] createDirectoryAtPath:stageDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSInteger dc = DBCopyFilesFromRoot(DBAppDocumentsDir(), DBDocumentsIncludePaths(), stageDir, @"Documents");
        NSInteger lc = DBCopyFilesFromRoot(DBAppLibraryDir(), DBLibraryIncludePaths(), stageDir, @"Library");
        DBLog(@"Staged: Docs=%ld Lib=%ld", (long)dc, (long)lc);
        NSDictionary *manifest = @{
            @"format": @"douyinbypass_account_backup_v1",
            @"created_at": @([[NSDate date] timeIntervalSince1970]),
            @"app_version": ver, @"bundle_id": bid,
            @"documents_file_count": @(dc), @"library_file_count": @(lc)
        };
        NSData *md = [NSJSONSerialization dataWithJSONObject:manifest options:NSJSONWritingPrettyPrinted error:nil];
        [md writeToFile:[stageDir stringByAppendingPathComponent:@"manifest.json"] atomically:YES];
        BOOL ok = DBCreateZip(stageDir, zipPath);
        [[NSFileManager defaultManager] removeItemAtPath:stageDir error:nil];
        if (!ok) return nil;
        DBLog(@"Export: %@ (%ld files)", zipPath, (long)(dc+lc));
        return zipPath;
    } @catch (NSException *e) { DBLog(@"Export exc: %@", e); return nil; }
}

BOOL DBImportAccountFromPath(NSString *filePath) {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) return NO;
        NSString *extDir = [DBCacheDir() stringByAppendingPathComponent:@"import_extract"];
        [[NSFileManager defaultManager] removeItemAtPath:extDir error:nil];
        if (!DBExtractZip(filePath, extDir)) { DBLog(@"Extract failed for: %@", filePath); return NO; }
        NSInteger dc = DBRestoreFilesToRoot(extDir, DBAppDocumentsDir(), @"Documents");
        NSInteger lc = DBRestoreFilesToRoot(extDir, DBAppLibraryDir(), @"Library");
        [[NSFileManager defaultManager] removeItemAtPath:extDir error:nil];
        DBLog(@"Import: Docs=%ld Lib=%ld", (long)dc, (long)lc);
        return (dc+lc) > 0;
    } @catch (NSException *e) { DBLog(@"Import exc: %@", e); return NO; }
}

static BOOL _db_isAppStoreChannel(id self, SEL _cmd) { return YES; }

void DBHookIsAppStoreChannel(void) {
    NSArray *names = @[@"AWEAppEnvironment", @"AWESecUserModel", @"AWEConfigManager",
                       @"BDUGCloudkitManager", @"AWEAppStoreMediator", @"TTAccountSDKSetup"];
    for (NSString *n in names) {
        Class c = NSClassFromString(n);
        if (c && [c instancesRespondToSelector:@selector(isAppStoreChannel)])
            MSHookMessageEx(c, @selector(isAppStoreChannel), (IMP)_db_isAppStoreChannel, NULL);
        if (c && [c respondsToSelector:@selector(isAppStoreChannel)])
            MSHookMessageEx(object_getClass(c), @selector(isAppStoreChannel), (IMP)_db_isAppStoreChannel, NULL);
    }
}

typedef void (^DBBoolCompletion)(BOOL);
typedef void (^DBIdCompletion)(id);
static void _db_openURL(id s, SEL c, NSURL *u, DBBoolCompletion cb) { if (cb) cb(YES); }
static void _db_initSK(id s, SEL c, DBIdCompletion cb) { if (cb) cb(nil); }

void DBHookAppStoreMediator(void) {
    Class c = NSClassFromString(@"AWEAppStoreMediator");
    if (!c) return;
    MSHookMessageEx(c, @selector(openURL:completion:), (IMP)_db_openURL, NULL);
    MSHookMessageEx(c, @selector(initSKStoreProductVCWithCompletion:), (IMP)_db_initSK, NULL);
}

@interface DBDocumentPickerDelegate : NSObject <UIDocumentPickerDelegate>
@property(nonatomic, copy) void (^completionBlock)(NSURL *url);
@property(nonatomic, copy) NSString *tempFilePath;
@end

@implementation DBDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.count > 0 && self.completionBlock) self.completionBlock(urls.firstObject);
    [self cleanupTempFile];
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)c { [self cleanupTempFile]; }
- (void)cleanupTempFile {
    if (self.tempFilePath && [[NSFileManager defaultManager] fileExistsAtPath:self.tempFilePath])
        [[NSFileManager defaultManager] removeItemAtPath:self.tempFilePath error:nil];
}
@end

static UIViewController *DBTopVC(void) {
    UIWindow *w = nil;
    for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
        if (s.activationState == UISceneActivationStateForegroundActive)
            for (UIWindow *ww in s.windows) { if (ww.isKeyWindow) { w = ww; break; } }
        if (w) break;
    }
    if (!w) w = [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

void DBPresentControlPanel(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIViewController *p = DBTopVC();
            if (!p) return;
            UIAlertController *panel = [UIAlertController alertControllerWithTitle:@"DouyinBypass 账号管理" message:@"选择操作" preferredStyle:UIAlertControllerStyleActionSheet];

            [panel addAction:[UIAlertAction actionWithTitle:@"导出当前账号信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                NSString *tmp = DBPrepareExportJson();
                if (!tmp) {
                    UIAlertController *e = [UIAlertController alertControllerWithTitle:@"导出失败" message:@"无法生成账号数据" preferredStyle:UIAlertControllerStyleAlert];
                    [e addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [DBTopVC() presentViewController:e animated:YES completion:nil]; return;
                }
                NSURL *u = [NSURL fileURLWithPath:tmp];
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                UIDocumentPickerViewController *pk = [[UIDocumentPickerViewController alloc] initWithURLs:@[u] inMode:UIDocumentPickerModeExportToService];
                #pragma clang diagnostic pop
                DBDocumentPickerDelegate *del = [[DBDocumentPickerDelegate alloc] init];
                del.tempFilePath = tmp;
                del.completionBlock = ^(NSURL *url) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"导出成功" message:[NSString stringWithFormat:@"已保存到:\n%@", url.path] preferredStyle:UIAlertControllerStyleAlert];
                        [ok addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [DBTopVC() presentViewController:ok animated:YES completion:nil];
                    });
                };
                static char k1; pk.delegate = del;
                objc_setAssociatedObject(pk, &k1, del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [DBTopVC() presentViewController:pk animated:YES completion:nil];
            }]];

            [panel addAction:[UIAlertAction actionWithTitle:@"导入账号信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                UIDocumentPickerViewController *pk = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.pkware.zip-archive", @"public.data"] inMode:UIDocumentPickerModeImport];
                #pragma clang diagnostic pop
                DBDocumentPickerDelegate *del = [[DBDocumentPickerDelegate alloc] init];
                del.completionBlock = ^(NSURL *url) {
                    if (!url) return;
                    BOOL sc = [url startAccessingSecurityScopedResource];
                    NSString *lp = [DBCacheDir() stringByAppendingPathComponent:@"import_picked.zip"];
                    [[NSFileManager defaultManager] removeItemAtPath:lp error:nil];
                    NSError *ce = nil;
                    [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:lp] error:&ce];
                    if (sc) [url stopAccessingSecurityScopedResource];
                    if (ce) { dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *e = [UIAlertController alertControllerWithTitle:@"导入失败" message:ce.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                        [e addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [DBTopVC() presentViewController:e animated:YES completion:nil]; }); return; }
                    BOOL ok = DBImportAccountFromPath(lp);
                    [[NSFileManager defaultManager] removeItemAtPath:lp error:nil];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (ok) {
                            UIAlertController *a2 = [UIAlertController alertControllerWithTitle:@"导入成功" message:@"账号信息已恢复，请重启抖音以生效。" preferredStyle:UIAlertControllerStyleAlert];
                            [a2 addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDefault handler:^(UIAlertAction *aa) { exit(0); }]];
                            [a2 addAction:[UIAlertAction actionWithTitle:@"稍后重启" style:UIAlertActionStyleCancel handler:nil]];
                            [DBTopVC() presentViewController:a2 animated:YES completion:nil];
                        } else {
                            UIAlertController *a2 = [UIAlertController alertControllerWithTitle:@"导入失败" message:@"文件格式不正确或已损坏" preferredStyle:UIAlertControllerStyleAlert];
                            [a2 addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            [DBTopVC() presentViewController:a2 animated:YES completion:nil];
                        }
                    });
                };
                static char k2; pk.delegate = del;
                objc_setAssociatedObject(pk, &k2, del, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [DBTopVC() presentViewController:pk animated:YES completion:nil];
            }]];

            [panel addAction:[UIAlertAction actionWithTitle:@"查看备份列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                NSFileManager *fm = [NSFileManager defaultManager];
                NSString *cd = DBCacheDir();
                NSArray *fs = [fm contentsOfDirectoryAtPath:cd error:nil];
                NSMutableArray *info = [NSMutableArray array];
                for (NSString *f in fs) {
                    if ([f hasSuffix:@".zip"]) {
                        NSDictionary *at = [fm attributesOfItemAtPath:[cd stringByAppendingPathComponent:f] error:nil];
                        NSDateFormatter *df = [[NSDateFormatter alloc] init]; df.dateFormat = @"yyyy-MM-dd HH:mm";
                        [info addObject:[NSString stringWithFormat:@"%@  (%.1f MB, %@)", f, at.fileSize/1024.0/1024.0, [df stringFromDate:at.fileModificationDate]]];
                    }
                }
                [info sortUsingSelector:@selector(compare:)];
                NSString *msg = info.count > 0 ? [[info reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n\n"] : @"暂无备份文件";
                UIAlertController *l = [UIAlertController alertControllerWithTitle:@"备份列表" message:msg preferredStyle:UIAlertControllerStyleAlert];
                if (info.count > 0) [l addAction:[UIAlertAction actionWithTitle:@"清除所有备份" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *aa) {
                    for (NSString *f in fs) { if ([f hasSuffix:@".zip"]) [fm removeItemAtPath:[cd stringByAppendingPathComponent:f] error:nil]; }
                }]];
                [l addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
                [DBTopVC() presentViewController:l animated:YES completion:nil];
            }]];

            [panel addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            if (panel.popoverPresentationController) {
                panel.popoverPresentationController.sourceView = p.view;
                panel.popoverPresentationController.sourceRect = CGRectMake(p.view.bounds.size.width/2, p.view.bounds.size.height/2, 1, 1);
            }
            [p presentViewController:panel animated:YES completion:nil];
        } @catch (NSException *e) { DBLog(@"Panel exc: %@", e); }
    });
}

id DBMakeSettingsEntryItem(void) {
    Class ic = NSClassFromString(@"AWESettingItemModel");
    if (!ic) return nil;
    AWESettingItemModel *item = [ic new];
    item.identifier = @"DouyinBypassAccountManager";
    item.title = @"账号管理";
    item.subTitle = @"导出/导入账号登录信息";
    item.detail = @"v3.0";
    item.iconImageName = @"ic_gearsimplify_outlined_20";
    item.svgIconImageName = @"ic_gearsimplify_outlined_20";
    item.cellType = 26;
    item.colorStyle = 0;
    item.isEnable = YES;
    item.isSwitchOn = NO;
    item.cellTappedBlock = ^{ DBPresentControlPanel(); };
    return item;
}

id DBMakeSettingsSection(id entryItem) {
    Class sc = NSClassFromString(@"AWESettingSectionModel");
    if (!sc || !entryItem) return nil;
    AWESettingSectionModel *s = [sc new];
    s.sectionHeaderTitle = @"DouyinBypass";
    s.sectionHeaderHeight = 40.0;
    s.sectionFooterTitle = @"";
    s.type = 0;
    s.itemArray = @[entryItem];
    return s;
}

NSArray *DBInjectSettingsSections(NSArray *orig) {
    if (![orig isKindOfClass:[NSArray class]]) return orig;
    for (id sec in orig) {
        NSArray *items = nil;
        @try { items = [sec valueForKey:@"itemArray"]; } @catch (__unused NSException *e) {}
        for (id it in items) {
            NSString *ident = nil;
            @try { ident = [it valueForKey:@"identifier"]; } @catch (__unused NSException *e) {}
            if ([ident isEqualToString:@"DouyinBypassAccountManager"]) return orig;
        }
    }
    id entry = DBMakeSettingsEntryItem();
    id section = DBMakeSettingsSection(entry);
    if (!entry || !section) return orig;
    NSMutableArray *r = [orig mutableCopy];
    if (!r) r = [NSMutableArray array];
    [r insertObject:section atIndex:0];
    return [r copy];
}





