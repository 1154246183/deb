TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = CocoaTop

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CocoaTopAN

CocoaTopAN_FILES = Tweak.x
CocoaTopAN_CFLAGS = -fobjc-arc
CocoaTopAN_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 CocoaTop || true"
