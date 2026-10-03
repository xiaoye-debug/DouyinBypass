# DouyinBypass

iOS Tweak to bypass Douyin (TikTok China) version check and resign detection.

## Problem
When self-signing Douyin IPA on iOS 27, login fails with:
- "Application version too low"
- "System busy"

## Root Cause Analysis
Reverse engineered from AwemeCore.framework (968 MB):
1. BDUGCloudkitManager.isValidMobileProvision - checks TeamIdentifier in embedded.mobileprovision
2. AWEAccountForceUpgradeManager - triggers force upgrade for non-AppStore installs
3. isAppStoreChannel - returns NO for self-signed apps
4. AWEAppStoreMediator - validates App Store certificates
5. Server-side version/channel check via request headers

## Hooks
| Class | Method | Action |
|-------|--------|--------|
| BDUGCloudkitManager | isValidMobileProvision | return YES |
| BDUGCloudkitManager | setupCloudKit | skip |
| AWEAccountForceUpgradeManager | checkForceUpgrade | skip |
| AWEAccountForceUpgradeManager | showForceUpgradeDialog | block |
| AWEAccountForceUpgradeManager | shouldForceUpgrade | return NO |
| NSObject | isAppStoreChannel | return YES |
| AWEAppStoreMediator | openURL:completion: | bypass cert |
| AWEAppStoreMediator | initSKStoreProductVCWithCompletion: | bypass cert |
| TTAccountSDKSetup | startWithConfig: | proceed |

## GitHub Actions Auto-Build (Recommended)

This repo includes a GitHub Actions workflow that automatically builds the .deb on every push.

1. Push this repo to GitHub
2. Go to Actions tab - the build will run automatically
3. Download the .deb from the Artifacts section
4. Or create a git tag to auto-publish a Release with the .deb attached

```bash
# Create a release tag
git tag v1.0.0
git push origin v1.0.0
```

## Local Build (macOS)

```bash
# Install Theos
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
brew install ldid

# Build
make package FINALPACKAGE=1

# Output: packages/*.deb
```

## Install on Device

**Jailbroken:**
```
dpkg -i com.douyin.bypass_1.0.0_iphoneos-arm.deb
killall -9 Aweme
```

**Non-jailbroken (sideloading):**
1. Use Dopamine + TrollStore for tweak injection without jailbreak
2. Or use MonkeyDev/Xcode to inject DouyinBypass.dylib into the IPA
3. Re-sign with your certificate after injection

## Target Info
- Bundle ID: com.ss.iphone.ugc.Aweme
- Version: 40.4.0
- Minimum iOS: 18.0
- Architectures: arm64, arm64e

## File Structure
```
DouyinBypass/
  .github/workflows/build.yml  # GitHub Actions CI
  Tweak.xm                     # Core hook code (Logos syntax)
  Makefile                     # Theos build config
  control                      # DEB package metadata
  DouyinBypass.plist           # Substrate filter (target bundle)
  build.sh                     # Local build script
  .gitignore
  README.md
```

## Disclaimer
For educational and personal use only.
