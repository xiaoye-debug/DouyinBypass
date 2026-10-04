ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme AwemeLite

include $(THEOS)/makefiles/common.mk

# === Tweak (DEB for jailbreak) ===
TWEAK_NAME = DouyinBypass
DouyinBypass_FILES = Tweak.xm DBHelpers.m
DouyinBypass_CFLAGS = -fobjc-arc
DouyinBypass_FRAMEWORKS = Foundation UIKit Security UniformTypeIdentifiers

include $(THEOS_MAKE_PATH)/tweak.mk

# === Build dylib: just copy the already-linked tweak dylib ===
build-dylib:
	@echo "=== Building Dylib for IPA injection ==="
	@mkdir -p packages
	@DYLIB=$$(find .theos/obj -name "DouyinBypass.dylib" 2>/dev/null | head -1); \
	if [ -z "$$DYLIB" ]; then \
		echo "[ERROR] DouyinBypass.dylib not found in .theos/obj/. Run 'make package' first."; \
		exit 1; \
	fi; \
	cp "$$DYLIB" packages/DouyinBypass.dylib && \
	echo "[OK] Copied $$DYLIB -> packages/DouyinBypass.dylib" && \
	(command -v ldid >/dev/null 2>&1 && ldid -S packages/DouyinBypass.dylib || true)

# Build everything: deb + dylib
package-all: package build-dylib
	@echo ""
	@echo "=== Build Complete ==="
	@ls -la packages/
	@echo ""

after-install::
	install.exec "killall -9 Aweme"
