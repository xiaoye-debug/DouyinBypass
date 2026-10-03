#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

// DouyinBypass v1.0.0
// Target: com.ss.iphone.ugc.Aweme (Douyin 40.4.0)
// Bypass version check and resign detection for iOS 27 self-signed IPA

#define LOG_TAG @"[DouyinBypass]"
#define DBLog(fmt, ...) NSLog(@"%@ " fmt, LOG_TAG, ##__VA_ARGS__)

// === BDUGCloudkitManager: mobileprovision validation ===
@interface BDUGCloudkitManager : NSObject
- (BOOL)isValidMobileProvision;
- (void)setupCloudKit;
@end

%hook BDUGCloudkitManager
- (BOOL)isValidMobileProvision {
    DBLog(@"isValidMobileProvision -> YES (bypassed)");
    return YES;
}
- (void)setupCloudKit {
    DBLog(@"setupCloudKit -> skipped");
}
%end

// === AWEAccountForceUpgradeManager: force upgrade dialog ===
@interface AWEAccountForceUpgradeManager : NSObject
+ (instancetype)sharedInstance;
- (void)checkForceUpgrade;
- (void)showForceUpgradeDialog;
- (BOOL)shouldForceUpgrade;
@end

%hook AWEAccountForceUpgradeManager
- (void)checkForceUpgrade {
    DBLog(@"checkForceUpgrade -> skipped");
}
- (void)showForceUpgradeDialog {
    DBLog(@"showForceUpgradeDialog -> blocked");
}
- (BOOL)shouldForceUpgrade {
    DBLog(@"shouldForceUpgrade -> NO");
    return NO;
}
%end

// === isAppStoreChannel: pretend App Store install ===
%hook NSObject
- (BOOL)isAppStoreChannel {
    if ([self respondsToSelector:@selector(isAppStoreChannel)]) {
        DBLog(@"%@ isAppStoreChannel -> YES", NSStringFromClass([self class]));
        return YES;
    }
    return %orig;
}
%end

// === AWEAppStoreMediator: certificate validation ===
@interface AWEAppStoreMediator : NSObject
+ (instancetype)sharedInstance;
- (void)openURL:(NSURL *)url completion:(void(^)(BOOL))completion;
- (void)initSKStoreProductVCWithCompletion:(void(^)(id))completion;
@end

%hook AWEAppStoreMediator
- (void)openURL:(NSURL *)url completion:(void(^)(BOOL))completion {
    DBLog(@"AWEAppStoreMediator openURL -> bypass cert");
    if (completion) completion(YES);
}
- (void)initSKStoreProductVCWithCompletion:(void(^)(id))completion {
    DBLog(@"AWEAppStoreMediator initSKStore -> bypass cert");
    if (completion) completion(nil);
}
%end

// === TTAccountSDKSetup: account SDK init ===
@interface TTAccountSDKSetup : NSObject
+ (void)startWithConfig:(id)config;
@end

%hook TTAccountSDKSetup
+ (void)startWithConfig:(id)config {
    DBLog(@"TTAccountSDKSetup startWithConfig -> proceeding");
    %orig;
}
%end

%ctor {
    DBLog(@"DouyinBypass v1.0.0 loaded");
    DBLog(@"Bypassing: mobileprovision, force upgrade, channel, cert");
}
