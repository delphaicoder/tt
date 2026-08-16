ARCHS = arm64 arm64e
TARGET := iphone:clang:14.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppOpenAnimation

AppOpenAnimation_FILES = Tweak.x
AppOpenAnimation_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AppOpenAnimation_FRAMEWORKS = UIKit CoreGraphics QuartzCore Foundation
# Can thiet: toolchain Linux cong dong dung de build tweak jailbreak sinh loi goi
# __cxa_guard_acquire/release (runtime C++) cho BAT KY bien static cuc bo nao trong
# ham, du la Objective-C thuan. Link them libc++abi de cung cap cac ham nay.
AppOpenAnimation_LDFLAGS = -lc++abi

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
