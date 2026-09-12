#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS 快手上号器 —— 工程生成与打包

产出两种可用形态：
  A. Theos 工程（theos_build/）—— 越狱机上直接 make package，最省事
  B. Xcode 工程（xcode_project/）—— Mac 上用 Xcode 编译，再 ldid 签名

目标设备：无根越狱（Dopamine / palera1n），iOS 15-16
安装路径：/var/jb/Applications/KSExtract.app

用法：
  python build_app.py              # 生成 Theos 工程 + Xcode 工程 + deb 骨架
  python build_app.py --theos      # 只要 Theos 工程
  python build_app.py --xcode      # 只要 Xcode 工程
"""
import argparse
import io
import os
import shutil
import struct
import sys
import tarfile
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
APP_SRC = os.path.join(ROOT, "app")
THEOS_DIR = os.path.join(ROOT, "theos_build")
XCODE_DIR = os.path.join(ROOT, "xcode_project")
OUT = os.path.join(ROOT, "build")

APP_NAME = "KSExtract"
DISPLAY_NAME = "快手上号器"
BUNDLE_ID = "com.kuaishou.ioslogin"
VERSION = "1.0.0"
PKG_ID = "com.kuaishou.ioslogin"

# deb 架构字段。
# 注意：设备 dpkg 的「system arch」在新机上常显示 iphoneos-arm64e，
# 若包声明 iphoneos-arm64，dpkg -i 会直接拒绝：
#   package architecture (iphoneos-arm64) does not match system (iphoneos-arm64e)
# 而编出来的 Mach-O 实际是 arm64（arm64e 系统可正常执行 arm64）。
# 所以这里用 iphoneos-arm64e 以通过 dpkg 校验；Sileo 两种都接受。
# 可用环境变量 KS_DEB_ARCH 覆盖。
ARCH = os.environ.get("KS_DEB_ARCH", "iphoneos-arm64e")

# 无根越狱安装前缀
JB_ROOT = "/var/jb"

# ==================================================================
# entitlements —— 关键：platform-application 让 App 有平台权限
# ==================================================================

ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.security.no-container</key>
    <true/>
    <key>com.apple.private.security.container-required</key>
    <false/>
    <key>task_for_pid-allow</key>
    <true/>
    <key>get-task-allow</key>
    <true/>
    <key>com.apple.private.skip-library-validation</key>
    <true/>
    <key>com.apple.private.security.no-sandbox</key>
    <true/>
    <key>com.apple.private.mobileinstall.allowedSPI</key>
    <array>
        <string>Install</string>
        <string>Lookup</string>
        <string>Uninstall</string>
    </array>
    <key>com.apple.springboard.launchapplications</key>
    <true/>
    <key>com.apple.private.launchservices.allowopenwithanyhandler</key>
    <true/>
</dict>
</plist>
"""

INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>%(exe)s</string>
    <key>CFBundleIdentifier</key>
    <string>%(bid)s</string>
    <key>CFBundleName</key>
    <string>%(name)s</string>
    <key>CFBundleDisplayName</key>
    <string>%(name)s</string>
    <key>CFBundleVersion</key>
    <string>%(ver)s</string>
    <key>CFBundleShortVersionString</key>
    <string>%(ver)s</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>MinimumOSVersion</key>
    <string>14.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <!-- ★ 启动必需：缺这些 SpringBoard 会拒绝拉起，表现为"点了没反应" -->
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>DTPlatformName</key>
    <string>iphoneos</string>
    <key>DTPlatformVersion</key>
    <string>16.1</string>
    <key>DTSDKName</key>
    <string>iphoneos16.1</string>
    <!-- ★ 图标：没有图标桌面会显示白板，部分系统直接不显示 -->
    <key>CFBundleIcons</key>
    <dict>
        <key>CFBundlePrimaryIcon</key>
        <dict>
            <key>CFBundleIconFiles</key>
            <array>
                <string>AppIcon60x60</string>
            </array>
            <key>CFBundleIconName</key>
            <string>AppIcon</string>
        </dict>
    </dict>
    <!-- ★ 空字符串会导致启动异常，用系统默认启动页 -->
    <key>UILaunchScreen</key>
    <dict/>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
    </array>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>UISupportedInterfaceOrientations~iphone</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>LSApplicationQueriesSchemes</key>
    <array>
        <string>com.jiangjia.gif</string>
        <string>com.kuaishou.nebula</string>
        <string>com.kwai.video</string>
        <string>kwai</string>
    </array>
    <key>NSAppleMusicUsageDescription</key>
    <string>用于设备信息读取</string>
</dict>
</plist>
""" % {"exe": APP_NAME, "bid": BUNDLE_ID, "name": DISPLAY_NAME, "ver": VERSION}


# ==================================================================
# A. Theos 工程
# ==================================================================

def gen_theos():
    if os.path.isdir(THEOS_DIR):
        shutil.rmtree(THEOS_DIR)
    base = os.path.join(THEOS_DIR, "ksextract")
    os.makedirs(base)

    # Makefile —— 编译成普通 App，带平台 entitlements
    makefile = """ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = %(exe)s

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = %(exe)s

%(exe)s_FILES = main.m KSCore.m
%(exe)s_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations
%(exe)s_FRAMEWORKS = UIKit Foundation Security
%(exe)s_PRIVATE_FRAMEWORKS = MobileCoreServices
%(exe)s_CODESIGN_FLAGS = -S%(ent)s
%(exe)s_INSTALL_PATH = %(jr)s/Applications

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "uicache -a || uicache || true"
""" % {"exe": APP_NAME, "ent": "entitlements.plist", "jr": JB_ROOT}
    _w(os.path.join(base, "Makefile"), makefile)
    _w(os.path.join(base, "entitlements.plist"), ENTITLEMENTS)
    _w(os.path.join(base, "Info.plist"), INFO_PLIST)

    for f in ("main.m", "KSCore.h", "KSCore.m"):
        s = os.path.join(APP_SRC, f)
        if os.path.exists(s):
            shutil.copy2(s, os.path.join(base, f))

    # control（Theos 会自动打包）
    _w(os.path.join(base, "control"), """Package: %s
Name: %s
Version: %s
Architecture: %s
Description: 快手 iOS 上号器 —— 粘贴五参一键登录
Maintainer: momo
Author: momo
Section: Utilities
Depends: firmware (>= 14.0)
Installed-Size: 512
""" % (PKG_ID, DISPLAY_NAME, VERSION, ARCH))

    print("[Theos] 工程: %s" % base)
    print("        越狱机上: cd %s && make package" % base)
    return base


# ==================================================================
# B. Xcode 工程
# ==================================================================

def gen_xcode():
    if os.path.isdir(XCODE_DIR):
        shutil.rmtree(XCODE_DIR)
    os.makedirs(XCODE_DIR)

    for f in ("main.m", "KSCore.h", "KSCore.m"):
        s = os.path.join(APP_SRC, f)
        if os.path.exists(s):
            shutil.copy2(s, os.path.join(XCODE_DIR, f))

    _w(os.path.join(XCODE_DIR, "Info.plist"), INFO_PLIST)
    _w(os.path.join(XCODE_DIR, "entitlements.plist"), ENTITLEMENTS)

    # 手工构造的 project.pbxproj（够用即可）
    pbx = _xcode_pbxproj()
    os.makedirs(os.path.join(XCODE_DIR, "%s.xcodeproj" % APP_NAME), exist_ok=True)
    _w(os.path.join(XCODE_DIR, "%s.xcodeproj" % APP_NAME, "project.pbxproj"), pbx)

    # ★ shared scheme —— 没有它，CI 上 xcodebuild -scheme 会直接报 scheme not found
    _w(os.path.join(XCODE_DIR, "%s.xcodeproj" % APP_NAME,
                    "xcshareddata", "xcschemes", "%s.xcscheme" % APP_NAME),
       _xcode_scheme())

    _w(os.path.join(XCODE_DIR, "编译说明.txt"), """iOS 快手上号器 —— Xcode 编译步骤
========================================

1. 打开 xcode_project/%s.xcodeproj

2. 设置签名（重要）：
   Signing & Capabilities → 取消勾选 "Automatically manage signing"
   然后手动选择你的证书（没有就选 "Sign to Run Locally"）

3. 编译：Product → Archive → Export
   或者命令行：
     xcodebuild -project %s.xcodeproj -scheme %s \\
                -sdk iphoneos -configuration Release \\
                CODE_SIGNING_ALLOWED=NO \\
                CONFIGURATION_BUILD_DIR=./out

4. 用 ldid 注入平台权限（关键，否则写不进快手沙盒）：
     ldid -Sentitlements.plist ./out/%s

5. 打包成 deb：
     python ../build_app.py --pack ./out/%s.app

6. 传到手机安装：
     爱思助手 → 越狱 → 安装 DEB
     或者 scp 到手机后 dpkg -i

说明：第 4 步不可省略。platform-application 权限是 App 能写别的
      App 沙盒的前提，对标安卓版的 su。
""" % (APP_NAME, APP_NAME, APP_NAME, APP_NAME, APP_NAME))

    print("[Xcode] 工程: %s" % XCODE_DIR)
    return XCODE_DIR


def _xcode_scheme():
    """共享 scheme —— CI 上 xcodebuild -scheme 必需"""
    return """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1400"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "AE0000000000000000000001"
               BuildableName = "{app}.app"
               BlueprintName = "{app}"
               ReferencedContainer = "container:{app}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Release"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Release"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AE0000000000000000000001"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "AE0000000000000000000001"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Release">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""".replace("{app}", APP_NAME)


def _xcode_pbxproj():
    """最小可用的 Xcode 工程文件"""
    return """// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 50;
	objects = {{

/* Begin PBXBuildFile section */
		AA0000000000000000000001 /* main.m in Sources */ = {{isa = PBXBuildFile; fileRef = AB0000000000000000000001 /* main.m */; }};
		AA0000000000000000000002 /* KSCore.m in Sources */ = {{isa = PBXBuildFile; fileRef = AB0000000000000000000002 /* KSCore.m */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		AB0000000000000000000001 /* main.m */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = main.m; sourceTree = "<group>"; }};
		AB0000000000000000000002 /* KSCore.m */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = KSCore.m; sourceTree = "<group>"; }};
		AB0000000000000000000003 /* KSCore.h */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = KSCore.h; sourceTree = "<group>"; }};
		AB0000000000000000000004 /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		AB0000000000000000000005 /* entitlements.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = entitlements.plist; sourceTree = "<group>"; }};
		AB0000000000000000000006 /* {app}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {app}.app; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		AC0000000000000000000001 /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AD0000000000000000000001 = {{
			isa = PBXGroup;
			children = (
				AB0000000000000000000001 /* main.m */,
				AB0000000000000000000002 /* KSCore.m */,
				AB0000000000000000000003 /* KSCore.h */,
				AB0000000000000000000004 /* Info.plist */,
				AB0000000000000000000005 /* entitlements.plist */,
				AD0000000000000000000002 /* Products */,
			);
			sourceTree = "<group>";
		}};
		AD0000000000000000000002 /* Products */ = {{
			isa = PBXGroup;
			children = (
				AB0000000000000000000006 /* {app}.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AE0000000000000000000001 /* {app} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = AF0000000000000000000002 /* Build configuration list for PBXNativeTarget "{app}" */;
			buildPhases = (
				AC0000000000000000000002 /* Sources */,
				AC0000000000000000000001 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = {app};
			productName = {app};
			productReference = AB0000000000000000000006 /* {app}.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AE0000000000000000000002 /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				LastUpgradeCheck = 1400;
				TargetAttributes = {{
					AE0000000000000000000001 = {{
						CreatedOnToolsVersion = 14.0;
					}};
				}};
			}};
			buildConfigurationList = AF0000000000000000000001 /* Build configuration list for PBXProject "{app}" */;
			compatibilityVersion = "Xcode 9.3";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = AD0000000000000000000001;
			productRefGroup = AD0000000000000000000002 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AE0000000000000000000001 /* {app} */,
			);
		}};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		AC0000000000000000000002 /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000002 /* KSCore.m in Sources */,
				AA0000000000000000000001 /* main.m in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		B0000000000000000000000001 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ARCHS = arm64;
				CLANG_ENABLE_OBJC_ARC = YES;
				GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
				IPHONEOS_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
			}};
			name = Debug;
		}};
		B0000000000000000000000002 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ARCHS = arm64;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = iphoneos;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		B0000000000000000000000003 /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_ENTITLEMENTS = entitlements.plist;
				INFOPLIST_FILE = Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = {bid};
				PRODUCT_NAME = "$(TARGET_NAME)";
				TARGETED_DEVICE_FAMILY = "1,2";
				FRAMEWORK_SEARCH_PATHS = ("$(inherited)", "$(SDKROOT)/System/Library/PrivateFrameworks");
			}};
			name = Debug;
		}};
		B0000000000000000000000004 /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "";
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CODE_SIGN_ENTITLEMENTS = entitlements.plist;
				INFOPLIST_FILE = Info.plist;
				PRODUCT_BUNDLE_IDENTIFIER = {bid};
				PRODUCT_NAME = "$(TARGET_NAME)";
				TARGETED_DEVICE_FAMILY = "1,2";
				FRAMEWORK_SEARCH_PATHS = ("$(inherited)", "$(SDKROOT)/System/Library/PrivateFrameworks");
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AF0000000000000000000001 /* Build configuration list for PBXProject "{app}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				B0000000000000000000000001 /* Debug */,
				B0000000000000000000000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		AF0000000000000000000002 /* Build configuration list for PBXNativeTarget "{app}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				B0000000000000000000000003 /* Debug */,
				B0000000000000000000000004 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = AE0000000000000000000002 /* Project object */;
}}
""".replace("{app}", APP_NAME).replace("{bid}", BUNDLE_ID)


# ==================================================================
# C. 打包成 deb
# ==================================================================

def pack_deb(app_dir=None):
    """把已编译的 .app 打成无根越狱 deb；没有 .app 时出骨架包"""
    os.makedirs(OUT, exist_ok=True)

    ctl = """Package: %s
Name: %s
Version: %s
Architecture: %s
Description: 快手 iOS 上号器 —— 粘贴五参一键登录
Maintainer: momo
Author: momo
Section: Utilities
Depends: firmware (>= 14.0)
Installed-Size: 1024
""" % (PKG_ID, DISPLAY_NAME, VERSION, ARCH)

    ctl_buf = io.BytesIO()
    with tarfile.open(fileobj=ctl_buf, mode="w:gz") as tf:
        _tar_add(tf, "./control", ctl.encode())
        _tar_add(tf, "./postinst", (
            "#!/bin/bash\n"
            "echo '[KS] iOS 快手上号器已安装' >&2\n"
            "uicache -a 2>/dev/null || uicache 2>/dev/null || true\n"
            "exit 0\n").encode(), 0o755)
    control_tar = ctl_buf.getvalue()

    appd = "%s/Applications/%s.app" % (JB_ROOT.lstrip("/"), APP_NAME)

    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode="w:xz") as tf:
        if app_dir and os.path.isdir(app_dir):
            # ★ 打包前强制保证图标齐全 + Info.plist 是二进制格式，
            #   否则装到设备上桌面不显示图标（iOS 11+ 只从 bplist 读图标）。
            _write_icons(app_dir)
            _to_binary_plist(app_dir)
            # rel 以 .app 自身的父目录为基准，这样 rel 里天然带 "KSExtract.app/"
            app_root = os.path.dirname(os.path.abspath(app_dir))
            # 先写目录条目，保证 dpkg 解包时中间层级都存在
            for d in ("var", "var/jb", "var/jb/Applications", appd):
                _tar_add_dir(tf, d)
            for root, _dirs, files in os.walk(app_dir):
                for f in files:
                    full = os.path.join(root, f)
                    rel = os.path.relpath(os.path.abspath(full), app_root)
                    rel = rel.replace(os.sep, "/")
                    with open(full, "rb") as fh:
                        data = fh.read()
                    perm = _unix_perm(full, f)
                    _tar_add(tf, "%s/Applications/%s" % (JB_ROOT.lstrip("/"), rel),
                             data, perm)
            print("[打包] 已嵌入编译好的 App")
        else:
            for d in ("var", "var/jb", "var/jb/Applications", appd):
                _tar_add_dir(tf, d)
            _tar_add(tf, appd + "/Info.plist", INFO_PLIST.encode())
            _tar_add(tf, appd + "/entitlements.plist", ENTITLEMENTS.encode())
            _tar_add(tf, appd + "/README.txt",
                     ("此包为骨架，未嵌入可执行文件。\n"
                      "请先用 Theos 或 Xcode 编译 KSExtract 可执行文件，\n"
                      "再执行: python build_app.py --pack <KSExtract.app 路径>\n").encode())
            print("[打包] 骨架包（App 未编译）")

    data_tar = data_buf.getvalue()

    deb = _make_ar([("debian-binary", b"2.0\n"),
                    ("control.tar.gz", control_tar),
                    ("data.tar.xz", data_tar)])

    name = ("ks_%s_%s_%s.deb" % (APP_NAME, VERSION, ARCH)
            if not app_dir else "ks_%s_%s_%s_FULL.deb" % (APP_NAME, VERSION, ARCH))
    path = os.path.join(OUT, name)
    with open(path, "wb") as f:
        f.write(deb)
    print("[打包] %s  (%.1f KB)" % (path, os.path.getsize(path) / 1024.0))
    return path


def _unix_perm(full, basename):
    """推断文件在 deb 里的 Unix 权限。

    Windows 上 os.stat 的 st_mode 不携带 Unix 权限位（永远 0o666），
    直接用会导致装到手机上 App 没有执行权限、点了没反应。
    """
    # 1) 非 Windows：直接信真实的权限位
    if os.name != "nt":
        mode = os.stat(full).st_mode & 0o777
        if mode:
            return mode

    # 2) 主可执行文件必须 0755
    if basename == APP_NAME:
        return 0o755

    # 3) 其他 Mach-O / dylib / 脚本
    if basename.endswith((".dylib", ".so")):
        return 0o755
    try:
        with open(full, "rb") as fh:
            magic = fh.read(4)
        # Mach-O / FAT 魔数
        if magic in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
                     b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
            return 0o755
        if magic[:2] == b"#!":
            return 0o755
    except OSError:
        pass

    # 4) plist / 资源：0644
    if basename.endswith((".plist", ".png", ".jpg", ".json", ".txt",
                          ".strings", ".car", ".nib", ".momd")):
        return 0o644
    return 0o644


def _tar_add_dir(tf, name, mode=0o755):
    """写一个目录条目"""
    info = tarfile.TarInfo(name.rstrip("/"))
    info.type = tarfile.DIRTYPE
    info.size = 0
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = "root"
    info.gname = "wheel"
    info.mtime = int(time.time())
    tf.addfile(info)


def _tar_add(tf, name, data, mode=0o644, uname="root", gname="wheel"):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = mode
    info.uid = 0
    info.gid = 0
    info.uname = uname
    info.gname = gname
    info.mtime = int(time.time())
    tf.addfile(info, io.BytesIO(data))


def _make_ar(members):
    buf = io.BytesIO()
    buf.write(b"!<arch>\n")
    for name, data in members:
        nm = (name + "/") if len(name) <= 15 else name
        hdr = nm.ljust(16)[:16].encode()
        hdr += str(int(time.time())).encode().ljust(12)[:12]
        hdr += b"0".ljust(6)[:6]
        hdr += b"0".ljust(6)[:6]
        hdr += b"100644".ljust(8)[:8]
        hdr += str(len(data)).encode().ljust(10)[:10]
        hdr += b"\x60\x0a"
        assert len(hdr) == 60
        buf.write(hdr)
        buf.write(data)
        if len(data) % 2:
            buf.write(b"\n")
    return buf.getvalue()


def _png_bytes(size, rgba_fill, bolt=True):
    """不依赖 Pillow 生成一个简单 PNG（纯 Python，用 zlib）"""
    import zlib, struct

    # 像素缓冲：每行前面 1 字节 filter
    w = h = size
    rows = []
    r, g, b, a = rgba_fill
    # 圆角半径
    rad = int(size * 0.22)
    for y in range(h):
        row = bytearray([0])  # filter type 0
        for x in range(w):
            # 圆角裁切
            inside = True
            if x < rad and y < rad:
                inside = (rad - x) ** 2 + (rad - y) ** 2 <= rad * rad
            elif x >= w - rad and y < rad:
                inside = (x - (w - rad - 1)) ** 2 + (rad - y) ** 2 <= rad * rad
            elif x < rad and y >= h - rad:
                inside = (rad - x) ** 2 + (y - (h - rad - 1)) ** 2 <= rad * rad
            elif x >= w - rad and y >= h - rad:
                inside = (x - (w - rad - 1)) ** 2 + (y - (h - rad - 1)) ** 2 <= rad * rad

            # 闪电形状（归一化坐标）
            px, py = x * 100.0 / size, y * 100.0 / size
            in_bolt = False
            if bolt and inside:
                poly = [(58, 12), (30, 56), (48, 56), (40, 88), (70, 42), (51, 42)]
                n = len(poly)
                j = n - 1
                for i in range(n):
                    xi, yi = poly[i]
                    xj, yj = poly[j]
                    if ((yi > py) != (yj > py)) and \
                       (px < (xj - xi) * (py - yi) / float(yj - yi) + xi):
                        in_bolt = not in_bolt
                    j = i

            if not inside:
                row += bytes((0, 0, 0, 0))
            elif in_bolt:
                row += bytes((255, 255, 255, 255))
            else:
                row += bytes((r, g, b, a))
        rows.append(bytes(row))

    raw = b"".join(rows)

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        c += struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        return c

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    return png


def _write_icons(app_dir):
    """把图标写进 .app（不依赖 Pillow），返回是否成功

    ★ 命名必须与能正常显示图标的越狱 app 一致（实测对比 RootHide/Sileo/Patcher）：
        AppIcon60x60@2x.png / AppIcon60x60@3x.png
        AppIcon76x76@2x.png
      iOS 只认这几档，多余的 @1x 反而无用。
    """
    try:
        targets = {
            "AppIcon60x60@2x.png": 120,
            "AppIcon60x60@3x.png": 180,
            "AppIcon76x76@2x.png": 152,
        }
        for name, sz in targets.items():
            with open(os.path.join(app_dir, name), "wb") as f:
                f.write(_png_bytes(sz, (255, 122, 0, 255)))
        return True
    except Exception as e:
        print("[图标] 生成失败: %s" % e)
        return False


def _to_binary_plist(app_dir):
    """把 .app/Info.plist 从 XML 转成二进制格式

    ★ 关键：实测对比发现，桌面能显示图标的越狱 app，Info.plist 全是 bplist00
      （二进制），而我们的包是 <?xml。iOS 11+ 的 SpringBoard 只从二进制 plist
      读取图标信息，XML 格式会导致 app 不显示在桌面。
    """
    import plistlib
    path = os.path.join(app_dir, "Info.plist")
    if not os.path.exists(path):
        print("[plist] Info.plist 不存在，跳过")
        return False
    with open(path, "rb") as f:
        head = f.read(8)
    if head.startswith(b"bplist"):
        print("[plist] 已是二进制格式")
        return True
    with open(path, "rb") as f:
        data = plistlib.load(f)
    with open(path, "wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
    print("[plist] 已转为二进制格式")
    return True


def _w(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)


# ==================================================================

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theos", action="store_true", help="只生成 Theos 工程")
    ap.add_argument("--xcode", action="store_true", help="只生成 Xcode 工程")
    ap.add_argument("--pack", metavar="APP_DIR", help="把编译好的 .app 打成 deb")
    ap.add_argument("--icons", metavar="APP_DIR", help="只给已编译的 .app 生成图标")
    args = ap.parse_args()

    if args.icons:
        ok = _write_icons(args.icons)
        print("[图标] %s" % ("已生成" if ok else "生成失败"))
        # ★ 图标生成了还不够：Info.plist 必须是二进制格式，否则桌面不显示
        _to_binary_plist(args.icons)
        return 0

    if args.pack:
        pack_deb(args.pack)
        return 0

    # 两个开关可以同时给，别用 return 把第二个吞掉
    only = args.theos or args.xcode
    if args.theos:
        gen_theos()
    if args.xcode:
        gen_xcode()
    if only:
        return 0

    gen_theos()
    gen_xcode()
    pack_deb()
    print("\n完成。下一步见 README_IOS.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
