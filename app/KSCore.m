//
//  KSCore.m
//  iOS 快手上号器 —— 核心引擎实现
//

#import "KSCore.h"
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <spawn.h>
#import <signal.h>
#import <errno.h>
#import <Security/Security.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <unistd.h>

extern char **environ;

#pragma mark - ========== 日志 ==========

static NSMutableArray *gLog = nil;
static NSLock *gLock = nil;

@implementation KSLog

+ (void)initialize {
    if (self == [KSLog class]) {
        gLog = [NSMutableArray array];
        gLock = [NSLock new];
    }
}

+ (void)add:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@",
                      [df stringFromDate:[NSDate date]], msg];

    [gLock lock];
    [gLog addObject:line];
    [gLock unlock];
}

+ (NSArray *)all {
    [gLock lock];
    NSArray *c = [gLog copy];
    [gLock unlock];
    return c;
}

+ (void)clear {
    [gLock lock];
    [gLog removeAllObjects];
    [gLock unlock];
}

+ (NSString *)dump {
    return [[self all] componentsJoinedByString:@"\n"];
}

@end

#pragma mark - ========== 五参 ==========

@interface KSFive ()
@end

@implementation KSFive

+ (instancetype)fromText:(NSString *)text {
    if (!text.length) return nil;

    NSString *t = [text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return nil;

    // ---- 分隔符归一化 ----
    // 坑：不能链式 replace("----").replace("--")，SEP 本身是 "----"，
    //     会被第二轮再切一次导致字段错位。用正则一次扫描。
    NSRegularExpression *sepRe =
        [NSRegularExpression regularExpressionWithPattern:@"-{2,}|\u2014+|\u2013+"
                                                 options:0 error:NULL];
    NSString *norm = [sepRe stringByReplacingMatchesInString:t options:0
                                                       range:NSMakeRange(0, t.length)
                                                withTemplate:KS_SEP];

    // ---- JSON ----
    if ([norm hasPrefix:@"{"]) {
        NSDictionary *j = [NSJSONSerialization JSONObjectWithData:
                           [norm dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0 error:NULL];
        if ([j isKindOfClass:[NSDictionary class]]) {
            if (j[@"five"] && [j[@"five"] isKindOfClass:[NSString class]]) {
                KSFive *f = [self fromText:j[@"five"]];
                if (f) {
                    if (!f.token.length  && j[@"token"])  f.token  = j[@"token"];
                    if (!f.salt.length   && j[@"salt"])   f.salt   = j[@"salt"];
                    if (!f.did.length    && j[@"did"])    f.did    = j[@"did"];
                    if (!f.egid.length   && j[@"egid"])   f.egid   = j[@"egid"];
                    if (!f.apiSt.length  && j[@"api_st"]) f.apiSt  = j[@"api_st"];
                    return f;
                }
            }
            KSFive *f = [KSFive new];
            f.token = j[@"token"] ?: j[@"gifshow_token"] ?: @"";
            f.salt  = j[@"salt"] ?: j[@"client_salt"] ?: j[@"token_client_salt"] ?: @"";
            f.did   = j[@"did"] ?: @"";
            f.egid  = j[@"egid"] ?: @"";
            f.apiSt = j[@"api_st"] ?: @"";
            f.hToken  = j[@"h5Token"];
            f.passToken = j[@"passToken"];
            return f.token.length ? f : nil;
        }
    }

    // ---- 五参行 ----
    for (NSString *raw in [norm componentsSeparatedByCharactersInSet:
                           [NSCharacterSet newlineCharacterSet]]) {
        if (![raw containsString:KS_SEP]) continue;

        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *s in [raw componentsSeparatedByString:KS_SEP]) {
            NSString *v = [s stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
            if (v.length) [parts addObject:v];
        }
        if (parts.count < 2) continue;

        // ★ 严格照搬 token_v1.0.4.apk 中 KuaishouInjector.parseInput() 的逻辑：
        //     token = parts[0]（完整保留，形如 "32位hex-用户数字ID"）
        //     uid   = parts[0] 里最后一个 '-' 之后的部分，必须全是数字
        //     salt  = parts[1]，必须匹配 [a-fA-F0-9]{32}
        //   第 3/4/5 段在原工具里没有被使用（但保留下来便于写入备用键）。
        KSFive *f = [KSFive new];
        NSString *tokenField = parts[0];
        NSString *saltField  = parts[1];

        NSRange lastDash = [tokenField rangeOfString:@"-"
                                             options:NSBackwardsSearch];
        if (lastDash.location == NSNotFound) {
            [KSLog add:@"⚠ 第1段没有 '-'，无法取 uid，按原样处理"];
        }
        NSString *uid = tokenField;
        if (lastDash.location != NSNotFound &&
            lastDash.location + 1 < tokenField.length) {
            uid = [tokenField substringFromIndex:lastDash.location + 1];
        }

        // 校验（与原工具一致：uid 必须纯数字，salt 必须 32 位 hex）
        NSRegularExpression *numRe =
            [NSRegularExpression regularExpressionWithPattern:@"^\\d+$"
                                                     options:0 error:NULL];
        NSRegularExpression *hex32Re =
            [NSRegularExpression regularExpressionWithPattern:@"^[a-fA-F0-9]{32}$"
                                                     options:0 error:NULL];
        BOOL uidOK = [numRe numberOfMatchesInString:uid options:0
                                              range:NSMakeRange(0, uid.length)] > 0;
        BOOL saltOK = [hex32Re numberOfMatchesInString:saltField options:0
                                                 range:NSMakeRange(0, saltField.length)] > 0;
        [KSLog add:@"解析: token=%d字符 uid=%@(%@) salt=%@(%@)",
         (int)tokenField.length, uid, uidOK ? @"合法" : @"⚠非纯数字",
         saltField, saltOK ? @"合法" : @"⚠非32位hex"];

        // ★ 字段映射（用户确认的顺序：token / salt / did / egid / apiSt）
        f.token = tokenField;      // 第1段：完整 "32位hex-uid"
        f.salt  = saltField;       // 第2段：32位hex
        //  第3段 = did（UUID），提取器对应 WeaponUUIDKey
        //  第4段 = egid（DFP 设备指纹）
        //  第5段 = api_st（base64 protobuf，kuaishou.api.st）
        if (parts.count > 2) f.did       = parts[2];
        if (parts.count > 3) f.egid      = parts[3];
        if (parts.count > 4) f.apiSt     = parts[4];
        // uid 来自第1段尾部（"hex-uid" 里的 uid）
        f.userIdFromToken = uid;
        return f;
    }

    // ---- 键值对兜底 ----
    NSRegularExpression *kvRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"\\b(token|salt|did|egid|uid|api_st|client_salt|service_token|serviceToken)\\b\\s*[=:]\\s*([^\\s,;&\\n]+)"
                                                 options:NSRegularExpressionCaseInsensitive
                                                   error:NULL];
    NSArray *ms = [kvRe matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    if (ms.count) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (NSTextCheckingResult *m in ms) {
            if (m.numberOfRanges < 3) continue;
            NSString *k = [[text substringWithRange:[m rangeAtIndex:1]] lowercaseString];
            NSString *v = [text substringWithRange:[m rangeAtIndex:2]];
            v = [v stringByTrimmingCharactersInSet:
                 [NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
            d[k] = v;
        }
        KSFive *f = [KSFive new];
        f.token = d[@"token"] ?: @"";
        f.salt  = d[@"salt"] ?: d[@"client_salt"] ?: @"";
        f.did   = d[@"uid"] ?: d[@"did"] ?: @"";
        f.egid  = d[@"egid"] ?: @"";
        f.apiSt = d[@"api_st"] ?: @"";
        f.passToken = d[@"service_token"] ?: d[@"servicetoken"] ?: @"";
        return f.token.length ? f : nil;
    }

    return nil;
}

- (BOOL)validToken {
    if (!self.token.length) return NO;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"^[0-9a-fA-F]{32}-\\d+$"
                                                 options:0 error:NULL];
    return [re numberOfMatchesInString:self.token options:0
                                 range:NSMakeRange(0, self.token.length)] > 0;
}

- (BOOL)usable {
    // 双参即可登录（与安卓版 parseInput 的校验范围一致）
    if (![self validToken]) return NO;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:@"^[a-fA-F0-9]{32}$"
                                                 options:0 error:NULL];
    return [re numberOfMatchesInString:self.salt options:0
                                 range:NSMakeRange(0, self.salt.length)] > 0;
}

- (NSString *)userId {
    // uid 是第1段 "32位hex-数字" 里 '-' 之后的数字，解析时已单独存下
    NSRegularExpression *numRe =
        [NSRegularExpression regularExpressionWithPattern:@"^\\d+$"
                                                 options:0 error:NULL];
    if (self.userIdFromToken.length &&
        [numRe numberOfMatchesInString:self.userIdFromToken options:0
                                 range:NSMakeRange(0, self.userIdFromToken.length)]) {
        return self.userIdFromToken;
    }
    // 回退：直接从 token 尾部取
    if (self.token.length) {
        NSRange d = [self.token rangeOfString:@"-" options:NSBackwardsSearch];
        if (d.location != NSNotFound && d.location + 1 < self.token.length) {
            return [self.token substringFromIndex:d.location + 1];
        }
    }
    return @"未知";
}

- (NSString *)toLine {
    return [NSString stringWithFormat:@"%@%@%@%@%@%@%@%@%@",
            self.token ?: @"", KS_SEP,
            self.salt  ?: @"", KS_SEP,
            self.did   ?: @"", KS_SEP,
            self.egid  ?: @"", KS_SEP,
            self.apiSt ?: @""];
}

- (NSString *)toJSON {
    NSDictionary *d = @{
        @"token": self.token ?: @"", @"salt": self.salt ?: @"",
        @"did": self.did ?: @"", @"egid": self.egid ?: @"",
        @"api_st": self.apiSt ?: @"", @"five": [self toLine],
        @"uid": [self userId],
    };
    NSData *j = [NSJSONSerialization dataWithJSONObject:d
                                                options:NSJSONWritingPrettyPrinted error:NULL];
    return [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
}

@end

#pragma mark - ========== 目标探测 ==========

@implementation KSTarget

+ (NSArray<NSString *> *)allBundleIDs {
    return @[KS_BID_MAIN, KS_BID_LITE, KS_BID_OVERSEA];
}

/// 从 .app 的 Info.plist 反查真正的 bundleID
/// （有些版本/马甲包目录名和 bundleID 不一致，靠目录名匹配会漏）
/// 注意：只读 Info.plist 文件，不调任何私有 API —— 私有 API 在 iOS 15 上
///       极易因 selector 不响应而抛 unrecognized selector，直接 SIGABRT。
+ (NSString *)bundleIDFromAppPath:(NSString *)appPath {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [appPath stringByAppendingPathComponent:@"Info.plist"]];
    return info[@"CFBundleIdentifier"];
}

/// 容器归属：读容器根下的元数据 plist 拿 MCMMetadataIdentifier
+ (NSString *)identifierOfContainer:(NSString *)container {
    NSString *meta = [container stringByAppendingPathComponent:
                      @".com.apple.mobile_container_manager.metadata.plist"];
    NSDictionary *md = [NSDictionary dictionaryWithContentsOfFile:meta];
    return md[@"MCMMetadataIdentifier"];
}

/// 拿容器路径（纯文件系统遍历，不用私有 API）
+ (NSString *)containerForBundleID:(NSString *)bid {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
    ];

    for (NSString *root in roots) {
        NSError *err = nil;
        NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:&err];
        if (!dirs) {
            [KSLog add:@"  [沙盒] 读不了 %@ (%@)", root,
             err.localizedDescription ?: @"未知错误"];
            continue;
        }
        for (NSString *d in dirs) {
            NSString *container = [root stringByAppendingPathComponent:d];
            NSString *ident = [self identifierOfContainer:container];
            if ([ident isEqualToString:bid]) {
                [KSLog add:@"  [沙盒] 命中: %@", container];
                return container;
            }
        }
        [KSLog add:@"  [沙盒] %@ 下 %lu 个容器，未匹配", root,
         (unsigned long)dirs.count];
    }
    return nil;
}

+ (NSString *)bundlePathForBundleID:(NSString *)bid {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *roots = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
    ];
    for (NSString *root in roots) {
        NSError *err = nil;
        NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:&err];
        if (!dirs) {
            [KSLog add:@"  [安装] 读不了 %@ (%@)", root,
             err.localizedDescription ?: @"未知错误"];
            continue;
        }
        for (NSString *d in dirs) {
            NSString *sub = [root stringByAppendingPathComponent:d];
            // 1) 先按标准命名试（快路径）
            NSString *p = [sub stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"%@.app", bid]];
            if ([fm fileExistsAtPath:p]) return p;

            // 2) 扫这一层所有 .app，用 Info.plist 反查真实 bundleID
            //    ★ 快手真实情况：目录名 com_kwai_gif.app，bundleID com.jiangjia.gif
            NSArray *apps = [fm contentsOfDirectoryAtPath:sub error:NULL];
            for (NSString *a in apps) {
                if (![a hasSuffix:@".app"]) continue;
                NSString *ap = [sub stringByAppendingPathComponent:a];
                NSString *realBid = [self bundleIDFromAppPath:ap];
                if ([realBid isEqualToString:bid]) return ap;
            }
        }
    }
    return nil;
}

+ (BOOL)isInstalled:(NSString *)bid {
    return [self bundlePathForBundleID:bid] != nil;
}

/// 检查自己有没有 platform-application 权限
+ (BOOL)hasPlatformEntitlement {
    // 沙盒 App 读不了这个目录；能读就说明有平台权限
    NSArray *c = [[NSFileManager defaultManager]
                  contentsOfDirectoryAtPath:@"/var/mobile/Containers/Data/Application"
                  error:NULL];
    return c != nil;
}

+ (instancetype)forBundleID:(NSString *)bid {
    [KSLog add:@"[探测] 检查 %@ ...", bid];

    NSString *bp = [self bundlePathForBundleID:bid];
    if (!bp) {
        [KSLog add:@"  [安装] 没找到 %@.app", bid];
        return nil;
    }
    [KSLog add:@"  [安装] ✓ %@", bp];

    KSTarget *t = [KSTarget new];
    t.bundleID = bid;
    t.bundlePath = bp;

    // 用 Info.plist 里的真实 bundleID 覆盖（马甲包/目录名不一致时）
    NSString *realBid = [self bundleIDFromAppPath:bp];
    if (realBid.length && ![realBid isEqualToString:bid]) {
        [KSLog add:@"  [安装] 实际 bundleID 是 %@，已修正", realBid];
        t.bundleID = realBid;
    }

    t.dataContainer = [self containerForBundleID:t.bundleID];
    if (!t.dataContainer && ![t.bundleID isEqualToString:bid]) {
        // 换回传入的 bid 再试一次
        t.dataContainer = [self containerForBundleID:bid];
    }

    if (t.dataContainer) {
        t.prefsPath = [self prefsPathIn:t.dataContainer bundleID:t.bundleID];
    }

    // 进程名：可执行文件 basename
    t.processName = [bp.lastPathComponent stringByDeletingPathExtension];

    if (!t.dataContainer) {
        [KSLog add:@"  ⚠ 沙盒未定位，但 App 确实装了"];
    }
    return t;
}

/// 在容器里找偏好文件，兼容多种落盘位置
+ (NSString *)prefsPathIn:(NSString *)container bundleID:(NSString *)bid {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *cands = @[
        [NSString stringWithFormat:@"Library/Preferences/%@.plist", bid],
        [NSString stringWithFormat:@"Library/Preferences/%@.plist", KS_BID_MAIN],
        @"Library/Preferences/com.jiangjia.gif.plist",
        @"Library/Preferences/gifshow.plist",
    ];
    for (NSString *rel in cands) {
        NSString *p = [container stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:p]) {
            [KSLog add:@"  [沙盒] 偏好文件已存在: %@", rel];
            return p;
        }
    }
    // 都不存在就用标准路径（写入时会创建）
    NSString *dflt = [container stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"Library/Preferences/%@.plist", bid]];
    [KSLog add:@"  [沙盒] 偏好文件待创建: %@", dflt.lastPathComponent];
    return dflt;
}

/// 探测目标：装了 .app 就算找到（沙盒稍后单独处理）
+ (instancetype)detect {
    for (NSString *bid in [self allBundleIDs]) {
        KSTarget *t = [self forBundleID:bid];
        if (t) return t;   // ★ 不再要求 dataContainer 存在
    }
    return nil;
}

+ (NSString *)runningProcessName {
    // 枚举进程找快手的可执行文件名
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0) return nil;
    struct kinfo_proc *procs = malloc(len);
    if (!procs) return nil;
    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) { free(procs); return nil; }

    NSUInteger n = len / sizeof(struct kinfo_proc);
    NSString *found = nil;
    for (NSUInteger i = 0; i < n; i++) {
        NSString *name = [NSString stringWithUTF8String:procs[i].kp_proc.p_comm];
        if ([name hasPrefix:@"com_kwai_gif"] || [name hasPrefix:@"Kwai"] ||
            [name hasPrefix:@"com.kuaishou"]) {
            found = name;
            break;
        }
    }
    free(procs);
    return found;
}

+ (BOOL)launch:(NSString *)bid {
    // 1) URL Scheme（最稳，不需要额外权限）
    NSURL *url = [NSURL URLWithString:[bid stringByAppendingString:@"://"]];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        [KSLog add:@"通过 URL Scheme 拉起 %@", bid];
        return YES;
    }

    // 2) LSApplicationWorkspace 私有接口（全部包在 @try 里，防 unrecognized selector 崩溃）
    @try {
        Class ws = NSClassFromString(@"LSApplicationWorkspace");
        if (ws && [ws respondsToSelector:NSSelectorFromString(@"defaultWorkspace")]) {
            id inst = ((id(*)(id, SEL))objc_msgSend)(ws,
                        NSSelectorFromString(@"defaultWorkspace"));
            SEL sel = NSSelectorFromString(@"openApplicationWithBundleID:");
            if (inst && [inst respondsToSelector:sel]) {
                BOOL ok = ((BOOL(*)(id, SEL, id))objc_msgSend)(inst, sel, bid);
                if (ok) {
                    [KSLog add:@"通过 LSApplicationWorkspace 拉起 %@", bid];
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {
        [KSLog add:@"⚠ 私有接口不可用(%@)，请手动点快手图标", e.reason ?: @"未知"];
    }

    [KSLog add:@"✗ 拉起失败，请手动点击快手图标"];
    return NO;
}

@end

#pragma mark - ========== 注入引擎 ==========

@interface KSInjector ()
+ (NSUInteger)writeViaCFPreferences:(NSDictionary *)kv
                               path:(NSString *)prefsPath
                             domain:(NSString *)bundleID;
+ (void)flushDaemons;
+ (NSString *)currentFiveLine:(KSTarget *)t;
+ (BOOL)killKuaishouAndWait;
+ (pid_t)pidFromLaunchctlForBundle:(NSString *)bundleID;
+ (pid_t)pidFromProcForBundle:(NSString *)bundleID;
+ (pid_t)pidFromSysctlForName:(NSString *)procName;
+ (pid_t)pidFromSysctlQuiet:(NSString *)procName;
+ (BOOL)killPID:(pid_t)pid;
+ (NSString *)didFromKeychain;
+ (NSString *)didFromNetworkCache;
+ (NSDictionary *)loadPlistAt:(NSString *)path;
+ (NSString *)didFromPlistDeep:(NSDictionary *)d;
+ (NSString *)egidFromContainerScan:(KSTarget *)t;
+ (NSString *)egidScan:(NSString *)knownDid;
+ (NSString *)containerRoot;
@end

@implementation KSInjector

/// 用 posix_spawn 调系统命令（越狱机上 App 有权限时可用）
static int runCmd(NSString *path, NSArray<NSString *> *args) {
    const char *argv[16];
    int i = 0;
    argv[i++] = [path UTF8String];
    for (NSString *a in args) {
        if (i >= 15) break;
        argv[i++] = [a UTF8String];
    }
    argv[i] = NULL;

    pid_t pid = 0;
    int rc = posix_spawn(&pid, [path UTF8String], NULL, NULL,
                         (char *const *)argv, environ);
    if (rc != 0) return -1;

    int status = 0;
    waitpid(pid, &status, 0);
    return WEXITSTATUS(status);
}

/// 用 posix_spawn 调系统命令并捕获 stdout（返回按行拆分的数组）
/// ★ 实测坑（RootHide 无根越狱）：
///   - App 可能没有独立容器，NSTemporaryDirectory() 指向的路径不可写
///   - 必须用 /tmp（越狱环境下所有进程都可写）
///   - 返回空数组时必须能让调用方区分"命令没输出"和"根本没能执行"
static NSArray<NSString *> *runCmdCapture(NSString *path, NSArray<NSString *> *args) {
    // ★ 实测坑：/tmp 是【相对符号链接】-> var/tmp，
    //   app 沙盒里解析不了，必须用绝对路径 /var/tmp。
    NSArray *cand = @[@"/var/tmp/ks_cmd_out.txt",
                      @"/private/var/tmp/ks_cmd_out.txt"];
    NSString *outPath = cand.firstObject;
    for (NSString *p in cand) {
        NSString *dir = [p stringByDeletingLastPathComponent];
        if ([[NSFileManager defaultManager] isWritableFileAtPath:dir]) {
            outPath = p; break;
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];

    // 先确认可执行文件真实存在
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:path]) {
        return nil;   // nil 表示"不可用"，与"无输出"（空数组）区分
    }

    pid_t pid = 0;
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO,
                                     [outPath fileSystemRepresentation],
                                     O_WRONLY | O_CREAT | O_TRUNC, 0644);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO,
                                     "/dev/null", O_WRONLY, 0);

    const char *argv[16];
    int i = 0;
    argv[i++] = [path UTF8String];
    for (NSString *a in args) {
        if (i >= 15) break;
        argv[i++] = [a UTF8String];
    }
    argv[i] = NULL;

    int rc = posix_spawn(&pid, [path UTF8String], &fa, NULL,
                         (char *const *)argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    if (rc != 0) return @[];

    int status = 0;
    waitpid(pid, &status, 0);

    NSString *txt = [NSString stringWithContentsOfFile:outPath
                                              encoding:NSUTF8StringEncoding
                                                 error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];
    if (!txt.length) return @[];
    return [txt componentsSeparatedByCharactersInSet:
            [NSCharacterSet newlineCharacterSet]];
}

/// 从 launchctl 取出指定 bundleID 的进程 PID
/// ★ 实测：killall 在 App 内（mobile 身份）完全无效 ——
///   实测返回 "No matching processes belonging to you were found"，
///   因为快手进程不在 mobile 的可见范围内。
///   唯一可靠的方式是用 launchctl list 拿到 PID，再 kill -9。
+ (pid_t)pidFromLaunchctlForBundle:(NSString *)bundleID {
    // ★ 实测（RootHide 无根越狱，真机日志）：
    //   - iOS 上 /proc 不存在（"文件夹 proc 不存在"）
    //   - ps / pgrep 未安装
    //   - App 内 posix_spawn 调 launchctl 无输出（沙盒拦截外部程序）
    //   → 唯一可靠的方式：Darwin 原生 sysctl(KERN_PROC_ALL)
    NSArray *names = @[@"com_kwai_gif", @"com.kuaishou.nebula"];
    for (NSString *n in names) {
        pid_t p = [self pidFromSysctlForName:n];
        if (p > 0) return p;
    }

    // 兜底：/proc（其他越狱环境可能有）
    pid_t p2 = [self pidFromProcForBundle:bundleID];
    if (p2 > 0) return p2;

    // 再兜底：launchctl（部分环境可用）
    NSArray *paths = @[@"/usr/bin/launchctl", @"/var/jb/usr/bin/launchctl"];
    for (NSString *lp in paths) {
        NSArray *lines = runCmdCapture(lp, @[@"list"]);
        if (!lines || !lines.count) continue;
        NSString *needle = [NSString stringWithFormat:@"UIKitApplication:%@", bundleID];
        for (NSString *l in lines) {
            if (![l containsString:needle]) continue;
            NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
            NSUInteger i = 0;
            while (i < l.length && [ws characterIsMember:[l characterAtIndex:i]]) i++;
            NSUInteger start = i;
            while (i < l.length &&
                   [[NSCharacterSet decimalDigitCharacterSet]
                    characterIsMember:[l characterAtIndex:i]]) i++;
            if (i > start) {
                NSString *num = [l substringWithRange:NSMakeRange(start, i - start)];
                pid_t r = (pid_t)[num intValue];
                [KSLog add:@"  launchctl 命中 → PID=%d", (int)r];
                return r;
            }
        }
    }
    return 0;
}

/// 用 Darwin 原生 sysctl 枚举进程（不依赖外部命令、不依赖 /proc）
/// ★ 实测：iOS 上 /proc 不存在，ps/pgrep 也没装，
///   唯一可用的进程枚举方式就是 sysctl(KERN_PROC_ALL) + proc_pidpath。
+ (pid_t)pidFromSysctlForName:(NSString *)procName {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;

    // 第一次：取所需缓冲区大小
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) {
        [KSLog add:@"  sysctl 取大小失败 (errno=%d)", errno];
        return 0;
    }
    // 多留 20% 余量，避免进程数变化导致 ENOMEM
    len = len * 12 / 10 + sizeof(struct kinfo_proc) * 16;
    struct kinfo_proc *buf = malloc(len);
    if (!buf) return 0;

    if (sysctl(mib, 4, buf, &len, NULL, 0) != 0) {
        [KSLog add:@"  sysctl 读进程列表失败 (errno=%d)", errno];
        free(buf);
        return 0;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    [KSLog add:@"  sysctl 枚举到 %d 个进程", count];
    pid_t found = 0;

    for (int i = 0; i < count; i++) {
        pid_t p = buf[i].kp_proc.p_pid;
        if (p <= 0) continue;
        // 用 p_comm 对比进程名（与 runningProcessName 相同写法，保证可编译）
        const char *cname = buf[i].kp_proc.p_comm;
        if (cname == NULL) continue;
        NSString *comm = [NSString stringWithUTF8String:cname];
        if (comm == nil) continue;
        if ([comm isEqualToString:procName]) {
            found = p;
            [KSLog add:@"  sysctl 命中 %@ → PID=%d", comm, (int)p];
            break;
        }
    }
    free(buf);
    if (!found) {
        [KSLog add:@"  sysctl 里没有名为 %@ 的进程", procName];
    }
    return found;
}

/// 备用方案：直接遍历 /proc 找进程（不依赖任何外部命令）
/// iOS 上通常不存在 /proc，留作兼容其他环境
+ (pid_t)pidFromProcForBundle:(NSString *)bundleID {
    NSFileManager *fm = [NSFileManager defaultManager];
    // 无根越狱下 /proc 存在两种可能，都试
    NSString *procRoot = @"/proc";
    NSError *pe = nil;
    NSArray *procs = [fm contentsOfDirectoryAtPath:procRoot error:&pe];
    [KSLog add:@"  /proc 读取: %@ 项%@", @(procs.count),
     pe ? [NSString stringWithFormat:@" (错误: %@)", pe.localizedDescription] : @""];
    if (!procs.count) {
        procRoot = @"/var/jb/proc";
        procs = [fm contentsOfDirectoryAtPath:procRoot error:NULL];
        [KSLog add:@"  /var/jb/proc 读取: %lu 项", (unsigned long)procs.count];
    }
    if (!procs.count) {
        [KSLog add:@"  ⚠ /proc 不可读（RootHide 沙盒可能屏蔽了它）"];
        return 0;
    }

    // 快手主进程名固定是 com_kwai_gif
    NSArray *targets = @[@"com_kwai_gif", @"com.kuaishou.nebula"];
    NSCharacterSet *nonDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    NSUInteger scanned = 0, readable = 0;

    for (NSString *d in procs) {
        if ([d rangeOfCharacterFromSet:nonDigit].location != NSNotFound) continue;
        scanned++;
        NSString *commPath = [NSString stringWithFormat:@"%@/%@/comm", procRoot, d];
        NSString *comm = [NSString stringWithContentsOfFile:commPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:NULL];
        if (!comm.length) continue;
        readable++;
        comm = [comm stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        for (NSString *tg in targets) {
            if ([comm isEqualToString:tg]) {
                pid_t p = (pid_t)[d intValue];
                [KSLog add:@"  /proc 命中 %@ → PID=%d", comm, (int)p];
                return p;
            }
        }
    }
    [KSLog add:@"  /proc 扫描 %lu 个 PID，可读 %lu 个，没找到快手",
     (unsigned long)scanned, (unsigned long)readable];
    return 0;
}

/// 用 PID 强杀进程（比 killall 可靠得多）
+ (BOOL)killPID:(pid_t)pid {
    if (pid <= 0) return NO;
    return (kill(pid, SIGKILL) == 0);
}

/// 彻底结束快手进程，并确认真的退出了
+ (BOOL)killKuaishouAndWait {
    NSArray *bids = @[@"com.jiangjia.gif", @"com.kuaishou.nebula"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *killallPaths = @[@"/var/jb/usr/bin/killall", @"/usr/bin/killall"];

    // ---- 第 1 轮：launchctl 取 PID → kill -9（主力方案）----
    BOOL didKill = NO;
    for (NSString *bid in bids) {
        pid_t pid = [self pidFromLaunchctlForBundle:bid];
        if (pid > 0) {
            [KSLog add:@"  发现 %@ PID=%d", bid, (int)pid];
            if ([self killPID:pid]) {
                [KSLog add:@"  ✓ kill -9 %d 已发送", (int)pid];
                didKill = YES;
            } else {
                [KSLog add:@"  ⚠ kill -9 %d 失败（errno=%d）", (int)pid, errno];
            }
        }
    }

    // ---- 第 2 轮：killall 兜底（对老版本/其他进程名有效）----
    NSArray *names = @[@"com_kwai_gif", @"com.kuaishou.nebula", @"Kwai"];
    for (NSString *kp in killallPaths) {
        if (![fm fileExistsAtPath:kp]) continue;
        for (NSString *n in names) runCmd(kp, @[@"-9", n]);
    }

    if (!didKill) {
        [KSLog add:@"  未找到快手进程（可能本来就没运行）"];
    }

    // ---- 轮询确认：用轻量的 sysctl 检测（避免刷屏日志）----
    NSArray *aliveNames = @[@"com_kwai_gif", @"com.kuaishou.nebula"];
    for (int i = 0; i < 25; i++) {
        BOOL alive = NO;
        for (NSString *n in aliveNames) {
            if ([self pidFromSysctlQuiet:n] > 0) { alive = YES; break; }
        }
        if (!alive) {
            [KSLog add:@"✓ 快手已完全退出（%.1f 秒）", (i + 1) * 0.2];
            usleep(500 * 1000);   // 再等 0.5s 让系统完成后台数据落盘
            return YES;
        }
        usleep(200 * 1000);
    }

    [KSLog add:@"⚠ 5 秒内快手仍未退出，写入可能被覆盖"];
    return NO;
}

/// 静默版 sysctl 查进程（不写日志，供轮询使用）
+ (pid_t)pidFromSysctlQuiet:(NSString *)procName {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) return 0;
    len = len * 12 / 10 + sizeof(struct kinfo_proc) * 16;
    struct kinfo_proc *buf = malloc(len);
    if (!buf) return 0;
    if (sysctl(mib, 4, buf, &len, NULL, 0) != 0) { free(buf); return 0; }

    int count = (int)(len / sizeof(struct kinfo_proc));
    pid_t found = 0;
    for (int i = 0; i < count; i++) {
        pid_t p = buf[i].kp_proc.p_pid;
        if (p <= 0) continue;
        const char *c = buf[i].kp_proc.p_comm;
        if (c && strcmp(c, procName.UTF8String) == 0) { found = p; break; }
    }
    free(buf);
    return found;
}

+ (void)killKuaishou {
    [self killKuaishouAndWait];
}

/// 修正 plist 属主与权限（对标安卓的 chown + chmod + chcon）
+ (BOOL)fixOwnership:(NSString *)prefsPath target:(KSTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;

    // 权限 660（安卓同款）
    BOOL ok = [fm setAttributes:@{NSFilePosixPermissions: @(0660)}
                   ofItemAtPath:prefsPath error:&err];
    if (!ok) {
        [KSLog add:@"⚠ 设置文件权限失败: %@", err.localizedDescription];
    } else {
        [KSLog add:@"✓ 权限设为 660（对标安卓 chmod 660）"];
    }

    // 属主改 mobile:mobile（对标安卓 chown u0_aXXX:u0_aXXX）
    // 无根越狱 App 权限受限时可能失败，快手常能容忍，不阻断流程
    if (chown([prefsPath UTF8String], 501, 501) == 0) {
        [KSLog add:@"✓ 属主设为 mobile:mobile（uid501）"];
    } else {
        [KSLog add:@"⚠ 属主设置失败(errno=%d)，通常不影响登录", errno];
    }

    // Preferences 目录权限
    NSString *dir = [prefsPath stringByDeletingLastPathComponent];
    [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:dir error:NULL];

    return YES;
}

+ (BOOL)writeOnly:(KSFive *)five target:(KSTarget *)t {
    // 沙盒没定位到就现场再试一次（可能刚打开快手才建容器）
    if (!t.dataContainer) {
        [KSLog add:@"沙盒未定位，重新探测..."];
        NSString *c = [KSTarget containerForBundleID:t.bundleID];
        if (!c) c = [KSTarget containerForBundleID:KS_BID_MAIN];
        if (c) {
            t.dataContainer = c;
            t.prefsPath = [KSTarget prefsPathIn:c bundleID:t.bundleID];
            [KSLog add:@"✓ 补定位成功: %@", c];
        }
    }

    if (!t.prefsPath) {
        [KSLog add:@"✗ 未定位到快手 Preferences 路径"];
        [KSLog add:@"  排查: 先手动打开一次快手，再点「诊断」看沙盒列表"];
        [KSLog add:@"  权限: %@", [KSTarget hasPlatformEntitlement]
                ? @"有平台权限" : @"✗ 无平台权限，写不进去"];
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [t.prefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        NSError *mkErr = nil;
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                       attributes:nil error:&mkErr];
        if (mkErr) {
            [KSLog add:@"✗ 创建目录失败: %@", mkErr.localizedDescription];
            [KSLog add:@"  这是权限问题，确认 App 有 platform-application"];
            return NO;
        }
        [KSLog add:@"✓ 已创建 Preferences 目录"];
    }

    // 读现有 plist（保留其他键，不破坏快手配置）
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    if (old) {
        [plist addEntriesFromDictionary:old];
        [KSLog add:@"读取现有 plist，%lu 个键将被保留", (unsigned long)old.count];
    }

    // ---- 写入登录键 ----
    // === 键名表：从快手 iOS 主二进制（com_kwai_gif，14.8.10）实测提取 ===
    //   实测存在：Gif_Token / Gif_Token_Salt / Gif_KwaiClientSalt /
    //            Gif_ServiceToken / Gif_PassToken / Gif_LastLoginType /
    //            Gif_ID / Gif_Kwai_ID / Gif_Name / Gif_HeadUrl / Gif_Sex /
    //            Gif_Email / Gif_Kwai_New_User / Gif_FansNumber /
    //            Gif_ProfileUserType / token_client_salt
    //   实测不存在：gifshow_token / gifshow_userid（Android 专用，iOS 不认）
    //              Gif_User（iOS 用的是 Gif_ID / Gif_Kwai_ID）
    __block NSUInteger n = 0;
    // put  用于字符串；类型必须与真实登录态一致，否则快手读出来是 nil/错值
    void (^put)(NSString *, NSString *) = ^(NSString *k, NSString *v) {
        if (k.length && v != nil) { plist[k] = v; n++; }
    };
    void (^putB)(NSString *, BOOL) = ^(NSString *k, BOOL v) {
        if (k.length) { plist[k] = @(v); n++; }
    };
    void (^putI)(NSString *, NSInteger) = ^(NSString *k, NSInteger v) {
        if (k.length) { plist[k] = @(v); n++; }
    };

    NSString *uid = [five userId];

    // === 核心登录键：严格对齐「五参提取器」的取数逻辑 ===
    // 提取器（快手五参提取.py）从 plist 读这几个键来生成五参：
    //     Gif_Token                                 → 第1段
    //     Gif_Token_Salt  / Gif_KwaiClientSalt      → 第2段
    //     KLink_Persistent_klink.device_id / WeaponUUIDKey → 第3段 (did)
    //     (日志 global_id=DFP)                       → 第4段 (egid)
    //     Gif_ServiceToken                          → 第5段 (api_st)
    // 所以写入时也必须落在这几个键上，写别处快手读不到。
    put(@"Gif_Token",          five.token);   // 第1段：完整 "32位hex-uid"
    put(@"Gif_Token_Salt",     five.salt);    // 第2段
    put(@"Gif_KwaiClientSalt", five.salt);    // 与 Salt 同值（真机实测一致）

    // ★ did（第3段）：提取器读的是 WeaponUUIDKey，
    //   iOS 快手判定"设备身份"用的就是这个键。
    //   之前我误写到 com.kuaishou.did 文件里，那个文件不是登录判定依据。
    if (five.did.length) {
        put(@"WeaponUUIDKey", five.did);
    }

    // egid（第4段）：DFP 设备指纹
    if (five.egid.length) {
        put(@"KS_OUTERID_KEY", five.egid);
    }

    // uid 写成整型（真机实测 Gif_ID 是 int 类型）
    NSInteger uidNum = (NSInteger)[uid longLongValue];
    if (uidNum > 0) putI(@"Gif_ID", uidNum);

    // 登录类型：真机值是 phone_captcha_login
    put(@"Gif_LastLoginType",  @"phone_captcha_login");
    putB(@"Gif_Kwai_New_User", NO);      // 老用户 = 布尔 NO

    // ★★ 用户资料键：必须补上，否则快手读到"已登录"后渲染资料页时
    //    拿到 nil 会在主线程 layoutSublayers 抛 NSException 直接 SIGTRAP 闪退。
    //    这些键在 iOS 主二进制里都存在，只是我们之前没写。
    put(@"Gif_Name",           five.nickName.length ? five.nickName : @"快手用户");
    put(@"Gif_HeadUrl",        five.headUrl.length ? five.headUrl
                              : @"http://alimov2.a.yximgs.com/kos/nlav12689/head.jpg");
    put(@"Gif_defaultHead",    @"");          // 空串而非 nil，避免 UI 拿到 nil
    put(@"Gif_Sex",            @"U");         // 真机值 "U"（未知），不是 "0"
    put(@"Gif_Email",          @"");
    put(@"Gif_FansNumber",     @"0");
    putI(@"Gif_ProfileUserType", 1);          // 真机实测是整型 1
    put(@"Gif_Background",     @"http://static.yximgs.com/s1/i/def/bg2.jpg");
    put(@"Gif_pendantType",    @"0");         // 挂件类型，枚举必须有值
    put(@"Gif_pendantUrls",    @"");
    putB(@"Gif_Contacts_Uploaded", NO);       // 真机是布尔
    putB(@"Gif_defaultHead",   NO);           // 覆盖上面的空串：真机是布尔 False
    put(@"Gif_User_Text",      @"");
    put(@"Gif_H",              @"");

    // === 服务端票据 ===
    // 实测三个 token 的 protobuf 名称（从已登录真机反解）：
    //   Gif_ServiceToken ← "kuaishou.api.st"        339 字符  → 对应参数【第5段】✓
    //   Gif_PassToken    ← "passport.ks-pass-token" 391 字符  → 参数里没有
    //   Gif_H5Token      ← "kuaishou.h5.st"         338 字符  → 参数里没有
    // 用户参数的 339 字符与 ServiceToken 完全吻合，所以第5段进 Gif_ServiceToken。
    // PassToken / H5Token 参数未提供，留空即可 —— 实测 iOS 会自行向后端换取。
    put(@"Gif_ServiceToken",   five.passToken.length ? five.passToken : five.apiSt);
    if (five.hToken.length) {
        put(@"Gif_H5Token",    five.hToken);
    }

    // === 兜底键名（真机实测存在）===
    // 注意：token_client_salt / ClientSalt 存的是【第2段】，
    //       而 Gif_Token_Salt 在真机上与它们同值，所以两边一致。
    put(@"token_client_salt",  five.salt);
    put(@"ClientSalt",         five.salt);
    put(@"uid",                uid);
    put(@"user_id",            uid);
    put(@"userId",             uid);

    if (n == 0) {
        [KSLog add:@"✗ 没有可写入的键"];
        return NO;
    }

    // ---- 落盘 ----
    // ★ 核心顺序（否则写入会被 cfprefsd 覆盖）：
    //   1) 先杀 cfprefsd —— 清掉它内存里的旧 plist 缓存
    //   2) 立刻写文件 —— 此时没有守护进程会回写
    //   3) 再杀一次 cfprefsd —— 确保刚重启的实例重新从磁盘加载我们的数据
    //   4) 结束快手 —— 它启动时才会读到新值
    // 实测教训：只写文件不杀 cfprefsd，快手下一次启动时旧值会被刷回来。

    // [1] 清缓存
    [self flushDaemons];
    usleep(300 * 1000);

    // [2] 写文件（此时 cfprefsd 不在，不会被覆盖）
    NSString *tmp = [t.prefsPath stringByAppendingString:@".ks_tmp"];
    BOOL ok = [plist writeToFile:tmp atomically:YES];
    if (!ok) {
        [KSLog add:@"✗ plist 文件写入失败（沙盒权限不足？）"];
        return NO;
    }
    [fm removeItemAtPath:t.prefsPath error:NULL];
    NSError *mvErr = nil;
    [fm moveItemAtPath:tmp toPath:t.prefsPath error:&mvErr];
    if (mvErr) {
        [KSLog add:@"✗ 替换 plist 失败: %@", mvErr.localizedDescription];
        return NO;
    }
    [KSLog add:@"✓ plist 已写入 %lu 个键", (unsigned long)n];

    // 写完后立即修正属主/权限（cfprefsd 重启前完成）
    [self fixOwnership:t.prefsPath target:t];

    // [3] 再杀一次，强迫重新加载
    [self flushDaemons];
    usleep(300 * 1000);
    [KSLog add:@"✓ cfprefsd/containermanagerd 缓存已刷新"];

    // [4] 结束快手（确保它启动时读的是新数据）
    [self killKuaishou];

    // 校验：把刚写的文件读回来，确认关键键真的在
    NSDictionary *verify = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    NSString *vt = verify[@"Gif_Token"];
    if (vt.length) {
        [KSLog add:@"✓ 校验通过: Gif_Token=%@", vt];
    } else {
        [KSLog add:@"⚠ 校验失败: 读回的 plist 里没有 Gif_Token（可能被覆盖）"];
    }
    [KSLog add:@"  Gif_ID=%@  Salt=%@",
     verify[@"Gif_ID"] ?: @"(无)", verify[@"Gif_Token_Salt"] ?: @"(无)"];

    return YES;
}

/// 通过 CFPreferences 写目标 App 的偏好（带平台权限时才能跨容器写）
+ (NSUInteger)writeViaCFPreferences:(NSDictionary *)kv
                               path:(NSString *)prefsPath
                             domain:(NSString *)bundleID {
    if (!kv.count) return 0;

    // 该 App 的偏好实际落在 <沙盒>/Library/Preferences/<bundleID>.plist，
    // 对 cfprefsd 而言它的 domain 就是 bundleID。
    NSString *dom = bundleID.length ? bundleID : @"com.jiangjia.gif";

    // 1) 逐键写入
    NSUInteger n = 0;
    for (NSString *k in kv) {
        id v = kv[k];
        if (![v isKindOfClass:[NSString class]]) continue;
        CFPreferencesSetAppValue((__bridge CFStringRef)k,
                                 (__bridge CFStringRef)v,
                                 (__bridge CFStringRef)dom);
        n++;
    }

    // 2) 同步到磁盘
    Boolean synced = CFPreferencesAppSynchronize((__bridge CFStringRef)dom);
    [KSLog add:@"  CFPreferencesSynchronize(%@) -> %@", dom,
     synced ? @"成功" : @"未同步"];

    return n;
}

/// 终止容器管理/偏好守护进程，确保我们写的文件不会被内存缓存覆盖
+ (void)flushDaemons {
    NSArray *daemons = @[@"cfprefsd", @"containermanagerd"];
    for (NSString *d in daemons) {
        runCmd(@"/usr/bin/killall", @[@"-9", d]);
    }
}

+ (BOOL)loginWithFive:(KSFive *)five
                target:(KSTarget *)t
              progress:(void (^)(NSString *, BOOL))progress {

    void (^step)(NSString *, BOOL) = ^(NSString *s, BOOL ok) {
        [KSLog add:@"%@", s];
        if (progress) progress(s, ok);
    };

    step(@"[1/6] 检查目标 App...", YES);
    if (!t) {
        step(@"✗ 没找到快手，先确认已安装", NO);
        return NO;
    }
    step([NSString stringWithFormat:@"  ✓ %@", t.bundleID], YES);

    // 沙盒没定位到就现场重试（容器可能刚建好 / LSApplicationWorkspace 才可用）
    if (!t.dataContainer) {
        step(@"  沙盒未定位，重新探测...", YES);
        NSString *c = [KSTarget containerForBundleID:t.bundleID];
        if (!c) c = [KSTarget containerForBundleID:KS_BID_MAIN];
        if (c) {
            t.dataContainer = c;
            t.prefsPath = [KSTarget prefsPathIn:c bundleID:t.bundleID];
        }
    }
    if (!t.dataContainer) {
        step(@"✗ 未定位到快手沙盒", NO);
        step(@"  1) 先手动打开一次快手再回来", NO);
        step(@"  2) 点「诊断」看详细探测结果", NO);
        step([NSString stringWithFormat:@"  平台权限: %@",
              [KSTarget hasPlatformEntitlement] ? @"有" : @"✗ 没有"], NO);
        return NO;
    }
    step([NSString stringWithFormat:@"  ✓ 沙盒: %@", t.dataContainer], YES);

    step(@"[2/6] 校验五参...", YES);
    if (![five usable]) {
        step(@"⚠ token/salt 不合法，仍尝试写入", YES);
    } else {
        step([NSString stringWithFormat:@"  ✓ uid=%@" , [five userId]], YES);
    }

    step(@"[3/6] 结束快手进程...", YES);
    // ★ 必须等到进程真的退出再写 —— 否则快手退出前会把内存里的旧数据刷回 plist，
    //   把我们写进去的键覆盖掉。这是"有时候能上号、有时候上不去"的主要原因。
    BOOL killed = [self killKuaishouAndWait];
    if (killed) {
        step(@"  ✓ 快手已完全退出", YES);
    } else {
        step(@"  ⚠ 进程仍在，尝试继续（可能失败）", NO);
    }

    step(@"[4/6] 清除旧登录态...", YES);
    [self clearLogin:t];
    step(@"  ✓ 已清理", YES);

    step(@"[5/6] 写入五参...", YES);
    BOOL wrote = [self writeOnly:five target:t];
    if (!wrote) {
        step(@"✗ 写入失败，请确认 App 权限", NO);
        return NO;
    }
    step(@"  ✓ 写入成功", YES);

    // did/egid 已在 writeOnly: 里作为 WeaponUUIDKey / KS_OUTERID_KEY 写入 plist，
    // 不再单独写 com.kuaishou.did 文件 —— 实测那个文件不是登录判定依据，
    // 真正被读取的是 WeaponUUIDKey（五参提取器也是从它取值）。
    if (five.did.length) {
        step([NSString stringWithFormat:@"  ✓ did(WeaponUUIDKey) = %@", five.did], YES);
    }

    step(@"[6/6] 拉起快手...", YES);
    [KSTarget launch:t.bundleID];

    return YES;
}

/// 多方式读取 plist（应对沙盒/文件权限差异）
/// 实测：快手 plist 是 mobile:mobile 0600，App 同为 mobile 应该能读，
///      但某些越狱环境会拦 NSDictionary 的直接读，需要多级回退。
+ (NSDictionary *)loadPlistAt:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) 标准方式
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    if (d.count) return d;

    // 2) NSData + NSPropertyListSerialization
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length) {
        id obj = [NSPropertyListSerialization
                  propertyListWithData:data options:NSPropertyListImmutable
                               format:NULL error:NULL];
        if ([obj isKindOfClass:[NSDictionary class]] && [obj count]) {
            [KSLog add:@"  (plist 用 NSPropertyListSerialization 读取)"];
            return obj;
        }
    }

    // 3) 路径兜底：/private 前缀（沙盒里 /var 与 /private/var 可能只有一个可读）
    if ([path hasPrefix:@"/var/"]) {
        NSString *alt = [@"/private" stringByAppendingString:path];
        d = [NSDictionary dictionaryWithContentsOfFile:alt];
        if (d.count) return d;
    } else if ([path hasPrefix:@"/private/var/"]) {
        NSString *alt = [path substringFromIndex:8];  // 去掉 /private
        d = [NSDictionary dictionaryWithContentsOfFile:alt];
        if (d.count) return d;
    }

    // 4) 诊断：文件到底能不能看见
    [KSLog add:@"  [诊断] 文件存在=%@ 可读=%@ 大小=%@",
     [fm fileExistsAtPath:path] ? @"是" : @"否",
     [fm isReadableFileAtPath:path] ? @"是" : @"否",
     [fm attributesOfItemAtPath:path error:NULL][NSFileSize] ?: @"?"];
    return nil;
}

+ (KSFive *)readCurrent:(KSTarget *)t {
    if (!t.prefsPath) {
        [KSLog add:@"  ✗ prefsPath 为空"];
        return nil;
    }

    // ★ 多种方式读取 plist（App 沙盒下某一种可能被拦）
    NSDictionary *d = [self loadPlistAt:t.prefsPath];
    if (!d) {
        [KSLog add:@"  ✗ 读不了 plist: %@", t.prefsPath];
        return nil;
    }
    [KSLog add:@"  plist 读取成功，%lu 个键", (unsigned long)d.count];

    // 取第一个存在且非空的字符串值（block 直接调用，ARC 下不能当函数指针强转）
    NSString *(^pick)(NSArray *) = ^NSString *(NSArray *keys) {
        for (NSString *k in keys) {
            id v = d[k];
            if ([v isKindOfClass:[NSString class]] && [v length]) return v;
            if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
        }
        return nil;
    };

    KSFive *f = [KSFive new];

    // === 第1段 token ===
    // 提取器逻辑：先取 Gif_Token，若不是 "32位hex-数字" 格式，
    // 回退到老版的 kwapp_host_path_db.db 的 host_path_table 表
    NSString *token = pick(@[@"Gif_Token", @"gifshow_token"]);
    NSRegularExpression *tokenRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"^[0-9a-fA-F]{32}-\\d+" options:0 error:NULL];
    BOOL tokenOK = token.length &&
        [tokenRe numberOfMatchesInString:token options:0
                                   range:NSMakeRange(0, token.length)] > 0;
    if (!tokenOK) {
        NSString *old = [self tokenFromKwappDB:t];
        if (old.length) {
            [KSLog add:@"  Gif_Token 格式不符，改用 kwapp DB 的 host_path_table"];
            token = old;
        }
    }
    f.token = token ?: @"";

    // === 第2段 salt ===
    f.salt = pick(@[@"Gif_Token_Salt", @"Gif_KwaiClientSalt",
                    @"token_client_salt", @"ClientSalt"]) ?: @"";

    // === 第3段 did ===
    // 来源优先级（真机实测校准）：
    //   1) 网络缓存里 "did=<UUID>" 的最新值  ← 实测最准（与 egid 同现，且随换号更新）
    //   2) plist "KLink_Persistent_klink.device_id"
    //   3) plist "WeaponUUIDKey"
    //   4) Keychain "CiInfoKey_Re_N"（实测值可能不是 did，放最后）
    NSString *did = [self didFromNetworkCache];
    if (!did.length) {
        did = pick(@[@"KLink_Persistent_klink.device_id", @"WeaponUUIDKey"]);
    }
    if (!did.length) did = [self didFromPlistDeep:d];
    if (!did.length) did = [self didFromKeychain];
    f.did = did ?: @"";

    // === 第4段 egid ===
    // ★ 实测校准（真机 KSURLCache/Cache.db-wal）：
    //   请求 URL 里 did= / egid= / global_id= 三者并存且值互不相同：
    //     did=BEA9D9B2-...           ← 设备 ID
    //     egid=DFP4563194B86C2...    ← ★ 第4段要的就是这个
    //     global_id=DFP2F2703D7DB... ← 另一个字段，不能混用
    //   而 plist 的 KS_OUTERID_KEY 是 32 位 hex（实测 863bfb78...），
    //   【不是】DFP 格式，绝不能拿它当 egid。
    NSString *egid = [self egidScan:f.did];          // 只认 egid=DFP...
    if (!egid.length) egid = [self egidFromLogs:t];  // 日志里的 egid=DFP...
    // 注意：不再回退 KS_OUTERID_KEY（格式不符，是错的）
    f.egid = egid ?: @"";

    // === 第5段 api_st ===
    f.apiSt = pick(@[@"Gif_ServiceToken"]) ?: @"";

    f.userIdFromToken = [f userId];
    return f.token.length ? f : nil;
}

/// 从网络缓存/日志里找【当前活跃】的 did
///
/// ★ 真机实测教训：
///   Keychain 的 CiInfoKey_Re_N 读出来的 UUID 与网络请求里的 did 不一致
///   （实测 Keychain 给 D506B263-…，而请求里是 3E796C4D-…），
///   说明那个 Keychain 项不是 did。
///   可靠做法：从请求参数 "did=<UUID>" 里取【最靠后出现】的那个 ——
///   缓存会累积历史值（换号/改机产生），偏移越靠后 = 越新 = 当前活跃。
+ (NSString *)didFromNetworkCache {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"\\bdid=([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})" options:0 error:NULL];

    NSArray *subs = @[
        @"Library/Caches/com.jiangjia.gif/KSURLCache",
        @"Library/Caches/com.jiangjia.gif",
        @"Library/vadar",
        @"Library/Caches",
    ];

    NSString *best = nil;

    for (NSString *sub in subs) {
        NSString *dir = [[self containerRoot] stringByAppendingPathComponent:sub];
        BOOL dIsDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&dIsDir] || !dIsDir) continue;

        // 只列当前层，优先 -wal / Cache.db（与 egidScan 一致的策略）
        NSArray *entries = [fm contentsOfDirectoryAtPath:dir error:NULL];
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSString *n in entries) {
            if ([n hasSuffix:@"-wal"]) [ordered insertObject:n atIndex:0];
            else if ([n hasPrefix:@"Cache.db"]) [ordered addObject:n];
        }
        for (NSString *n in entries) {
            if (![ordered containsObject:n]) [ordered addObject:n];
        }

        NSUInteger used = 0, budget = 200;
        for (NSString *n in ordered) {
            if (used >= budget) break;
            NSString *full = [dir stringByAppendingPathComponent:n];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
            used++;
            NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
            if ([attr fileSize] > 16 * 1024 * 1024) continue;
            if ([attr fileSize] == 0) continue;

            NSData *data = [NSData dataWithContentsOfFile:full];
            if (!data.length) continue;
            NSString *txt = [[NSString alloc] initWithData:data
                                                  encoding:NSISOLatin1StringEncoding];
            if (!txt.length) continue;

            NSArray *ms = [re matchesInString:txt options:0
                                        range:NSMakeRange(0, txt.length)];
            // 取该文件里【最后一个】did=（越靠后越新）
            NSTextCheckingResult *last = ms.lastObject;
            if (!last || last.numberOfRanges < 2) continue;
            NSString *v = [txt substringWithRange:[last rangeAtIndex:1]];
            if (v.length) { best = v; break; }
        }
        if (best) break;   // 找到就停（KSURLCache 最权威）
    }

    if (best) {
        [KSLog add:@"  did 从网络缓存取最新值 → %@", best];
    }
    return best;
}

/// 从 Keychain 读 did（参考 ksextract 插件：service = "CiInfoKey_Re_N"）
/// base64 解码后正则提取 UUID
/// ★ 注意：实测真机上这个 Keychain 项的值与请求里的 did 不一致，
///   所以只作为【次要】来源，主来源是 didFromNetworkCache。
+ (NSString *)didFromKeychain {
    // 先试快手自己的 access group，再试默认组
    NSArray *groups = @[@"NR2KD6K4TL.com.jiangjia.gif",
                        @"R3Y5DWB26T.com.jiangjia.gif",
                        @"com.jiangjia.gif",
                        nil];   // nil = 不指定 group（用默认）
    NSArray *services = @[@"CiInfoKey_Re_N", @"EAccountSDKFakeUUID"];

    NSRegularExpression *uuidRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];

    for (NSString *grp in groups) {
        for (NSString *svc in services) {
            for (int mode = 0; mode < 2; mode++) {
                NSMutableDictionary *q = [NSMutableDictionary dictionary];
                q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
                q[(__bridge id)kSecAttrService] = svc;
                if (mode == 1) q[(__bridge id)kSecAttrAccount] = svc;
                if (grp) q[(__bridge id)kSecAttrAccessGroup] = grp;
                q[(__bridge id)kSecReturnData] = (id)kCFBooleanTrue;
                q[(__bridge id)kSecMatchLimit] = (id)kSecMatchLimitOne;

                CFTypeRef r = NULL;
                OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
                if (st != errSecSuccess || !r) continue;

                id obj = (__bridge_transfer id)r;
                NSData *dd = nil;
                if ([obj isKindOfClass:[NSData class]]) dd = obj;
                else if ([obj isKindOfClass:[NSDictionary class]])
                    dd = obj[(__bridge id)kSecValueData];
                if (!dd.length) continue;

                NSString *raw = [[NSString alloc] initWithData:dd
                                                      encoding:NSUTF8StringEncoding] ?: @"";
                NSString *txt = raw;
                NSData *dec = [[NSData alloc] initWithBase64EncodedString:raw options:0];
                if (dec) {
                    NSString *t2 = [[NSString alloc] initWithData:dec
                                                         encoding:NSUTF8StringEncoding];
                    if (t2.length) txt = t2;
                }
                NSTextCheckingResult *m = [uuidRe firstMatchInString:txt options:0
                                                               range:NSMakeRange(0, txt.length)];
                if (m) {
                    NSString *uuid = [txt substringWithRange:m.range];
                    [KSLog add:@"  did 从 Keychain(%@/%@) 提取: %@",
                     grp ?: @"default", svc, uuid];
                    return uuid;
                }
                [KSLog add:@"  Keychain(%@/%@) 命中但无 UUID，原值前40字符: %.40@",
                 grp ?: @"default", svc, raw];
            }
        }
    }
    [KSLog add:@"  Keychain 里没找到 did（可能缺 keychain-access-groups 权限）"];
    return nil;
}

/// 从 plist 深层结构里找 UUID 形态的 did（兜底）
+ (NSString *)didFromPlistDeep:(NSDictionary *)d {
    NSArray *cands = @[@"KSCurrentUserPendantInfo", @"KSCurrentUser",
                       @"kKSUserDefaultRSAKeyPair", @"kKSIMServiceLoginInfoDiskCacheKey"];
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    for (NSString *k in cands) {
        id v = d[k];
        if (!v) continue;
        NSString *s = [v description];
        NSTextCheckingResult *m = [re firstMatchInString:s options:0
                                                   range:NSMakeRange(0, s.length)];
        if (m) {
            NSString *uuid = [s substringWithRange:m.range];
            [KSLog add:@"  did 从 plist.%@ 提取", k];
            return uuid;
        }
    }
    return nil;
}

/// 扫描容器内的文本文件找 DFP 指纹（参考插件：任意文本里 DFP+40~64hex）
/// ★ 实测（真机 Cache.db-wal 分析）：
///   请求参数串里 did 和 egid 同现，形如
///     "...;did=BEA9D9B2-121F-27F4-CB7B-6FD40BBD4AF6;didTag=0;egid=DFP248629...;gid=DFP248629...;"
///   而缓存里存在多个历史 DFP（设备每次改机/重置都会生成新的）。
///   所以判据是：找【与当前 did 出现在同一条请求里】的那个 DFP，而不是随便找一个。
+ (NSString *)egidFromContainerScan:(KSTarget *)t {
    return [self egidScan:t.did];
}

/// 扫描容器文本文件找 egid
/// @param knownDid 已知的 did（UUID），用于锁定同现的 egid；可为空
///
/// ★ 真机 Cache.db-wal 实测（唯一正确的判据）：
///   请求 URL 里三个字段并存，值各不相同，只有 egid 才是我们要的第4段：
///     ...&did=BEA9D9B2-121F-27F4-CB7B-6FD40BBD4AF6&did_tag=0
///        &egid=DFP4563194B86C20E86E14090E2F5182F1FA0231143E876123B9B45415DE1BE7
///        &global_id=DFP2F2703D7DBEE96E909DAFECF3CF17BD7CC34F59CB61A05AB8D3709366AED1...
///   注意 global_id 与 egid 不同，绝不能拿 global_id 当 egid。
///   所以只认 "egid=DFP..." 这种键值对形式。
+ (NSString *)egidScan:(NSString *)knownDid {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 精确匹配 egid=DFP...（只认 egid 这个键名）
    NSRegularExpression *egidRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"\\begid=(DFP[0-9A-Fa-f]{40,64})" options:0 error:NULL];
    // 宽松匹配：任意位置的 DFP（仅作最后兜底）
    NSRegularExpression *anyDfpRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"DFP[0-9A-Fa-f]{40,64}" options:0 error:NULL];

    // 按优先级扫描（网络缓存里最可能有 egid= 键值对）
    // ★ 实测坑（真机复现两次）：
    //   egid= 就在 <容器>/Library/Caches/com.jiangjia.gif/KSURLCache/Cache.db-wal
    //   （2.2MB，权限 rw-r--r--，App 可读，内含 114 个 egid=）。
    //   但用 enumeratorAtPath: 会【递归进入 fsCachedData 子目录】，
    //   那里的海量小文件会耗尽扫描配额，导致 Cache.db-wal 根本轮不到。
    //   → 改为：只列当前目录（不递归），并优先处理名字里带 -wal / Cache.db 的文件。
    NSArray *subs = @[
        @"Library/Caches/com.jiangjia.gif/KSURLCache",
        @"Library/Caches/com.jiangjia.gif",
        @"Library/vadar",
        @"Library/Caches/ObiwanLogs",
        @"Documents/mmkv",
    ];

    NSString *bestAny = nil;
    NSMutableDictionary *counter = [NSMutableDictionary dictionary];

    for (NSString *sub in subs) {
        NSString *dir = [[self containerRoot] stringByAppendingPathComponent:sub];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;

        // 只列当前层（非递归），按优先级排序：-wal > Cache.db > 其他
        NSArray *entries = [fm contentsOfDirectoryAtPath:dir error:NULL];
        NSMutableArray *ordered = [NSMutableArray array];
        for (NSString *n in entries) {
            if ([n hasSuffix:@"-wal"]) [ordered insertObject:n atIndex:0];
            else if ([n hasPrefix:@"Cache.db"]) [ordered addObject:n];
        }
        for (NSString *n in entries) {
            if (![ordered containsObject:n]) [ordered addObject:n];
        }

        NSUInteger used = 0, budget = 200;
        for (NSString *n in ordered) {
            if (used >= budget) break;
            NSString *full = [dir stringByAppendingPathComponent:n];
            BOOL fIsDir = NO;
            if (![fm fileExistsAtPath:full isDirectory:&fIsDir] || fIsDir) continue;
            used++;

            NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
            // 放宽到 16MB（KSURLCache 的 wal 文件实测 2.2MB）
            if ([attr fileSize] > 16 * 1024 * 1024) continue;
            if ([attr fileSize] == 0) continue;

            NSData *data = [NSData dataWithContentsOfFile:full];
            if (!data.length) continue;
            NSString *txt = [[NSString alloc] initWithData:data
                                                  encoding:NSISOLatin1StringEncoding];
            if (!txt.length) continue;

            // ① 首选：egid=DFP... 键值对
            NSArray *ms = [egidRe matchesInString:txt options:0
                                            range:NSMakeRange(0, txt.length)];
            for (NSTextCheckingResult *m in ms) {
                if (m.numberOfRanges < 2) continue;
                NSString *v = [txt substringWithRange:[m rangeAtIndex:1]];
                counter[v] = @([counter[v] integerValue] + 1);
            }
            if (ms.count) {
                [KSLog add:@"  %@/%@ 里找到 %lu 个 egid= 键值对",
                 [sub lastPathComponent], rel, (unsigned long)ms.count];
                // 一命中就可以停：KSURLCache 是权威来源
                if (sub == subs.firstObject) {
                    NSString *hit = counter.count ? counter.allKeys.firstObject : nil;
                    if (hit.length) {
                        [KSLog add:@"  egid 命中 KSURLCache → %@", hit];
                        return hit;
                    }
                }
            }

            // ② 兜底记录：任意 DFP（取出现最多的）
            if (!bestAny) {
                if (knownDid.length && [txt containsString:knownDid]) {
                    NSTextCheckingResult *dm = [anyDfpRe firstMatchInString:txt
                        options:0 range:NSMakeRange(0, txt.length)];
                    if (dm) bestAny = [txt substringWithRange:dm.range];
                }
            }
        }
    }

    // 取「egid=」出现次数最多的那个
    NSString *best = nil;
    NSInteger bestN = 0;
    for (NSString *k in counter) {
        NSInteger n = [counter[k] integerValue];
        if (n > bestN) { bestN = n; best = k; }
    }
    if (best) {
        [KSLog add:@"  egid 取自 egid= 键值对（%ld 次）→ %@", (long)bestN, best];
        return best;
    }
    if (bestAny) {
        [KSLog add:@"  egid 兜底（did 同现的 DFP）→ %@", bestAny];
        return bestAny;
    }
    return nil;
}

/// 快手数据容器根（缓存一份，避免重复探测）
+ (NSString *)containerRoot {
    static NSString *cached = nil;
    if (cached) return cached;
    cached = [KSTarget containerForBundleID:KS_BID_MAIN];
    if (!cached) cached = [KSTarget containerForBundleID:@"com.kuaishou.nebula"];
    return cached ?: @"";
}

/// 老版快手的 token 在 kwapp_host_path_db.db 的 host_path_table 里（host_id-owner_id）
+ (NSString *)tokenFromKwappDB:(KSTarget *)t {
    NSString *db = [t.dataContainer stringByAppendingPathComponent:
                    @"Library/KWApp/kwapp_host_path_db.db"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:db]) return nil;

    NSString *sqlPath = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:@"ks_kwapp.sql"];
    // 用 sqlite3 命令行提取（避免引入 libsqlite3 依赖）
    NSString *sql = @"SELECT host_id || '-' || owner_id FROM host_path_table LIMIT 1;";
    if (![sql writeToFile:sqlPath atomically:YES encoding:NSUTF8StringEncoding error:NULL])
        return nil;

    NSArray *lines = runCmdCapture(@"/usr/bin/sqlite3", @[db, sql]);
    for (NSString *l in lines) {
        NSString *v = [l stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (v.length) return v;
    }
    return nil;
}

/// 在快手日志里找 egid（DFP 设备指纹）
/// 提取器做法：正则 global_id=DFP[0-9A-Fa-f]{40,64}
+ (NSString *)egidFromLogs:(KSTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *logRoot = [t.dataContainer
                         stringByAppendingPathComponent:@"Documents/com.hawkeye.data"];
    if (![fm fileExistsAtPath:logRoot]) return nil;

    // ★ 必须用 egid= 而不是 global_id= —— 真机实测两者值不同：
    //     egid=DFP4563194B86C2...      ← 这才是第4段
    //     global_id=DFP2F2703D7DBEE... ← 另一个字段，不能混用
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"\\begid=(DFP[0-9A-Fa-f]{40,64})" options:0 error:NULL];

    NSDirectoryEnumerator *en = [fm enumeratorAtPath:logRoot];
    int scanned = 0;
    for (NSString *rel in en) {
        if (scanned++ > 600) break;
        NSString *full = [logRoot stringByAppendingPathComponent:rel];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:full isDirectory:&isDir] || isDir) continue;
        NSDictionary *attr = [fm attributesOfItemAtPath:full error:NULL];
        if ([attr fileSize] > 16 * 1024 * 1024) continue;

        NSData *data = [NSData dataWithContentsOfFile:full];
        if (!data || data.length > 16 * 1024 * 1024) continue;
        // 用 latin-1 解码（日志是二进制+文本混合）
        NSString *s = [[NSString alloc] initWithData:data
                                            encoding:NSISOLatin1StringEncoding];
        if (!s.length) continue;
        NSTextCheckingResult *m = [re firstMatchInString:s options:0
                                                   range:NSMakeRange(0, s.length)];
        if (m && m.numberOfRanges > 1) {
            NSString *hit = [s substringWithRange:[m rangeAtIndex:1]];
            [KSLog add:@"  egid 从日志提取: %@", rel];
            return hit;
        }
    }
    return nil;
}

/// 输出当前设备的五参（拼接成 ---- 分隔的一行），返回该字符串
+ (NSString *)currentFiveLine:(KSTarget *)t {
    KSFive *f = [self readCurrent:t];
    if (!f) {
        [KSLog add:@"✗ 读取失败：没找到 Gif_Token（可能未登录）"];
        return nil;
    }

    // ★ 顺序与输入一致：token / salt / did / egid / apiSt
    NSArray *parts = @[
        f.token.length    ? f.token    : @"",
        f.salt.length     ? f.salt     : @"",
        f.did.length      ? f.did      : @"",
        f.egid.length     ? f.egid     : @"",
        f.apiSt.length    ? f.apiSt    : @"",
    ];
    NSString *line = [parts componentsJoinedByString:@"----"];

    [KSLog add:@"──── 当前设备五参 ────"];
    [KSLog add:@"1 token  %@", f.token.length ? f.token : @"(缺失)"];
    [KSLog add:@"2 salt   %@", f.salt.length ? f.salt : @"(缺失)"];
    [KSLog add:@"3 did    %@", f.did.length ? f.did : @"(缺失)"];
    [KSLog add:@"4 egid   %@", f.egid.length ? f.egid : @"(缺失)"];
    [KSLog add:@"5 apiSt  %@", f.apiSt.length ? f.apiSt : @"(缺失)"];
    [KSLog add:@"  uid    %@", [f userId] ?: @"?"];
    [KSLog add:@"──── 拼接结果（已复制） ────"];
    [KSLog add:@"%@", line];
    return line;
}

+ (BOOL)clearLogin:(KSTarget *)t {
    if (!t.prefsPath) return NO;

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    if (old) [d addEntriesFromDictionary:old];

    NSArray *loginKeys = @[
        @"Gif_Token", @"Gif_Token_Salt", @"Gif_KwaiClientSalt", @"ClientSalt",
        @"Gif_User", @"Gif_LastLoginType",
        @"Gif_ServiceToken", @"Gif_H5Token", @"Gif_PassToken",
        @"gifshow_token", @"gifshow_userid", @"token_client_salt",
        @"KS_OUTERID_KEY", @"token", @"egid", @"uid",
    ];
    NSUInteger removed = 0;
    for (NSString *k in loginKeys) {
        if (d[k]) { [d removeObjectForKey:k]; removed++; }
    }
    if (removed == 0) {
        [KSLog add:@"  无旧登录态需要清理"];
        return YES;
    }

    [d writeToFile:t.prefsPath atomically:YES];
    [KSLog add:@"  已清除 %lu 个登录键", (unsigned long)removed];
    return YES;
}

+ (BOOL)wipeAllData:(KSTarget *)t {
    if (!t.dataContainer) {
        [KSLog add:@"✗ 未定位到容器"];
        return NO;
    }

    // ★ 第一步必须是杀进程，而且确认真的退出（用 launchctl 取 PID 强杀）
    [KSLog add:@"  ① 结束快手进程..."];
    BOOL killed = [self killKuaishouAndWait];
    [KSLog add:@"     %@", killed ? @"✓ 已退出" : @"⚠ 未能确认退出"];

    NSFileManager *fm = [NSFileManager defaultManager];

    // ★★ 直接清空容器内容
    //    实测（RootHide 03:33 日志）：容器根目录本身不可删（"没有访问它的权限"），
    //    但子目录里的文件可以删。所以要对每个顶层目录【递归清空内容】，
    //    能删整个目录就删，删不掉就进去把里面的条目全删。
    [KSLog add:@"  ② 清空容器内容: %@", t.dataContainer];

    // 递归清空一个目录里的所有条目（目录本身保留）
    __block NSUInteger removed = 0;
    __block NSUInteger failed = 0;
    void (^purge)(NSString *, int) = nil;
    purge = ^(NSString *dir, int depth) {
        if (depth > 6) return;
        NSError *de = nil;
        NSArray *items = [fm contentsOfDirectoryAtPath:dir error:&de];
        if (!items) {
            if (depth <= 1) {
                [KSLog add:@"     ⚠ 读不了 %@: %@", [dir lastPathComponent],
                 de.localizedDescription ?: @"未知"];
            }
            return;
        }
        for (NSString *it in items) {
            if ([it isEqualToString:
                 @".com.apple.mobile_container_manager.metadata.plist"]) continue;
            NSString *p = [dir stringByAppendingPathComponent:it];
            BOOL isDir = NO;
            [fm fileExistsAtPath:p isDirectory:&isDir];
            NSError *re = nil;
            if ([fm removeItemAtPath:p error:&re]) {
                removed++;
            } else if (isDir) {
                // 目录删不掉 → 进去把内容清掉
                purge(p, depth + 1);
                // 再试一次删空目录
                if ([fm removeItemAtPath:p error:NULL]) removed++;
                else failed++;
            } else {
                failed++;
                if (failed <= 5) {
                    [KSLog add:@"     ✗ %@: %@", it,
                     re.localizedDescription ?: @"未知错误"];
                }
            }
        }
    };
    purge(t.dataContainer, 0);
    [KSLog add:@"     已删除 %lu 项，失败 %lu 项",
     (unsigned long)removed, (unsigned long)failed];
    NSUInteger total = removed;

    // AppGroup 共享容器（group.com.kwai.video）里也有账号痕迹
    NSArray *groups = [self appGroupContainers];
    for (NSString *g in groups) {
        NSError *ge = nil;
        NSArray *items = [fm contentsOfDirectoryAtPath:g error:&ge];
        if (!items) continue;
        NSUInteger ok = 0;
        for (NSString *it in items) {
            if ([it isEqualToString:
                 @".com.apple.mobile_container_manager.metadata.plist"]) continue;
            if ([fm removeItemAtPath:[g stringByAppendingPathComponent:it]
                               error:NULL]) ok++;
        }
        total += ok;
        if (ok) {
            [KSLog add:@"     清理 AppGroup(%@) %lu 项",
             [g lastPathComponent], (unsigned long)ok];
        }
    }

    [KSLog add:@"  ③ 合计清理 %lu 项", (unsigned long)total];

    // 清完刷新守护进程缓存，防它把内存数据写回
    [self flushDaemons];
    [KSLog add:@"  ④ 已刷新 cfprefsd 缓存"];

    // ★ 校验：容器应该基本为空了
    NSArray *after = [fm contentsOfDirectoryAtPath:t.dataContainer error:NULL];
    NSUInteger remain = 0;
    for (NSString *x in after) {
        if (![x isEqualToString:
              @".com.apple.mobile_container_manager.metadata.plist"]) remain++;
    }
    if (remain == 0) {
        [KSLog add:@"  ✓ 容器已清空"];
    } else {
        [KSLog add:@"  ⚠ 容器还剩 %lu 个条目（可能有进程占用）", (unsigned long)remain];
        for (NSString *x in after) {
            if (![x hasPrefix:@"."]) [KSLog add:@"      残留: %@", x];
        }
    }
    return YES;
}

/// 找出所有 group.com.kwai.video 的 AppGroup 共享容器
+ (NSArray<NSString *> *)appGroupContainers {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = @"/var/mobile/Containers/Shared/AppGroup";
    NSMutableArray *out = [NSMutableArray array];
    NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:NULL];
    for (NSString *d in dirs) {
        NSString *c = [root stringByAppendingPathComponent:d];
        NSString *meta = [c stringByAppendingPathComponent:
                          @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *m = [NSDictionary dictionaryWithContentsOfFile:meta];
        NSString *ident = m[@"MCMMetadataIdentifier"];
        if ([ident isKindOfClass:[NSString class]] &&
            ([ident containsString:@"kwai"] || [ident containsString:@"gif"])) {
            [out addObject:c];
        }
    }
    return out;
}

@end
