# DouyinBypass

iOS Tweak to bypass Douyin / Douyin Lite version check and resign detection.
Supports **2 build targets** for different injection methods.

## Build Artifacts

| Artifact | Format | Use Case | Injection Method |
|----------|--------|----------|-----------------|
| DEB | .deb | Jailbroken devices | Substrate / Substitute / ElleKit auto-inject |
| Dylib | .dylib | Self-signed IPA | TrollStore / Dopamine / inject.sh script |

## GitHub Actions Auto-Build

Push to GitHub and all 2 artifacts are built automatically.
Download from **Actions -> Artifacts**:
- DouyinBypass-deb - for jailbreak
- DouyinBypass-dylib - for IPA injection

Create a tag to auto-publish a Release with all artifacts:
```bash
git tag v1.0.0
git push origin v1.0.0
```

## Local Build (macOS + Theos)

```bash
# Setup
export THEOS=$HOME/theos
git clone --recursive https://github.com/theos/theos.git $THEOS
brew install ldid insert_dylib

# Build all 2 artifacts
make package-all FINALPACKAGE=1

# Or build individually:
make package FINALPACKAGE=1          # DEB only
make package-dylib                    # Dylib only
```

## Usage

### 1. Jailbreak (DEB)
```
dpkg -i com.douyin.bypass_1.0.0_iphoneos-arm.deb
killall -9 Aweme
```

### 2. Self-signed IPA (Dylib injection)

**Option A: Using inject.sh (recommended)**
```bash
chmod +x inject.sh
./inject.sh douyin.ipa                          # ad-hoc sign
./inject.sh douyin.ipa patched.ipa              # custom output
./inject.sh douyin.ipa out.ipa 'iPhone Developer'  # with identity
```

**Option B: Manual injection**
1. Unzip IPA, copy DouyinBypass.dylib to Payload/Aweme.app/Frameworks/
2. Add load command: insert_dylib @executable_path/Frameworks/DouyinBypass.dylib Payload/Aweme.app/Aweme
3. Re-sign: codesign -fs - Payload/Aweme.app
4. Repackage: zip -qr patched.ipa Payload/
5. Install with AltStore / Sideloadly / TrollStore

**Option C: Using TrollStore / Dopamine**
- Use your tool's built-in deb/dylib injection feature
- Point it to the .deb or .dylib file


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

## Supported Apps
- com.ss.iphone.ugc.Aweme (Douyin)
- com.ss.iphone.ugc.aweme.lite (Douyin Lite)

## Target Info
- Version: 40.4.0
- Minimum iOS: 18.0
- Architectures: arm64, arm64e

## File Structure
```
DouyinBypass/
  .github/workflows/build.yml   # GitHub Actions CI (2 artifacts)
  Tweak.xm                      # Core hook code (Logos)
  Makefile                      # 2 build targets
  control                       # DEB metadata
  DouyinBypass.plist            # Substrate filter
  build.sh                      # Local build script
  inject.sh                     # IPA injection script
  .gitignore
  README.md
```

## Disclaimer
For educational and personal use only.
