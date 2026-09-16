// KSDid v16 —— 完全按安卓流程：先改，再重启快手
// v15 已确认：iOS 上所有 did 条目都能改成功（✓成功）
//    NewGifUUID / WeaponUUIDKey / KSCommonIDFAKeychainKey / com.kwai.openSDK.deviceId / CiInfoKey_Re_N
//
// ★ 关键洞察（v15 日志）：
//   插件是在快手「启动后」0.8s/3s/8s 才改的 —— 太晚！
//   快手在启动瞬间已把 did 读进内存 + 上报服务端。
//   安卓的流程是 force-stop → 改文件 → 再启动。
//
// 本版：改完所有位置后，延迟几秒 → 重启快手（只重启一次，防循环）

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <signal.h>
#import <spawn.h>
#import <sys/wait.h>

extern char **environ;

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;
static BOOL g_didRestart = NO;

static NSString *ks_logPath(void) {
    if (g_logPath) return g_logPath;
    NSString *home = NSHomeDirectory();
    if (home.length)
        g_logPath = [home stringByAppendingPathComponent:@"Documents/ksdid_log.txt"];
    else
        g_logPath = @"/var/mobile/Documents/ksdid_log.txt";
    return g_logPath;
}

static void ks_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [msg stringByAppendingString:@"\n"];
    @try {
        NSString *path = ks_logPath();
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
    } @catch (NSException *e) {}
}

static NSString *ks_loadCustomDid(void) {
    NSString *home = NSHomeDirectory();
    NSMutableArray *paths = [NSMutableArray array];
    if (home.length)
        [paths addObject:[home stringByAppendingPathComponent:@"Documents/ks_did.txt"]];
    [paths addObject:@"/var/mobile/Documents/ks_did.txt"];
    for (NSString *p in paths) {
        NSString *t = [NSString stringWithContentsOfFile:p
                                                encoding:NSUTF8StringEncoding error:NULL];
        t = [t stringByTrimmingCharactersInSet:
             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length == 36) return t;
    }
    return nil;
}

// 标记文件：记录已经重启过一次，防死循环
static NSString *ks_flagPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/.ks_restarted"];
}

// ---------- UUID 替换 ----------

static NSData *ks_replaceUUIDsInData(NSData *data, int *countOut) {
    if (!data.length || !g_customDid.length) return nil;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!s.length) return nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    NSArray *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!ms.count) return nil;
    NSMutableString *out = [NSMutableString stringWithString:s];
    int n = 0;
    for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = (NSTextCheckingResult *)ms[(NSUInteger)i];
        NSString *old = [s substringWithRange:m.range];
        if ([old caseInsensitiveCompare:g_customDid] == NSOrderedSame) continue;
        [out replaceCharactersInRange:m.range withString:g_customDid];
        n++;
    }
    if (!n) return nil;
    if (countOut) *countOut = n;
    return [out dataUsingEncoding:NSISOLatin1StringEncoding];
}

// ★ 额外：把 32 位 hex 也换成不带横线的 did（用于 EAccountSDKFakeUUID）
static NSData *ks_replaceHex32InData(NSData *data, int *countOut) {
    if (!data.length || !g_customDid.length) return nil;
    NSString *noDash = [g_customDid stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!s.length) return nil;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"(?<![0-9A-Fa-f-])[0-9a-f]{32}(?![0-9A-Fa-f-])" options:0 error:NULL];
    NSArray *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!ms.count) return nil;
    NSMutableString *out = [NSMutableString stringWithString:s];
    int n = 0;
    for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = (NSTextCheckingResult *)ms[(NSUInteger)i];
        NSString *old = [s substringWithRange:m.range];
        if ([old caseInsensitiveCompare:noDash] == NSOrderedSame) continue;
        // 跳过明显不是 uuid 的（比如 base64 碎片）—— 只替换小写或全 hex 的
        [out replaceCharactersInRange:m.range withString:[noDash lowercaseString]];
        n++;
    }
    if (!n) return nil;
    if (countOut) *countOut = n;
    return [out dataUsingEncoding:NSISOLatin1StringEncoding];
}

// ---------- MMKV ----------

static int ks_patchMMKV(void) {
    if (!g_customDid.length) return 0;
    NSString *mmkvDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mmkv"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:mmkvDir isDirectory:&isDir] || !isDir) return 0;
    int total = 0;
    NSArray *names = @[@"kKSUMMKVStoreKey", @"kKSUHeartBeatReportKey",
                       @"com.kuaishou.KSNewDiskCache.startup",
                       @"com.kuaishou.ConfigCenter.KSStartupService",
                       @"gifshow", @"account_main_app_data"];
    for (NSString *name in names) {
        NSString *p = [mmkvDir stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:p]) continue;
        NSDictionary *attr = [fm attributesOfItemAtPath:p error:NULL];
        NSNumber *perm = attr[NSFilePosixPermissions];
        NSData *data = [NSData dataWithContentsOfFile:p];
        if (!data.length || data.length > 8 * 1024 * 1024) continue;
        int n = 0;
        NSData *nd = ks_replaceUUIDsInData(data, &n);
        if (!nd) continue;
        if ([nd writeToFile:p atomically:NO]) {
            if (perm) [fm setAttributes:@{NSFilePosixPermissions: perm}
                            ofItemAtPath:p error:NULL];
            total += n;
        }
    }
    return total;
}

// ---------- Keychain ----------

static NSArray *ks_candidateKeys(void) {
    return @[@"kuaishou_holdout_did_exp1", @"NewGifUUID", @"EAccountSDKFakeUUID",
             @"WeaponUUIDKey", @"CiInfoKey_Re_N", @"KSCommonIDFAKeychainKey",
             @"com.kwai.openSDK.deviceId"];
}

static BOOL ks_writeKey(NSString *key, NSData *nd) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = key;
    q[(__bridge id)kSecAttrAccount] = key;
    q[(__bridge id)kSecAttrAccessGroup] = @"NR2KD6K4TL.com.jiangjia.gif";
    NSDictionary *upd = @{ (__bridge id)kSecValueData: nd };
    return SecItemUpdate((__bridge CFDictionaryRef)q,
                         (__bridge CFDictionaryRef)upd) == errSecSuccess;
}

static BOOL ks_patchOneKey(NSString *key, BOOL allowHex32) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = key;
    q[(__bridge id)kSecAttrAccount] = key;
    q[(__bridge id)kSecAttrAccessGroup] = @"NR2KD6K4TL.com.jiangjia.gif";
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef r = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &r) != errSecSuccess || !r)
        return NO;
    NSData *data = (__bridge_transfer NSData *)r;
    if (!data.length) return NO;

    int n = 0;
    NSData *nd = ks_replaceUUIDsInData(data, &n);
    if (!nd && allowHex32) {
        int n2 = 0;
        nd = ks_replaceHex32InData(data, &n2);
        n = n2;
    }
    if (!nd) return NO;
    BOOL ok = ks_writeKey(key, nd);
    ks_log(@"[KC写] %@ %d 处 → %@", key, n, ok ? @"✓" : @"✗");
    return ok;
}

static void ks_patchAllKeychain(void) {
    ks_log(@"--- Keychain ---");
    ks_patchOneKey(@"NewGifUUID", NO);
    ks_patchOneKey(@"WeaponUUIDKey", NO);
    ks_patchOneKey(@"KSCommonIDFAKeychainKey", NO);
    ks_patchOneKey(@"com.kwai.openSDK.deviceId", NO);
    ks_patchOneKey(@"CiInfoKey_Re_N", NO);
    ks_patchOneKey(@"EAccountSDKFakeUUID", YES);   // ★ 32 位 hex 格式
    ks_patchOneKey(@"kuaishou_holdout_did_exp1", NO);
}

// ---------- ★ 重启快手 ----------

static void ks_restartKuaishou(void) {
    if (g_didRestart) return;
    g_didRestart = YES;

    // 写标记文件，防止无限重启
    NSString *flag = ks_flagPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:flag]) {
        ks_log(@"[重启] 已有标记，跳过（防循环）");
        return;
    }
    [@"1" writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    ks_log(@"[重启] ★ 开始重启快手...");

    // 用 open 命令重新打开快手（SpringBoard 会重开）
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        pid_t pid;
        const char *args[] = {"/usr/bin/open", "com.jiangjia.gif", NULL};
        int ret = posix_spawn(&pid, "/usr/bin/open", NULL, NULL,
                              (char *const *)args, environ);
        ks_log(@"[重启] open ret=%d pid=%d", ret, (int)pid);
        if (ret != 0) {
            // 备选：uiopen
            char *args2[] = {"/usr/bin/uiopen", "com.jiangjia.gif", NULL};
            ret = posix_spawn(&pid, "/usr/bin/uiopen", NULL, NULL, args2, environ);
            ks_log(@"[重启] uiopen ret=%d", ret);
        }
    });
}

// ---------- 主流程 ----------

static void ks_doPatch(const char *why) {
    if (!g_customDid.length) return;
    ks_log(@"===== %s =====", why);
    ks_log(@"[MMKV] %d 处", ks_patchMMKV());
    ks_patchAllKeychain();
}

%ctor {
    @autoreleasepool {
        g_customDid = ks_loadCustomDid();

        // 第一次：0.5s 改所有位置
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v16 ##########");
                ks_log(@"目标 did = %@", g_customDid ?: @"(未配置)");
                ks_doPatch("+0.5s");
            } @catch (NSException *e) {
                ks_log(@"!!! 异常: %@", e.reason);
            }
        });

        // 第二次：2s 再改（快手可能回写）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try { ks_doPatch("+2s"); } @catch (NSException *e) {}
        });

        // ★ 第三次：4s 后重启快手（确保它重新读取）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_doPatch("+4s");
                ks_log(@"");
                ks_log(@"[重启] 准备重启快手以让它重新读取 did");
                ks_restartKuaishou();
            } @catch (NSException *e) {}
        });
    }
}
