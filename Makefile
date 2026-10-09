TARGET := iphone:clang:latest:15.0
ARCHS := arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Griddy

Griddy_FILES = Tweak.x $(wildcard *.m)
Griddy_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
