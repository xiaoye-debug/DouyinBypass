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

# === Build dylib from already-compiled .o files (after tweak build) ===
build-dylib:
	@echo "=== Building Dylib for IPA injection ==="
	@mkdir -p packages
	@OBJDIR=$$(ls -d .theos/obj/*/ 2>/dev/null | head -1); \
	if [ -z "$$OBJDIR" ]; then echo "[ERROR] No compiled objects found. Run 'make package' first."; exit 1; fi; \
	OBJS=$$(find $$OBJDIR -name "*.o" ! -name "*.dylib" 2>/dev/null); \
	if [ -z "$$OBJS" ]; then echo "[ERROR] No .o files found in $$OBJDIR"; exit 1; fi; \
	echo "Linking: $$OBJS"; \
	$(TARGET_LD) -dylib \
		-arch arm64 \
		-miphoneos-version-min=15.0 \
		-syslibroot $(THEOS_SDK_PATH) \
		-F$(THEOS_VENDOR_LIB_PATH) \
		-framework Foundation -framework UIKit -framework Security -framework UniformTypeIdentifiers \
		-lobjc -lsubstrate \
		-o packages/DouyinBypass.dylib $$OBJS && \
	echo "[OK] packages/DouyinBypass.dylib" && \
	(command -v ldid >/dev/null 2>&1 && ldid -S packages/DouyinBypass.dylib || true)

# Build everything: deb + dylib
package-all: package build-dylib
	@echo ""
	@echo "=== Build Complete ==="
	@ls -la packages/
	@echo ""

after-install::
	install.exec "killall -9 Aweme"
