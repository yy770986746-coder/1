TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := com.jiangjia.gif
ARCHS := arm64e

# ★ 不用 THEOS_PACKAGE_SCHEME := rootless
#   实测对比（能工作的 ksextract）：
#     deb 里路径是 /Library/MobileSubstrate/DynamicLibraries/xxx.dylib  （无 /var/jb 前缀）
#     control 里声明 Pre-Depends: rootless-compat (>= 0.9)
#     → 安装时 rootless-compat 会把路径转换成 /var/jb/... 并触发 RootHide 镜像到 pkgmirror
#   而我们用 rootless scheme 打出来的 deb 直接写 /var/jb/...，
#   RootHide 不会镜像，导致 ElleKit 不加载插件。
THEOS_PACKAGE_SCHEME :=

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KSDid
KSDid_FILES = KSDid.xm
KSDid_CFLAGS = -fobjc-arc
KSDid_LIBRARIES = substrate
KSDid_FRAMEWORKS = Foundation Security
KSDid_CODESIGN_FLAGS = -Sent.xml

include $(THEOS_MAKE_PATH)/tweak.mk
