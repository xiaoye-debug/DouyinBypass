ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme AwemeLite

include $(THEOS)/makefiles/common.mk

# === Target 1: Tweak (DEB for jailbreak) ===
TWEAK_NAME = DouyinBypass
DouyinBypass_FILES = Tweak.xm
DouyinBypass_CFLAGS = -fobjc-arc
DouyinBypass_FRAMEWORKS = Foundation UIKit Security

# === Target 2: Dynamic Library (for IPA injection) ===
LIBRARY_NAME = DouyinBypassLib
DouyinBypassLib_FILES = Tweak.xm
DouyinBypassLib_CFLAGS = -fobjc-arc
DouyinBypassLib_FRAMEWORKS = Foundation UIKit Security
DouyinBypassLib_INSTALL_PATH = /Library/Application Support/DouyinBypass

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/library.mk

# Package dylib for IPA injection
package-dylib::
	@mkdir -p packages
	@cp $(THEOS_OBJ_DIR)/libDouyinBypassLib.dylib packages/DouyinBypass.dylib 2>/dev/null || cp .theos/obj/debug/libDouyinBypassLib.dylib packages/DouyinBypass.dylib 2>/dev/null || true
	@if [ -f packages/DouyinBypass.dylib ]; then echo "[OK] packages/DouyinBypass.dylib"; ldid -S packages/DouyinBypass.dylib; else echo "[WARN] dylib not found"; fi

# Build everything: deb + dylib
package-all::
	@$(MAKE) package FINALPACKAGE=1
	@$(MAKE) package-dylib
	@echo ""
	@echo "=== Build Complete ==="
	@echo "  DEB:   packages/*.deb"
	@echo "  Dylib: packages/DouyinBypass.dylib"
	@echo ""

after-install::
	install.exec "killall -9 Aweme"
