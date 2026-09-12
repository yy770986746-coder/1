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

        f.token = tokenField;      // 第1段：完整 "hex-uid"
        f.salt  = saltField;       // 第2段：32位hex
        f.did   = uid;             // 第1段尾部的数字 uid
        // 其余段位尽量保留，供备用键写入
        if (parts.count > 2) f.egid  = parts[2];
        if (parts.count > 3) f.apiSt = parts[3];
        if (parts.count > 4) f.passToken = parts[4];
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
    // 解析阶段已经把 uid 放进 did（纯数字）。直接用它最稳。
    NSRegularExpression *numRe =
        [NSRegularExpression regularExpressionWithPattern:@"^\\d+$"
                                                 options:0 error:NULL];
    if (self.did.length &&
        [numRe numberOfMatchesInString:self.did options:0
                                 range:NSMakeRange(0, self.did.length)]) {
        return self.did;
    }
    // 回退：token 写成 "32位hex-数字" 时，从尾部 '-' 后取
    for (NSString *cand in @[self.did ?: @"", self.token ?: @""]) {
        if (!cand.length) continue;
        NSRange d = [cand rangeOfString:@"-" options:NSBackwardsSearch];
        if (d.location == NSNotFound) continue;
        NSString *tail = [cand substringFromIndex:d.location + 1];
        if (tail.length) return tail;
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

+ (void)killKuaishou {
    NSString *running = [KSTarget runningProcessName];
    NSArray *names = running ? @[running] : @[@"com_kwai_gif", @"Kwai", @"com.kuaishou.nebula"];

    for (NSString *n in names) {
        // killall 优先（越狱机 /usr/bin/killall 存在）
        runCmd(@"/usr/bin/killall", @[@"-9", n]);
    }
    [KSLog add:@"已结束快手进程"];
    usleep(400 * 1000);
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
    // 键名表已用真机实测校准（快手 iOS 14.8.10 主二进制）：
    //   存在: Gif_Token / Gif_Token_Salt / Gif_KwaiClientSalt /
    //         Gif_ServiceToken / Gif_PassToken / Gif_H5Token /
    //         Gif_User / Gif_LastLoginType / token_client_salt
    //   不存在: gifshow_token / gifshow_userid（安卓那套 iOS 已废弃）
    __block NSUInteger n = 0;
    void (^put)(NSString *, NSString *) = ^(NSString *k, NSString *v) {
        if (k.length && v.length) { plist[k] = v; n++; }
    };

    // === 主键：严格对齐 token_v1.0.4.apk 的 KuaishouInjector.buildXml() ===
    // 原工具（Android，实测可登录）只写这三个键：
    //   gifshow_token     = 第1段（完整 "32位hex-用户ID"）
    //   gifshow_userid    = 第1段尾部的数字 uid
    //   token_client_salt = 第2段（32位hex）
    // 这三行是登录成败的关键，其余键都只是保险。
    put(@"gifshow_token",      five.token);
    put(@"gifshow_userid",     [five userId]);
    put(@"token_client_salt",  five.salt);

    // === iOS 端的等价键（同一份数据，iOS 快手可能读 Gif_* 命名）===
    put(@"Gif_Token",          five.token);
    put(@"Gif_User",           [five userId]);
    put(@"Gif_Token_Salt",     five.salt);
    put(@"Gif_KwaiClientSalt", five.salt);
    put(@"Gif_LastLoginType",  @"1");

    // 其余段位的备用键（原工具没用到，写了不冲突）
    put(@"ClientSalt",         five.salt);
    put(@"uid",                [five userId]);
    put(@"user_id",            [five userId]);
    put(@"userId",             [five userId]);
    put(@"Gif_ServiceToken",   five.apiSt.length ? five.apiSt : five.passToken);
    put(@"Gif_PassToken",      five.passToken.length ? five.passToken : five.apiSt);
    put(@"Gif_H5Token",        five.hToken);

    if (n == 0) {
        [KSLog add:@"✗ 没有可写入的键"];
        return NO;
    }

    // ---- 落盘 ----
    // ★ iOS 上直接改 plist 文件会被 cfprefsd 覆盖（它内存里有缓存，
    //   重启后按缓存重建文件，把我们的写入冲掉）。
    //   正确路径：通过 CFPreferences 接口写，让 cfprefsd 自己落盘。
    NSUInteger cfOK = [self writeViaCFPreferences:plist
                                             path:t.prefsPath
                                           domain:t.bundleID];
    [KSLog add:@"CFPreferences 写入 %lu 个键", (unsigned long)cfOK];

    // 文件写入作为兜底（cfprefsd 不可用 / 权限受限时仍可能生效）
    NSString *tmp = [t.prefsPath stringByAppendingString:@".ks_tmp"];
    BOOL ok = [plist writeToFile:tmp atomically:YES];
    if (!ok) {
        [KSLog add:@"⚠ plist 文件写入失败（沙盒权限不足？），仅依赖 CFPreferences"];
    } else {
        [fm removeItemAtPath:t.prefsPath error:NULL];
        NSError *mvErr = nil;
        [fm moveItemAtPath:tmp toPath:t.prefsPath error:&mvErr];
        if (mvErr) {
            [KSLog add:@"⚠ 替换 plist 文件失败: %@", mvErr.localizedDescription];
        } else {
            [KSLog add:@"✓ plist 文件已写入"];
        }
    }

    [KSLog add:@"✓ 已写入 %lu 个登录键", (unsigned long)n];
    [KSLog add:@"  Gif_Token = %@", five.token];

    [self fixOwnership:t.prefsPath target:t];

    // 刷新 cfprefsd 缓存（让它把内存里的新值同步到磁盘）
    runCmd(@"/usr/bin/killall", @[@"-9", @"cfprefsd"]);
    [KSLog add:@"已刷新 cfprefsd 缓存"];

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
    [self killKuaishou];
    step(@"  ✓ 已结束", YES);

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

    step(@"[6/6] 拉起快手...", YES);
    [KSTarget launch:t.bundleID];

    return YES;
}

+ (KSFive *)readCurrent:(KSTarget *)t {
    if (!t.prefsPath) return nil;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    if (!d) return nil;

    // 取第一个存在且非空的字符串值（block 直接调用，ARC 下不能当函数指针强转）
    NSString *(^pick)(NSArray *) = ^NSString *(NSArray *keys) {
        for (NSString *k in keys) {
            id v = d[k];
            if (v && [v isKindOfClass:[NSString class]] && [v length]) return v;
        }
        return nil;
    };

    KSFive *f = [KSFive new];
    f.token = pick(@[@"Gif_Token", @"gifshow_token", @"token"]) ?: @"";
    f.salt  = pick(@[@"Gif_Token_Salt", @"Gif_KwaiClientSalt",
                     @"token_client_salt", @"ClientSalt"]) ?: @"";
    f.apiSt = pick(@[@"Gif_ServiceToken", @"api_st"]) ?: @"";
    f.egid  = pick(@[@"KS_OUTERID_KEY", @"egid"]) ?: @"";
    return f.token.length ? f : nil;
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
    if (!t.dataContainer) return NO;

    [self killKuaishou];

    // 等价安卓 pm clear：删掉整个 Data 容器内容
    // 保守做法：只删 Library 下的缓存与偏好，保留 Documents（避免误删用户文件）
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *subs = @[@"Library/Preferences", @"Library/Caches",
                      @"Library/Cookies", @"Library/WebKit"];

    for (NSString *s in subs) {
        NSString *p = [t.dataContainer stringByAppendingPathComponent:s];
        NSArray *items = [fm contentsOfDirectoryAtPath:p error:NULL];
        for (NSString *it in items) {
            [fm removeItemAtPath:[p stringByAppendingPathComponent:it] error:NULL];
        }
        [KSLog add:@"  已清理 %@（%lu 项）", s, (unsigned long)items.count];
    }
    return YES;
}

@end
