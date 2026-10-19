TARGET := iphone:clang:16.5:16.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ArrowRevampedPrefs

ArrowRevampedPrefs_FILES = ARRRootListController.m
ArrowRevampedPrefs_FRAMEWORKS = UIKit
ArrowRevampedPrefs_PRIVATE_FRAMEWORKS = Preferences
ArrowRevampedPrefs_INSTALL_PATH = /Library/PreferenceBundles
ArrowRevampedPrefs_CFLAGS = -fobjc-arc -Wall -Wextra -Werror

include $(THEOS_MAKE_PATH)/bundle.mk
