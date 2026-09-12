ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = KSExtract

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = KSExtract

KSExtract_FILES = main.m KSCore.m
KSExtract_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations
KSExtract_FRAMEWORKS = UIKit Foundation
KSExtract_PRIVATE_FRAMEWORKS = MobileCoreServices
KSExtract_CODESIGN_FLAGS = -Sentitlements.plist
KSExtract_INSTALL_PATH = /var/jb/Applications

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache -a || uicache || true"
