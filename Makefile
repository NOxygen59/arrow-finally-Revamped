ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ArrowFinally

ArrowFinally_FILES = Tweak.xm
ArrowFinally_CFLAGS = -fobjc-arc -Wall -Wextra -Werror
ArrowFinally_FRAMEWORKS = Foundation CoreGraphics QuartzCore UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
