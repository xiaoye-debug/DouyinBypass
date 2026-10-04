ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme AwemeLite

include $(THEOS)/makefiles/common.mk

# === Target 1: Tweak (DEB for jailbreak) ===
TWEAK_NAME = DouyinBypass
DouyinBypass_FILES = Tweak.xm DBHelpers.m
DouyinBypass_CFLAGS = -fobjc-arc
DouyinBypass_FRAMEWORKS = Foundation UIKit Security UniformTypeIdentifiers

include $(THEOS_MAKE_PATH)/tweak.mk

# === Build dylib manually (avoids library.mk stage issues on CI) ===
DYLIB_DIR = .theos/obj/dylib

$(DYLIB_DIR)/Tweak.xm.mm: Tweak.xm
	@mkdir -p $(DYLIB_DIR)
	$(THEOS_BIN_PATH)/logos.pl Tweak.xm > $@

$(DYLIB_DIR)/DouyinBypass.dylib: $(DYLIB_DIR)/Tweak.xm.mm DBHelpers.m
	$(TARGET_CC) -dynamiclib \
		-arch arm64 -arch arm64e \
		-miphoneos-version-min=15.0 \
		-fobjc-arc -fobjc-weak \
		-isysroot "$(THEOS_SDK_PATH)" \
		-I"$(THEOS_INCLUDE_PATH)" \
		-F"$(THEOS_VENDOR_LIB_PATH)" \
		-framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
		-lobjc -lsubstrate \
		-o $@ $^

build-dylib: $(DYLIB_DIR)/DouyinBypass.dylib
	@mkdir -p packages
	cp $< packages/DouyinBypass.dylib
	@if command -v ldid >/dev/null 2>&1; then ldid -S packages/DouyinBypass.dylib; fi
	@echo "[OK] packages/DouyinBypass.dylib ($$(ls -lh packages/DouyinBypass.dylib | awk '{print $$5}'))"

# Build everything: deb + dylib
package-all: package build-dylib
	@echo ""
	@echo "=== Build Complete ==="
	@ls -la packages/
	@echo ""

after-install::
	install.exec "killall -9 Aweme"
