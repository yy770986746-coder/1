TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := com.jiangjia.gif
ARCHS := arm64 arm64e

# ★ 用 Theos 标准 rootless scheme（Dopamine 兼容）
#   Dopamine 是标准无根越狱，ElleKit 从 /var/jb/Library/MobileSubstrate/DynamicLibraries
#   加载插件，这是 Theos 的默认布局。
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KSDid
KSDid_FILES = KSDid.xm
KSDid_CFLAGS = -fobjc-arc
KSDid_LIBRARIES = substrate
KSDid_FRAMEWORKS = Foundation Security
KSDid_CODESIGN_FLAGS = -Sent.xml

include $(THEOS_MAKE_PATH)/tweak.mk
