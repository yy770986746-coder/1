// KSDid v15 —— 读取所有候选条目的真实内容
// v14 发现（枚举结果）：
//   kuaishou_holdout_did_exp1 / NewGifUUID / EAccountSDKFakeUUID / WeaponUUIDKey
//   CiInfoKey_Re_N / KSCommonIDFAKeychainKey / KS_CLONE_KEY_N / KS_OUTERID_KEY_N
//   com.kwai.openSDK.deviceId / com.kste.bcinfo
// 本版：dump 每个条目的原始 data（UTF8 直读 + bplist 解析），找出真正的 did

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;

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

static NSString *ks_sha1Empty(void) {
    unsigned char d[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1("", 0, d);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", d[i]];
    return s;
}

static NSString *ks_hex(NSData *d, NSUInteger maxLen) {
    if (!d.length) return @"(空)";
    NSUInteger n = MIN(d.length, maxLen);
    NSMutableString *s = [NSMutableString string];
    const uint8_t *b = (const uint8_t *)[d bytes];
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
    if (d.length > maxLen) [s appendFormat:@"...(%lu字节)", (unsigned long)d.length];
    return s;
}

// ---------- ★ 读取所有候选条目的内容 ----------

static NSArray *ks_candidateKeys(void) {
    return @[
        @"kuaishou_holdout_did_exp1",
        @"NewGifUUID",
        @"EAccountSDKFakeUUID",
        @"WeaponUUIDKey",
        @"CiInfoKey_Re_N",
        @"KSCommonIDFAKeychainKey",
        @"KS_CLONE_KEY_N",
        @"KS_OUTERID_KEY_N",
        @"com.kwai.openSDK.deviceId",
        @"com.kste.bcinfo",
    ];
}

static void ks_dumpOne(NSString *key) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = key;
    q[(__bridge id)kSecAttrAccount] = key;
    q[(__bridge id)kSecAttrAccessGroup] = @"NR2KD6K4TL.com.jiangjia.gif";
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef r = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
    if (st != errSecSuccess || !r) {
        ks_log(@"  【%@】读取失败 status=%d", key, (int)st);
        return;
    }
    NSData *data = (__bridge_transfer NSData *)r;
    ks_log(@"  【%@】%lu 字节", key, (unsigned long)data.length);

    // ① 直接 UTF8
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (s.length && s.length < 500) {
        ks_log(@"     UTF8: %@", [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
    } else {
        // ② base64
        NSString *b64 = [data base64EncodedStringWithOptions:0];
        if (b64.length < 400) ks_log(@"     b64 : %@", b64);
        // ③ hex 头
        ks_log(@"     hex : %@", ks_hex(data, 48));
    }

    // ④ bplist 解析
    id pl = [NSPropertyListSerialization propertyListWithData:data
                    options:NSPropertyListMutableContainers format:NULL error:NULL];
    if (pl) {
        if ([pl isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)pl;
            ks_log(@"     bplist keys: %@", [[d allKeys] componentsJoinedByString:@","]);
            id objs = d[@"$objects"];
            if ([objs isKindOfClass:[NSArray class]]) {
                for (id o in (NSArray *)objs) {
                    if ([o isKindOfClass:[NSString class]]) {
                        NSString *t = (NSString *)o;
                        if (t.length < 400)
                            ks_log(@"       obj: %@", t);
                        else
                            ks_log(@"       obj(%lu): %@...", (unsigned long)t.length,
                                   [t substringToIndex:120]);
                    }
                }
            }
        } else {
            ks_log(@"     plist: %@", pl);
        }
    }

    // ⑤ 找 UUID
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:
        @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        options:0 error:NULL];
    NSString *raw = s ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (raw) {
        NSArray *ms = [re matchesInString:raw options:0 range:NSMakeRange(0, raw.length)];
        for (NSTextCheckingResult *m in ms) {
            ks_log(@"     UUID: %@", [raw substringWithRange:m.range]);
        }
    }
    ks_log(@"");
}

static void ks_dumpAll(void) {
    ks_log(@"");
    ks_log(@"===== ★★ 候选条目内容 dump =====");
    for (NSString *k in ks_candidateKeys()) ks_dumpOne(k);
    ks_log(@"===== dump 结束 =====");
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

// ---------- Keychain 写入 ----------

static BOOL ks_writeKey(NSString *key, NSData *nd) {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = key;
    q[(__bridge id)kSecAttrAccount] = key;
    q[(__bridge id)kSecAttrAccessGroup] = @"NR2KD6K4TL.com.jiangjia.gif";
    NSDictionary *upd = @{ (__bridge id)kSecValueData: nd };
    OSStatus st = SecItemUpdate((__bridge CFDictionaryRef)q,
                                (__bridge CFDictionaryRef)upd);
    return st == errSecSuccess;
}

// 对指定条目做 UUID 替换
static BOOL ks_patchKeyEntry(NSString *key) {
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
    if (!nd) return NO;
    BOOL ok = ks_writeKey(key, nd);
    ks_log(@"[KC写] %@ %d 处 → %@", key, n, ok ? @"✓成功" : @"✗失败");
    return ok;
}

static void ks_patchAllKeychain(void) {
    ks_log(@"");
    ks_log(@"===== ★ Keychain 批量替换 UUID =====");
    for (NSString *k in ks_candidateKeys()) {
        @try { ks_patchKeyEntry(k); } @catch (NSException *e) {}
    }
    ks_log(@"");
}

// ---------- 主流程 ----------

static void ks_doPatch(const char *why) {
    if (!g_customDid.length) return;
    ks_log(@"===== %s =====", why);
    int n = ks_patchMMKV();
    ks_log(@"[MMKV] %d 处", n);
    ks_patchAllKeychain();
}

%ctor {
    @autoreleasepool {
        g_customDid = ks_loadCustomDid();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v15 ##########");
                ks_log(@"目标 did = %@", g_customDid ?: @"(未配置)");
                ks_log(@"sha1(empty) = %@", ks_sha1Empty());
                ks_dumpAll();          // ★ 先看所有条目的真实内容
                ks_doPatch("+0.8s");
                ks_dumpAll();          // ★ 改后再看
            } @catch (NSException *e) {
                ks_log(@"!!! 异常: %@ / %@", e.name, e.reason);
            }
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try { ks_doPatch("+3s"); } @catch (NSException *e) {}
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try { ks_doPatch("+8s"); ks_dumpAll(); } @catch (NSException *e) {}
        });
    }
}
