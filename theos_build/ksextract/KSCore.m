//
//  KSCore.m
//  iOS 快手上号器 —— 核心引擎实现
//

#import "KSCore.h"
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <spawn.h>
#import <signal.h>
#import <dlfcn.h>

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
            f.h5Token  = j[@"h5Token"];
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

        KSFive *f = [KSFive new];
        f.token = parts[0];
        f.salt  = parts[1];
        if (parts.count > 2) f.did   = parts[2];
        if (parts.count > 3) f.egid  = parts[3];
        if (parts.count > 4) f.apiSt = parts[4];
        return f;
    }

    // ---- 键值对兜底 ----
    NSRegularExpression *kvRe =
        [NSRegularExpression regularExpressionWithPattern:
         @"\\b(token|salt|did|egid|api_st|client_salt)\\b\\s*[=:]\\s*([^\\s,;&\\n]+)"
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
        f.did   = d[@"did"] ?: @"";
        f.egid  = d[@"egid"] ?: @"";
        f.apiSt = d[@"api_st"] ?: @"";
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
    if (!self.token.length) return @"未知";
    NSRange d = [self.token rangeOfString:@"-" options:NSBackwardsSearch];
    return (d.location != NSNotFound) ? [self.token substringFromIndex:d.location + 1] : @"未知";
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

/// 用私有 API 拿容器路径（App 带平台权限时可用）
+ (NSString *)containerForBundleID:(NSString *)bid {
    // 1) MCM 私有接口（iOS 14+，越狱机上 App 有平台权限即可调）
    Class mcm = NSClassFromString(@"MCMAppContainer");
    if (mcm) {
        id inst = ((id(*)(id, SEL))objc_msgSend)(mcm,
                    NSSelectorFromString(@"containerWithIdentifier:createIfNecessary:error:"));
        (void)inst;
    }

    // 2) 标准容器路径探测（无根越狱）
    NSArray *roots = @[
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
    ];
    NSFileManager *fm = [NSFileManager defaultManager];

    for (NSString *root in roots) {
        NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *d in dirs) {
            NSString *container = [root stringByAppendingPathComponent:d];
            // 读 .com.apple.mobile_container_manager.metadata.plist 确认归属
            NSString *meta = [container stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *md = [NSDictionary dictionaryWithContentsOfFile:meta];
            if ([md[@"MCMMetadataIdentifier"] isEqualToString:bid]) {
                return container;
            }
        }
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
        NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *d in dirs) {
            NSString *p = [root stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"%@/%@.app", d, bid]];
            if ([fm fileExistsAtPath:p]) return p;
        }
    }
    return nil;
}

+ (BOOL)isInstalled:(NSString *)bid {
    return [self bundlePathForBundleID:bid] != nil;
}

+ (instancetype)forBundleID:(NSString *)bid {
    NSString *bp = [self bundlePathForBundleID:bid];
    if (!bp) return nil;

    KSTarget *t = [KSTarget new];
    t.bundleID = bid;
    t.bundlePath = bp;
    t.dataContainer = [self containerForBundleID:bid];

    if (t.dataContainer) {
        t.prefsPath = [t.dataContainer stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"Library/Preferences/%@.plist", bid]];
    }
    // 进程名：可执行文件 basename
    t.processName = [bp.lastPathComponent stringByDeletingPathExtension];
    return t;
}

+ (instancetype)detect {
    for (NSString *bid in [self allBundleIDs]) {
        KSTarget *t = [self forBundleID:bid];
        if (t && t.dataContainer) return t;
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

    // 2) LSApplicationWorkspace 私有接口
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (ws) {
        id inst = ((id(*)(id, SEL))objc_msgSend)(ws,
                    NSSelectorFromString(@"defaultWorkspace"));
        if (inst) {
            BOOL ok = ((BOOL(*)(id, SEL, id))objc_msgSend)(inst,
                        NSSelectorFromString(@"openApplicationWithBundleID:"), bid);
            if (ok) {
                [KSLog add:@"通过 LSApplicationWorkspace 拉起 %@", bid];
                return YES;
            }
        }
    }
    [KSLog add:@"✗ 拉起失败，请手动点击快手图标"];
    return NO;
}

@end

#pragma mark - ========== 注入引擎 ==========

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
    if (!t.prefsPath) {
        [KSLog add:@"✗ 未定位到快手 Preferences 路径"];
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [t.prefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                       attributes:nil error:NULL];
        [KSLog add:@"创建 Preferences 目录"];
    }

    // 读现有 plist（保留其他键，不破坏快手配置）
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    if (old) {
        [plist addEntriesFromDictionary:old];
        [KSLog add:@"读取现有 plist，%lu 个键将被保留", (unsigned long)old.count];
    }

    // ---- 写入登录键 ----
    // 对照组：安卓版只写 gifshow_token / gifshow_userid / token_client_salt
    // iOS 侧快手用的是 Gif_* 命名空间，两套都写，确保命中
    NSUInteger n = 0;
    void (^put)(NSString *, NSString *) = ^(NSString *k, NSString *v) {
        if (k.length && v.length) { plist[k] = v; n++; }
    };

    // iOS 原生键（主线）
    put(@"Gif_Token",          five.token);
    put(@"Gif_Token_Salt",     five.salt);
    put(@"Gif_KwaiClientSalt", five.salt);
    put(@"ClientSalt",         five.salt);

    // 安卓等价键（兜底，部分版本共用）
    put(@"gifshow_token",      five.token);
    put(@"gifshow_userid",     [five userId]);
    put(@"token_client_salt",  five.salt);

    // 可选参
    put(@"Gif_ServiceToken",   five.apiSt);
    put(@"Gif_H5Token",        five.h5Token);
    put(@"Gif_PassToken",      five.passToken);
    put(@"KS_OUTERID_KEY",     five.egid);

    if (n == 0) {
        [KSLog add:@"✗ 没有可写入的键"];
        return NO;
    }

    // ---- 落盘 ----
    // 先写临时文件再原子替换，避免写一半损坏（快手有 plist 完整性检查时的保险）
    NSString *tmp = [t.prefsPath stringByAppendingString:@".ks_tmp"];
    BOOL ok = [plist writeToFile:tmp atomically:YES];
    if (!ok) {
        [KSLog add:@"✗ plist 写入失败（沙盒权限不足？）"];
        return NO;
    }
    [fm removeItemAtPath:t.prefsPath error:NULL];
    NSError *mvErr = nil;
    [fm moveItemAtPath:tmp toPath:t.prefsPath error:&mvErr];
    if (mvErr) {
        [KSLog add:@"✗ 替换 plist 失败: %@", mvErr.localizedDescription];
        return NO;
    }

    [KSLog add:@"✓ 已写入 %lu 个登录键", (unsigned long)n];
    [KSLog add:@"  Gif_Token = %@", five.token];

    [self fixOwnership:t.prefsPath target:t];

    // 清掉可能干扰的缓存
    NSString *cfprefsd = [@"/usr/bin/killall" copy];
    runCmd(cfprefsd, @[@"-9", @"cfprefsd"]);
    [KSLog add:@"已刷新 cfprefsd 缓存"];

    return YES;
}

+ (BOOL)loginWithFive:(KSFive *)five
                target:(KSTarget *)t
              progress:(void (^)(NSString *, BOOL))progress {

    void (^step)(NSString *, BOOL) = ^(NSString *s, BOOL ok) {
        [KSLog add:@"%@", s];
        if (progress) progress(s, ok);
    };

    step(@"[1/6] 检查目标 App...", YES);
    if (!t || !t.dataContainer) {
        step(@"✗ 未找到快手沙盒，请先打开一次快手", NO);
        return NO;
    }
    step([NSString stringWithFormat:@"  ✓ %@", t.bundleID], YES);
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

    id pick = ^NSString *(NSArray *keys) {
        for (NSString *k in keys) {
            id v = d[k];
            if (v && [v isKindOfClass:[NSString class]] && [v length]) return v;
        }
        return nil;
    };

    KSFive *f = [KSFive new];
    f.token = ((NSString *(*)(NSArray *))pick)(@[@"Gif_Token", @"gifshow_token", @"token"]) ?: @"";
    f.salt  = ((NSString *(*)(NSArray *))pick)(@[@"Gif_Token_Salt", @"Gif_KwaiClientSalt",
                                                 @"token_client_salt", @"ClientSalt"]) ?: @"";
    f.apiSt = ((NSString *(*)(NSArray *))pick)(@[@"Gif_ServiceToken", @"api_st"]) ?: @"";
    f.egid  = ((NSString *(*)(NSArray *))pick)(@[@"KS_OUTERID_KEY", @"egid"]) ?: @"";
    return f.token.length ? f : nil;
}

+ (BOOL)clearLogin:(KSTarget *)t {
    if (!t.prefsPath) return NO;

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:t.prefsPath];
    if (old) [d addEntriesFromDictionary:old];

    NSArray *loginKeys = @[
        @"Gif_Token", @"Gif_Token_Salt", @"Gif_KwaiClientSalt", @"ClientSalt",
        @"gifshow_token", @"gifshow_userid", @"token_client_salt",
        @"Gif_ServiceToken", @"Gif_H5Token", @"Gif_PassToken",
        @"KS_OUTERID_KEY", @"token", @"egid",
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
