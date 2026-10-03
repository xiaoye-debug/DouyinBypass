ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DouyinBypass
DouyinBypass_FILES = Tweak.xm
DouyinBypass_CFLAGS = -fobjc-arc
DouyinBypass_FRAMEWORKS = Foundation UIKit Security

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Aweme"
