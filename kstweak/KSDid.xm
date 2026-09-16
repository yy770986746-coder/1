// KSDid v13 —— 关键突破版
// v12 发现：
//   1. Keychain 里快手有 142 条，agrp 全部是 "NR2KD6K4TL.com.jiangjia.gif"
//   2. 插件 entitlements 是 "com.jiangjia.gif"（无 TeamID）→ 访问不了
//   3. 有个 svce=sha1("") 的条目被反复写 110 次 ← 极可能是 did
// 本版：
//   1. ★ 枚举所有 Keychain 条目（打印明文 svce/acct，找 did 的真实条目）
//   2. ★ 用正确的 access group 重试写入
//   3. 尝试多个候选 access group

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;

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

// sha1 空串
static NSString *ks_sha1Empty(void) {
    unsigned char d[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1("", 0, d);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
    return s;
}

// ---------- ★ 枚举所有 Keychain 条目 ----------

static void ks_dumpKeychain(void) {
    ks_log(@"");
    ks_log(@"===== ★ Keychain 枚举 =====");

    NSArray *classes = @[@(kSecClassGenericPassword), @(kSecClassInternetPassword)];
    NSArray *classNames = @[@"genp", @"inet"];

    for (NSUInteger ci = 0; ci < classes.count; ci++) {
        NSDictionary *q = @{
            (__bridge id)kSecClass: classes[ci],
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnData: @NO
        };
        CFTypeRef r = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
        if (st != errSecSuccess || !r) {
            ks_log(@"[枚举] %@ status=%d", classNames[ci], (int)st);
            continue;
        }
        NSArray *items = (__bridge_transfer NSArray *)r;
        ks_log(@"[枚举] %@ 共 %lu 条", classNames[ci], (unsigned long)items.count);

        for (NSDictionary *it in items) {
            @try {
                NSString *svc = it[(__bridge id)kSecAttrService];
                NSString *acct = it[(__bridge id)kSecAttrAccount];
                NSString *agrp = it[(__bridge id)kSecAttrAccessGroup];
                NSNumber *ctyp = it[(__bridge id)kSecAttrCreator];
                if (![svc isKindOfClass:[NSString class]]) {
                    // 二进制 service（加密显示）
                    NSData *svd = (NSData *)svc;
                    if ([svd isKindOfClass:[NSData class]])
                        svc = [NSString stringWithFormat:@"<bin:%@>",
                               [svd subdataWithRange:NSMakeRange(0, MIN(12, svd.length))]];
                    else svc = @"<?>";
                }
                if (![acct isKindOfClass:[NSString class]]) {
                    NSData *acd = (NSData *)acct;
                    if ([acd isKindOfClass:[NSData class]])
                        acct = [NSString stringWithFormat:@"<bin:%@>",
                                [acd subdataWithRange:NSMakeRange(0, MIN(12, acd.length))]];
                    else acct = @"<?>";
                }
                // 只看可能有用的
                NSString *low = [NSString stringWithFormat:@"%@ %@", svc, acct].lowercaseString;
                if ([low rangeOfString:@"ci"].location != NSNotFound ||
                    [low rangeOfString:@"did"].location != NSNotFound ||
                    [low rangeOfString:@"device"].location != NSNotFound ||
                    [low rangeOfString:@"kwai"].location != NSNotFound ||
                    [low rangeOfString:@"gif"].location != NSNotFound ||
                    [low rangeOfString:@"ks"].location != NSNotFound ||
                    [low rangeOfString:@"uuid"].location != NSNotFound ||
                    [svc rangeOfString:@"bin:"].location != NSNotFound) {
                    ks_log(@"  svce=%@ acct=%@ agrp=%@ ctyp=%@",
                           svc, acct, agrp, ctyp);
                }
            } @catch (NSException *e) {}
        }
    }
    ks_log(@"===== 枚举结束 =====");
    ks_log(@"");
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
        }
    }
    ks_log(@"[MMKV] 共 %d 处", total);
    return total;
}

// ---------- ★ Keychain 写入（多 access group 尝试）----------

static BOOL ks_writeOne(NSString *svce, NSString *acct, NSData *newData, NSString *agrp) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    if (svce) q[(__bridge id)kSecAttrService] = svce;
    if (acct) q[(__bridge id)kSecAttrAccount] = acct;
    if (agrp) q[(__bridge id)kSecAttrAccessGroup] = agrp;

    NSDictionary *upd = @{ (__bridge id)kSecValueData: newData };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)upd);
    if (st == errSecSuccess) {
        ks_log(@"[KC写] ✓ svce=%@ acct=%@ agrp=%@", svce, acct, agrp);
        return YES;
    }
    if (st == errSecItemNotFound) {
        NSMutableDictionary *a = [q mutableCopy];
        a[(__bridge id)kSecValueData] = newData;
        a[(__bridge id)kSecAttrAccessible] =
            (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
        OSStatus st2 = SecItemAdd((__bridge CFDictionaryRef)a, NULL);
        ks_log(@"[KC写] add svce=%@ agrp=%@ status=%d", svce, agrp, (int)st2);
        return st2 == errSecSuccess;
    }
    ks_log(@"[KC写] ✗ svce=%@ agrp=%@ status=%d", svce, agrp, (int)st);
    return NO;
}

static BOOL ks_patchKeychain(void) {
    if (!g_customDid.length) return NO;
    BOOL any = NO;
    @try {
        NSString *key = @"CiInfoKey_Re_N";
        NSArray *agrps = @[@"NR2KD6K4TL.com.jiangjia.gif",
                           @"com.jiangjia.gif",
                           nil];

        for (id ag in agrps) {
            NSString *agrp = (ag == [NSNull null]) ? nil : (NSString *)ag;
            // 读
            NSMutableDictionary *rq = [NSMutableDictionary dictionary];
            rq[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
            rq[(__bridge id)kSecAttrService] = key;
            rq[(__bridge id)kSecAttrAccount] = key;
            if (agrp) rq[(__bridge id)kSecAttrAccessGroup] = agrp;
            rq[(__bridge id)kSecReturnData] = @YES;
            rq[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

            CFTypeRef r = NULL;
            OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)rq, &r);
            ks_log(@"[KC读] agrp=%@ status=%d", agrp ?: @"(nil)", (int)st);
            if (st != errSecSuccess || !r) continue;
            NSData *data = (__bridge_transfer NSData *)r;
            if (!data.length) continue;

            id parsed = [NSPropertyListSerialization propertyListWithData:data
                                options:NSPropertyListMutableContainers
                                 format:NULL error:NULL];
            if (![parsed isKindOfClass:[NSDictionary class]]) continue;
            NSMutableArray *objs = ((NSDictionary *)parsed)[@"$objects"];
            if (![objs isKindOfClass:[NSMutableArray class]]) continue;

            BOOL changed = NO;
            for (NSUInteger i = 0; i < objs.count; i++) {
                id o = objs[i];
                if (![o isKindOfClass:[NSString class]]) continue;
                NSString *s = (NSString *)o;
                if (s.length < 20) continue;
                NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
                if (!dec.length) continue;
                NSString *json = [[NSString alloc] initWithData:dec
                                                      encoding:NSUTF8StringEncoding];
                if (!json.length || [json rangeOfString:@"cloud_did"].location == NSNotFound) continue;
                NSRegularExpression *re =
                    [NSRegularExpression regularExpressionWithPattern:
                     @"(\"cloud_did\"\\s*:\\s*\")([^\"]*)(\")" options:0 error:NULL];
                NSString *nj = [re stringByReplacingMatchesInString:json options:0
                                    range:NSMakeRange(0, json.length)
                             withTemplate:[NSString stringWithFormat:@"$1%@$3", g_customDid]];
                if ([nj isEqualToString:json]) continue;
                objs[i] = [[nj dataUsingEncoding:NSUTF8StringEncoding]
                           base64EncodedStringWithOptions:0];
                changed = YES;
            }
            if (!changed) { ks_log(@"  → json 已是目标值"); continue; }

            NSData *nd = [NSPropertyListSerialization dataWithPropertyList:parsed
                            format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
            if (!nd.length) continue;
            if (ks_writeOne(key, key, nd, agrp)) any = YES;
        }
    } @catch (NSException *e) {
        ks_log(@"[KC] 异常: %@", e.reason);
    }
    return any;
}

static void ks_doPatch(const char *why) {
    if (!g_customDid.length) return;
    ks_log(@"===== %s =====", why);
    ks_patchMMKV();
    ks_patchKeychain();
}

%ctor {
    @autoreleasepool {
        g_customDid = ks_loadCustomDid();
        ks_log(@"");
        ks_log(@"########## KSDid v13 ##########");
        ks_log(@"目标 did = %@", g_customDid ?: @"(未配置)");
        ks_log(@"sha1(empty) = %@", ks_sha1Empty());
        if (!g_customDid.length) return;

        // ★ 枚举 Keychain（在启动早期做，看快手还没写之前的原始值）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_dumpKeychain();
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+1s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{ ks_doPatch("+3s"); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_doPatch("+8s");
            ks_dumpKeychain();
        });
    }
}
