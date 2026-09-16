//
//  KSCore.h
//  iOS 快手上号器 —— 核心引擎
//
//  设计目标：一个 App 全搞定，不需要 PC / SSH / Mac 编译
//
//  原理（对标安卓版 KuaishouInjector）：
//    安卓: su → 写 /data/data/com.smile.gifmaker/shared_prefs/gifshow.xml
//    iOS : 平台权限进程 → 写 <快手沙盒>/Library/Preferences/com.jiangjia.gif.plist
//
//  关键：App 需带 platform-application entitlement（越狱机可用），
//        这样才能绕过沙盒写别的 App 的容器。
//

#ifndef KSCore_h
#define KSCore_h

#import <Foundation/Foundation.h>

#pragma mark - 常量

#define KS_VERSION          @"1.0.0"

/// 快手各版本 BundleID
#define KS_BID_MAIN         @"com.jiangjia.gif"
#define KS_BID_LITE         @"com.kuaishou.nebula"
#define KS_BID_OVERSEA      @"com.kwai.video"

/// 无根越狱前缀（Dopamine / palera1n rootless）
#define KS_JBROOT           @"/var/jb"

/// 五参分隔符
#define KS_SEP              @"----"

#pragma mark - 五参

@interface KSFive : NSObject

@property (nonatomic, copy) NSString *token;
@property (nonatomic, copy) NSString *salt;
@property (nonatomic, copy) NSString *did;      // 第3段：设备 ID（UUID）→ WeaponUUIDKey
@property (nonatomic, copy) NSString *egid;     // 第4段：DFP 设备指纹 → KS_OUTERID_KEY
@property (nonatomic, copy) NSString *apiSt;    // 第5段：api_st → Gif_ServiceToken
@property (nonatomic, copy) NSString *userIdFromToken; // 第1段尾部数字（账号 ID）
@property (nonatomic, copy) NSString *hToken;
@property (nonatomic, copy) NSString *passToken; // serviceToken（base64 protobuf）
/// 用户资料（可选，缺失时用安全默认值兜底，避免快手 UI 拿到 nil 崩溃）
@property (nonatomic, copy) NSString *nickName;
@property (nonatomic, copy) NSString *headUrl;

/// 从任意文本解析（五参行 / JSON / 键值对 / 中文破折号）
+ (instancetype)fromText:(NSString *)text;

/// 双参即可登录（与安卓版结论一致）
- (BOOL)usable;
/// token 格式 ^[0-9a-fA-F]{32}-\d+$
- (BOOL)validToken;
/// 从 token 尾部取 uid
- (NSString *)userId;

- (NSString *)toLine;
- (NSString *)toJSON;

@end

#pragma mark - 目标 App 探测

@interface KSTarget : NSObject

@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *dataContainer;   // 沙盒的 Data 容器
@property (nonatomic, copy) NSString *bundlePath;      // .app 路径
@property (nonatomic, copy) NSString *prefsPath;       // 目标 plist 完整路径
@property (nonatomic, copy) NSString *processName;     // 进程名

/// 扫设备上装的快手（支持新/老/海外版）
+ (instancetype)detect;
/// 指定 bundleID
+ (instancetype)forBundleID:(NSString *)bid;
/// 是否已安装
+ (BOOL)isInstalled:(NSString *)bid;
/// 本进程是否有 platform-application 权限
+ (BOOL)hasPlatformEntitlement;
/// 全部候选 bundleID
+ (NSArray<NSString *> *)allBundleIDs;
/// 查 .app 路径
+ (NSString *)bundlePathForBundleID:(NSString *)bid;
/// 从 .app 的 Info.plist 反查真实 bundleID
+ (NSString *)bundleIDFromAppPath:(NSString *)appPath;
/// 当前运行的快手进程名
+ (NSString *)runningProcessName;
/// 拉起快手
+ (BOOL)launch:(NSString *)bid;

@end

#pragma mark - 注入引擎

@interface KSInjector : NSObject

/// 上号主流程（全自动）
/// 1. 结束快手  2. 清理旧登录态  3. 写五参  4. 修权限  5. 拉起快手
/// @param progress 进度回调（主线程之外）
+ (BOOL)loginWithFive:(KSFive *)five
                target:(KSTarget *)target
              progress:(void (^)(NSString *step, BOOL ok))progress;

/// 只写五参，不重启（调试用）
+ (BOOL)writeOnly:(KSFive *)five target:(KSTarget *)target;

/// 读回当前生效的五参
+ (KSFive *)readCurrent:(KSTarget *)target;

/// 提取当前设备五参并拼接成一行（---- 分隔），同时写日志。失败返回 nil
+ (NSString *)currentFiveLine:(KSTarget *)target;

/// 只修改 did（设备标识），不改 token/salt 等其他参数
/// @param did 新的 did（标准 UUID，如 4C96E59A-0F12-47E8-B56B-FFB036C694CB）
/// @return 是否成功
+ (BOOL)changeDID:(NSString *)did target:(KSTarget *)target;

/// 只读：取出当前 did（不修改任何东西），失败返回 nil
+ (NSString *)currentDID:(KSTarget *)target;

/// 判断字符串是否为标准 UUID 格式
+ (BOOL)isUUID:(NSString *)s;

/// 清除登录态（回到未登录）
+ (BOOL)clearLogin:(KSTarget *)target;

/// 清空快手全部数据（等价 pm clear）
+ (BOOL)wipeAllData:(KSTarget *)target;

/// 结束快手进程
+ (void)killKuaishou;

/// 结束快手进程并轮询确认已退出（写 plist 前必须调用）
+ (BOOL)killKuaishouAndWait;

@end

#pragma mark - 日志

@interface KSLog : NSObject
+ (void)add:(NSString *)fmt, ...;
+ (NSArray<NSString *> *)all;
+ (void)clear;
+ (NSString *)dump;
@end

#endif /* KSCore_h */
