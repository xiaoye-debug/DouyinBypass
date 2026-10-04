#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "DBHelpers.h"

// DouyinBypass v2.2.1

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
#pragma mark - Settings Injection (DY-tools pattern)
// ============================================================

%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *sections = %orig;
    return DBInjectSettingsSections(sections);
}
%end

// ============================================================
#pragma mark - Constructor
// ============================================================

%ctor {
    DBLog(@"DouyinBypass v2.2.1 loaded");
    DBGetBackupDir();
    DBHookIsAppStoreChannel();
    DBHookAppStoreMediator();
    DBLog(@"All hooks installed");
}
