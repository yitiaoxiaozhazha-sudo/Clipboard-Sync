TARGET := iphone:clang:16.5:13.0
INSTALL_TARGET_PROCESSES = SpringBoard

# Build rootless by default; set THEOS_PACKAGE_SCHEME=rootful for rootful
ifeq ($(THEOS_PACKAGE_SCHEME),)
THEOS_PACKAGE_SCHEME = rootless
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ClipboardSync

$(TWEAK_NAME)_FILES = Tweak.x ClipboardSync.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/aggregate.mk
