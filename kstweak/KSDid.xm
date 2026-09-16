// KSDid v12 —— 修复 Keychain 更新（status=-50 errSecParam）
// v11 发现：SecItemUpdate 返回 -50，因为 query 字典里包含了 kSecReturnData/kSecReturnAttributes
//          （这些是"返回值描述"键，不能出现在 Update 的 query 里）
// 本版：query 用"纯查询字典"，update 用独立字典

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

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

// ---------- MMKV ----------

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

static int ks_patchMMKV(void) {
    if (!g_customDid.length) return 0;
    NSString *home = NSHomeDirectory();
    NSString *mmkvDir = [home stringByAppendingPathComponent:@"Documents/mmkv"];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:mmkvDir isDirectory:&isDir] || !isDir) return 0;

    int total = 0;
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
            total += n;
            ks_log(@"[MMKV] ✓ %@ 改 %d 处", name, n);
        }
    }
    ks_log(@"[MMKV] 共 %d 处", total);
    return total;
}

// ---------- Keychain（修复版） ----------

static BOOL ks_patchKeychain(void) {
    if (!g_customDid.length) return NO;
    @try {
        NSString *key = @"CiInfoKey_Re_N";

        // ★ 查询字典：只含"定位"用的键，不含 kSecReturnData / kSecReturnAttributes
        NSDictionary *baseQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: key,
            (__bridge id)kSecAttrAccount: key
        };

        // 读：在 baseQuery 上加返回描述
        NSMutableDictionary *readQuery = [baseQuery mutableCopy];
        readQuery[(__bridge id)kSecReturnData] = @YES;
        readQuery[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
        readQuery[(__bridge id)kSecReturnAttributes] = @NO;

        CFTypeRef r = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)readQuery, &r);
        if (st != errSecSuccess || !r) {
            ks_log(@"[KC] 读取失败 status=%d", (int)st);
            return NO;
        }
        NSData *data = (__bridge_transfer NSData *)r;
        if (!data.length) { ks_log(@"[KC] data 空"); return NO; }

        NSError *err = nil;
        id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListMutableContainers
                                                              format:NULL error:&err];
        if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) {
            ks_log(@"[KC] bplist 解析失败");
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
        }
        if (!changed) { ks_log(@"[KC] 已是目标值"); return NO; }

        NSData *newData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0 error:NULL];
        if (!newData.length) return NO;

        // ★ update 字典：只含 kSecValueData
        NSDictionary *upd = @{ (__bridge id)kSecValueData: newData };
        OSStatus st2 = SecItemUpdate((__bridge CFDictionaryRef)baseQuery,
                                     (__bridge CFDictionaryRef)upd);
        ks_log(@"[KC] SecItemUpdate status=%d", (int)st2);

        if (st2 == errSecItemNotFound) {
            // 不存在 → 新建
            NSMutableDictionary *addQ = [baseQuery mutableCopy];
            addQ[(__bridge id)kSecValueData] = newData;
            addQ[(__bridge id)kSecAttrAccessible] =
                (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
            OSStatus st3 = SecItemAdd((__bridge CFDictionaryRef)addQ, NULL);
            ks_log(@"[KC] SecItemAdd status=%d", (int)st3);
            return st3 == errSecSuccess;
        }
        return st2 == errSecSuccess;
    } @catch (NSException *e) {
        ks_log(@"[KC] 异常: %@", e.reason);
        return NO;
    }
}

static void ks_doPatch(const char *why) {
    if (!g_customDid.length) return;
    g_writes++;
    ks_log(@"===== 第 %d 次写入 (%s) =====", g_writes, why);
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
        ks_log(@"===== KSDid v12 (修复Keychain) =====");
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");
        if (!g_customDid.length) return;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+0.5s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+2s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+5s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+10s"); });
    }
}
