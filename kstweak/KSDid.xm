// KSDid v10 —— 全量 hook Keychain API
// v9 发现：快手没调用 SecItemCopyMatching（hook 装了但没触发）
// 本版同时 hook CopyMatching / Add / Update / Delete，找出快手读/写 did 的真实路径

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;
static int g_cm = 0, g_add = 0, g_upd = 0, g_del = 0;

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

static NSString *ks_queryName(CFDictionaryRef q) {
    if (!q) return @"(null)";
    @try {
        NSDictionary *d = (__bridge NSDictionary *)q;
        id s = d[(__bridge id)kSecAttrService];
        id a = d[(__bridge id)kSecAttrAccount];
        NSMutableString *m = [NSMutableString string];
        if ([s isKindOfClass:[NSString class]]) [m appendFormat:@"svc=%@", s];
        if ([a isKindOfClass:[NSString class]]) [m appendFormat:@" acct=%@", a];
        return m.length ? m : @"(无名称)";
    } @catch (NSException *e) { return @"(异常)"; }
}

static NSString *ks_replaceCloudDid(NSString *b64) {
    if (!b64.length || !g_customDid.length) return nil;
    NSData *raw = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!raw.length) return nil;
    NSString *json = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
    if (!json.length || [json rangeOfString:@"cloud_did"].location == NSNotFound) return nil;

    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"(\"cloud_did\"\\s*:\\s*\")([^\"]*)(\")" options:0 error:NULL];
    if (![re numberOfMatchesInString:json options:0 range:NSMakeRange(0, json.length)])
        return nil;

    NSString *newJson = [re stringByReplacingMatchesInString:json options:0
                                                       range:NSMakeRange(0, json.length)
                                                withTemplate:
                       [NSString stringWithFormat:@"$1%@$3", g_customDid]];
    if ([newJson isEqualToString:json]) return nil;
    return [[newJson dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

/// 处理可能含 did 的 bplist，返回新 NSData（nil 表示无需改）
static NSData *ks_patchPlistData(NSData *data, NSString **logOut) {
    if (!data.length || data.length > 64 * 1024) return nil;
    NSError *err = nil;
    id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                         options:NSPropertyListMutableContainers
                                                          format:NULL error:&err];
    if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableDictionary *plist = (NSMutableDictionary *)parsed;
    NSMutableArray *objs = plist[@"$objects"];
    if (![objs isKindOfClass:[NSMutableArray class]]) return nil;

    BOOL changed = NO;
    for (NSUInteger i = 0; i < objs.count; i++) {
        id o = objs[i];
        if (![o isKindOfClass:[NSString class]]) continue;
        NSString *s = (NSString *)o;
        if (s.length < 20) continue;

        NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
        if (!dec.length) continue;
        NSString *t = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
        if (!t.length || [t rangeOfString:@"cloud_did"].location == NSNotFound) continue;

        NSString *nb = ks_replaceCloudDid(s);
        if (nb.length) {
            objs[i] = nb;
            changed = YES;
            if (logOut) *logOut = t;
        }
    }
    if (!changed) return nil;

    return [NSPropertyListSerialization dataWithPropertyList:plist
                                                      format:NSPropertyListBinaryFormat_v1_0
                                                     options:0 error:NULL];
}

// ==================== hooks ====================

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);
    @try {
        g_cm++;
        if (ret != errSecSuccess || !result || !*result) return ret;
        NSString *nm = ks_queryName(query);
        id obj = (__bridge id)*result;

        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)obj;
            NSData *data = d[(__bridge id)kSecValueData];
            NSString *hit = nil;
            NSData *newData = ks_patchPlistData(data, &hit);
            if (newData) {
                NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:d];
                md[(__bridge id)kSecValueData] = newData;
                CFTypeRef old = *result;
                *result = (__bridge_retained CFTypeRef)md;
                if (old) CFRelease(old);
                ks_log(@"[COPY-OK] %@ | %@ → did=%@", nm, hit, g_customDid);
            }
        }
        // 记录 did 相关查询（便于诊断）
        if ([nm rangeOfString:@"CiInfo"].location != NSNotFound) {
            ks_log(@"[COPY-%d] %@", (int)ret, nm);
        }
    } @catch (NSException *e) { ks_log(@"[COPY-ERR] %@", e.reason); }
    return ret;
}

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    @try {
        g_add++;
        if (attrs) {
            NSDictionary *d = (__bridge NSDictionary *)attrs;
            NSData *data = d[(__bridge id)kSecValueData];
            if (data.length) {
                NSString *hit = nil;
                NSData *nd = ks_patchPlistData(data, &hit);
                if (nd) {
                    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:d];
                    md[(__bridge id)kSecValueData] = nd;
                    ks_log(@"[ADD-OK] %@ | %@ → did=%@", ks_queryName(attrs), hit, g_customDid);
                    return orig_SecItemAdd((__bridge CFDictionaryRef)md, result);
                }
            }
        }
    } @catch (NSException *e) { ks_log(@"[ADD-ERR] %@", e.reason); }
    return orig_SecItemAdd(attrs, result);
}

static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);

static OSStatus my_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    @try {
        g_upd++;
        if (attrs) {
            NSDictionary *d = (__bridge NSDictionary *)attrs;
            NSData *data = d[(__bridge id)kSecValueData];
            if (data.length) {
                NSString *hit = nil;
                NSData *nd = ks_patchPlistData(data, &hit);
                if (nd) {
                    NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:d];
                    md[(__bridge id)kSecValueData] = nd;
                    ks_log(@"[UPDATE-OK] %@ | %@ → did=%@", ks_queryName(query), hit, g_customDid);
                    return orig_SecItemUpdate(query, (__bridge CFDictionaryRef)md);
                }
            }
        }
    } @catch (NSException *e) { ks_log(@"[UPDATE-ERR] %@", e.reason); }
    return orig_SecItemUpdate(query, attrs);
}

static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);

static OSStatus my_SecItemDelete(CFDictionaryRef query) {
    @try { g_del++; } @catch (...) {}
    return orig_SecItemDelete(query);
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid v10 (全量 Keychain hook) =====");
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching, (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        MSHookFunction((void *)SecItemAdd, (void *)my_SecItemAdd, (void **)&orig_SecItemAdd);
        MSHookFunction((void *)SecItemUpdate, (void *)my_SecItemUpdate, (void **)&orig_SecItemUpdate);
        MSHookFunction((void *)SecItemDelete, (void *)my_SecItemDelete, (void **)&orig_SecItemDelete);
        ks_log(@"4 个 hook 已安装");
    }
}
