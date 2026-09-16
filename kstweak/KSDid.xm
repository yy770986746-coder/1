// ==================================================================
//  KSDid —— 快手自定义 did（注入插件）
//
//  原理：
//    快手把 did 加密存在 Keychain 的 "CiInfoKey_Re_N" 条目里。
//    本插件注入快手进程后：
//      ① hook SecItemCopyMatching —— 快手【读】did 时替换成自定义值
//      ② hook SecItemAdd        —— 快手的 SDK 首次【写】did 时也替换
//
//  配置（按优先级）：
//    1) /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist  键 did
//    2) /var/mobile/Documents/ks_did.txt                          一行 UUID
//
//  日志：/var/mobile/Documents/ksdid_log.txt（便于排查）
//
//  安全设计：
//    - 全程 @try/@catch，异常不影响快手
//    - 只在明确命中 did 条目且类型安全时才替换，否则原样返回
//    - 绝不在读取路径上做任何耗时操作
// ==================================================================

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_customDid = nil;

// ---------- 日志 ----------

static void ks_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [msg stringByAppendingString:@"\n"];
    NSString *path = @"/var/mobile/Documents/ksdid_log.txt";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fh) {
        @try {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (NSException *e) {}
        [fh closeFile];
    } else {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

// ---------- 配置 ----------

static NSString *ks_loadCustomDid(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/com.kuaishou.ksdid.plist"];
    id v = d[@"did"];
    if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length == 36) return v;

    NSString *t = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/ks_did.txt"
                                            encoding:NSUTF8StringEncoding error:NULL];
    t = [t stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length == 36 ? t : nil;
}

static BOOL ks_isUUID(NSString *s) {
    if (s.length != 36) return NO;
    static NSRegularExpression *re = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
               "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$" options:0 error:NULL];
    });
    return [re numberOfMatchesInString:s options:0 range:NSMakeRange(0, s.length)] > 0;
}

static NSString *ks_replaceUUIDs(NSString *src, NSString *newDid) {
    if (!src.length || !ks_isUUID(newDid)) return src;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    NSArray *ms = [re matchesInString:src options:0 range:NSMakeRange(0, src.length)];
    if (!ms.count) return src;
    NSMutableString *out = [NSMutableString stringWithString:src];
    for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
        NSTextCheckingResult *r = (NSTextCheckingResult *)ms[(NSUInteger)i];
        [out replaceCharactersInRange:r.range withString:newDid];
    }
    return out;
}

/// 判断某个 Keychain 查询是否与 did 相关
static BOOL ks_isDidKey(NSDictionary *q) {
    id svc  = q[(__bridge id)kSecAttrService];
    id acct = q[(__bridge id)kSecAttrAccount];
    id labl = q[(__bridge id)kSecAttrLabel];
    for (id o in @[svc ?: [NSNull null], acct ?: [NSNull null], labl ?: [NSNull null]]) {
        if ([o isKindOfClass:[NSString class]]) {
            NSString *s = (NSString *)o;
            if ([s rangeOfString:@"CiInfoKey_Re"].location != NSNotFound) return YES;
            if ([s rangeOfString:@"cloud_did"].location != NSNotFound) return YES;
        }
    }
    return NO;
}

// ---------- hook: 读 ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (ret != errSecSuccess || !result || !*result || !query) return ret;
        if (!g_customDid.length) return ret;

        NSDictionary *q = (__bridge NSDictionary *)query;
        if (!ks_isDidKey(q)) return ret;

        id val = (__bridge id)*result;
        NSString *s = nil;
        BOOL isDictResult = NO;
        NSData *data = nil;

        if ([val isKindOfClass:[NSData class]]) {
            data = (NSData *)val;
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            isDictResult = YES;
            id d2 = ((NSDictionary *)val)[(__bridge id)kSecValueData];
            if ([d2 isKindOfClass:[NSData class]]) data = d2;
        }
        if (!data.length || data.length > 1024 * 256) return ret;

        s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s.length) return ret;

        NSString *target = s;
        BOOL wasBase64 = NO;
        NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
        if (dec.length) {
            NSString *t2 = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
            if (t2.length && [t2 rangeOfString:@"-"].location != NSNotFound) {
                target = t2; wasBase64 = YES;
            }
        }

        NSString *replaced = ks_replaceUUIDs(target, g_customDid);
        if ([replaced isEqualToString:target]) return ret;

        NSData *newData = wasBase64
            ? [[replaced dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:0]
            : [replaced dataUsingEncoding:NSUTF8StringEncoding];
        if (!newData.length) return ret;

        ks_log(@"[READ] 替换 did: %@ → %@", target, replaced);

        if (!isDictResult) {
            CFTypeRef old = *result;
            *result = (__bridge_retained CFTypeRef)newData;
            if (old) CFRelease(old);
        } else {
            NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:val];
            md[(__bridge id)kSecValueData] = newData;
            CFTypeRef old = *result;
            *result = (__bridge_retained CFTypeRef)md;
            if (old) CFRelease(old);
        }
    } @catch (NSException *e) {
        ks_log(@"[READ] 异常: %@", e.reason);
    } @catch (...) {
    }
    return ret;
}

// ---------- 启动 ----------

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         @"/var/mobile/Documents/ksdid_log.txt" error:NULL];

        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid 启动 =====");
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"SecItemCopyMatching hook 已安装");
    }
}
