ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme AwemeLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DouyinBypass
DouyinBypass_FILES = Tweak.xm DBHelpers.m
DouyinBypass_CFLAGS = -fobjc-arc -w
DouyinBypass_FRAMEWORKS = Foundation UIKit Security UniformTypeIdentifiers
DouyinBypass_LIBRARIES = z

include $(THEOS_MAKE_PATH)/tweak.mk

build-dylib:
	@echo "=== Building Dylib for IPA injection ==="
	@mkdir -p packages
	@DYLIB=$$(find .theos/obj -name "DouyinBypass.dylib" 2>/dev/null | head -1); \
	if [ -z "$$DYLIB" ]; then echo "[ERROR] not found"; exit 1; fi; \
	cp "$$DYLIB" packages/DouyinBypass.dylib && \
	echo "[OK] packages/DouyinBypass.dylib" && \
	(command -v ldid >/dev/null 2>&1 && ldid -S packages/DouyinBypass.dylib || true)

package-all: package build-dylib
	@echo ""
	@echo "=== Build Complete ==="
	@ls -la packages/
	@echo ""

after-install::
	install.exec "killall -9 Aweme"
