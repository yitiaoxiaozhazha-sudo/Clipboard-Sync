TARGET := iphone:clang:16.5:13.0
INSTALL_TARGET_PROCESSES = Preferences

ifeq ($(THEOS_PACKAGE_SCHEME),)
THEOS_PACKAGE_SCHEME = rootless
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ClipboardSyncPreferences

$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_FILES = CSRootListController.m
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk
