// KSDid v11 —— 自动写入版
// 思路：插件注入快手后，【主动把 did 写进 MMKV 和 Keychain】
//      不需要外部杀进程，快手启动时插件先改好，快手读到的就是新值
//
// 已确认的 did 存储：
//   1) MMKV 文件: <容器>/Documents/mmkv/kKSUMMKVStoreKey 等（明文 UUID）
//   2) Keychain:  CiInfoKey_Re_N（bplist + base64 JSON 里的 cloud_did）
//
// 配置: 快手沙盒 Documents/ks_did.txt （一行 UUID）
// 日志: 快手沙盒 Documents/ksdid_log.txt

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;
static int g_writes = 0;

static NSString *ks_logPath(void) {
    if (g_logPath) return g_logPath;
    NSString *home = NSHomeDirectory();
    NSArray *cands = @[
        [home stringByAppendingPathComponent:@"Documents/ksdid_log.txt"],
        @"/var/mobile/Documents/ksdid_log.txt"
    ];
    for (NSString *p in cands) {
        if ([@"init" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:NULL]) {
            g_logPath = p;
            return p;
        }
    }
    g_logPath = cands.firstObject;
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

/// 把 data 里所有 UUID 形态的串换成自定义 did
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

/// 修改快手沙盒里的 MMKV 文件
static int ks_patchMMKV(void) {
    if (!g_customDid.length) return 0;
    NSString *home = NSHomeDirectory();     // 快手的沙盒
    NSString *mmkvDir = [home stringByAppendingPathComponent:@"Documents/mmkv"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:mmkvDir isDirectory:&isDir] || !isDir) {
        ks_log(@"[MMKV] 目录不存在: %@", mmkvDir);
        return 0;
    }
    NSArray *files = [fm contentsOfDirectoryAtPath:mmkvDir error:NULL];
    ks_log(@"[MMKV] 目录有 %lu 个文件", (unsigned long)files.count);

    int total = 0, touched = 0;
    // 优先这几个关键文件
    NSArray *priority = @[@"kKSUMMKVStoreKey", @"kKSUHeartBeatReportKey",
                          @"com.kuaishou.KSNewDiskCache.startup",
                          @"com.kuaishou.ConfigCenter.KSStartupService"];
    for (NSString *name in priority) {
        NSString *p = [mmkvDir stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:p]) continue;

        NSDictionary *attr = [fm attributesOfItemAtPath:p error:NULL];
        NSNumber *perm = attr[NSFilePosixPermissions];

        NSData *data = [NSData dataWithContentsOfFile:p];
        if (!data.length || data.length > 8 * 1024 * 1024) continue;

        int n = 0;
        NSData *newData = ks_replaceUUIDsInData(data, &n);
        if (!newData) continue;

        if ([newData writeToFile:p atomically:NO]) {
            if (perm) [fm setAttributes:@{NSFilePosixPermissions: perm}
                            ofItemAtPath:p error:NULL];
            touched++; total += n;
            ks_log(@"[MMKV] ✓ %@ 改 %d 处", name, n);
        } else {
            ks_log(@"[MMKV] ✗ %@ 写入失败", name);
        }
    }
    ks_log(@"[MMKV] 共改 %d 文件 %d 处", touched, total);
    return total;
}

/// 修改 Keychain 里的 CiInfoKey_Re_N
static BOOL ks_patchKeychain(void) {
    if (!g_customDid.length) return NO;
    @try {
        NSDictionary *q = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: @"CiInfoKey_Re_N",
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
        };
        CFTypeRef r = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
        if (st != errSecSuccess || !r) {
            ks_log(@"[KC] 读取失败 status=%d", (int)st);
            return NO;
        }
        NSDictionary *d = (__bridge_transfer NSDictionary *)r;
        NSData *data = d[(__bridge id)kSecValueData];
        if (!data.length) return NO;

        NSError *err = nil;
        id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListMutableContainers
                                                              format:NULL error:&err];
        if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) {
            ks_log(@"[KC] bplist 解析失败: %@", err.localizedDescription);
            return NO;
        }
        NSMutableDictionary *plist = (NSMutableDictionary *)parsed;
        NSMutableArray *objs = plist[@"$objects"];
        if (![objs isKindOfClass:[NSMutableArray class]]) return NO;

        BOOL changed = NO;
        for (NSUInteger i = 0; i < objs.count; i++) {
            id o = objs[i];
            if (![o isKindOfClass:[NSString class]]) continue;
            NSString *s = (NSString *)o;
            if (s.length < 20) continue;

            NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
            if (!dec.length) continue;
            NSString *json = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
            if (!json.length || [json rangeOfString:@"cloud_did"].location == NSNotFound) continue;

            NSRegularExpression *re =
                [NSRegularExpression regularExpressionWithPattern:
                 @"(\"cloud_did\"\\s*:\\s*\")([^\"]*)(\")" options:0 error:NULL];
            NSString *nj = [re stringByReplacingMatchesInString:json options:0
                                                          range:NSMakeRange(0, json.length)
                                                   withTemplate:
                            [NSString stringWithFormat:@"$1%@$3", g_customDid]];
            if ([nj isEqualToString:json]) continue;

            objs[i] = [[nj dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            changed = YES;
            ks_log(@"[KC] cloud_did: %@ → %@", json, nj);
        }
        if (!changed) { ks_log(@"[KC] 无需修改"); return NO; }

        NSData *newData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0 error:NULL];
        if (!newData.length) return NO;

        NSMutableDictionary *upd = [NSMutableDictionary dictionary];
        upd[(__bridge id)kSecValueData] = newData;
        OSStatus st2 = SecItemUpdate((__bridge CFDictionaryRef)q,
                                     (__bridge CFDictionaryRef)upd);
        ks_log(@"[KC] SecItemUpdate status=%d", (int)st2);
        return st2 == errSecSuccess;
    } @catch (NSException *e) {
        ks_log(@"[KC] 异常: %@", e.reason);
        return NO;
    }
}

/// 执行一次完整写入
static void ks_doPatch(const char *why) {
    if (!g_customDid.length) return;
    g_writes++;
    ks_log(@"===== 第 %d 次写入 (触发: %s) =====", g_writes, why);
    ks_patchMMKV();
    ks_patchKeychain();
    ks_log(@"===== 完成 =====");
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid v11 (自动写入) =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        if (!g_customDid.length) return;

        // 多次触发：快手启动是异步的，MMKV 可能稍后才建好
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("启动+0.5s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("启动+2s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("启动+5s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("启动+10s"); });
    }
}
