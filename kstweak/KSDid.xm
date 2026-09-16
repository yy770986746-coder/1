// ==================================================================
//  KSDid —— 快手自定义 did（注入插件）
//
//  ★ 重要：插件注入到【快手的沙盒】里运行，
//    写 /var/mobile/Documents 会被沙盒拒绝（日志一直是空的）。
//    必须写到【快手自己的沙盒目录】：
//      /var/mobile/Containers/Data/Application/<UUID>/Documents/ksdid_log.txt
//    代码里用 NSHomeDirectory() 动态获取。
// ==================================================================

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;

/// 日志路径：优先快手沙盒，回退几个常见位置
static NSString *ks_logPath(void) {
    if (g_logPath) return g_logPath;
    NSMutableArray *cands = [NSMutableArray array];

    // 1) 当前进程的沙盒（注入到快手后就是快手的沙盒）
    NSString *home = NSHomeDirectory();
    if (home.length) {
        [cands addObject:[home stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]];
        [cands addObject:[home stringByAppendingPathComponent:@"Library/ksdid_log.txt"]];
        [cands addObject:[home stringByAppendingPathComponent:@"tmp/ksdid_log.txt"]];
    }
    // 2) 绝对路径兜底
    [cands addObject:@"/var/mobile/Documents/ksdid_log.txt"];
    [cands addObject:@"/tmp/ksdid_log.txt"];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in cands) {
        NSString *dir = [p stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) continue;
        // 试写
        if ([@"init" writeToFile:p atomically:YES
                        encoding:NSUTF8StringEncoding error:NULL]) {
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
    NSString *path = ks_logPath();
    @try {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        } else {
            [line writeToFile:path atomically:YES
                     encoding:NSUTF8StringEncoding error:NULL];
        }
    } @catch (NSException *e) {}
}

// ---------- 配置：也要从沙盒里读 ----------

static NSString *ks_loadCustomDid(void) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    if (home.length) {
        [paths addObject:[home stringByAppendingPathComponent:@"Documents/ks_did.txt"]];
        [paths addObject:[home stringByAppendingPathComponent:
                          @"Library/Preferences/com.kuaishou.ksdid.plist"]];
    }
    [paths addObject:@"/var/mobile/Documents/ks_did.txt"];
    [paths addObject:@"/var/mobile/Library/Preferences/com.kuaishou.ksdid.plist"];

    for (NSString *p in paths) {
        if ([p hasSuffix:@".plist"]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
            id v = d[@"did"];
            if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length == 36)
                return v;
        } else {
            NSString *t = [NSString stringWithContentsOfFile:p
                                                    encoding:NSUTF8StringEncoding error:NULL];
            t = [t stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (t.length == 36) return t;
        }
    }
    return nil;
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

// ---------- hook ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (ret != errSecSuccess || !result || !*result || !query) return ret;

        NSDictionary *q = (__bridge NSDictionary *)query;
        BOOL isDid = ks_isDidKey(q);
        if (isDid) {
            ks_log(@"[HIT] 查 did 条目 → %@", [q description]);
        }
        if (!isDid || !g_customDid.length) return ret;

        id val = (__bridge id)*result;
        NSData *data = nil;
        BOOL isDictResult = NO;
        if ([val isKindOfClass:[NSData class]]) {
            data = (NSData *)val;
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            isDictResult = YES;
            id d2 = ((NSDictionary *)val)[(__bridge id)kSecValueData];
            if ([d2 isKindOfClass:[NSData class]]) data = d2;
        }
        if (!data.length || data.length > 1024 * 256) return ret;

        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s.length) return ret;
        ks_log(@"[VAL] 原值: %.200@", s);

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
        if ([replaced isEqualToString:target]) {
            ks_log(@"[SKIP] 没有 UUID 可替换");
            return ret;
        }

        NSData *newData = wasBase64
            ? [[replaced dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:0]
            : [replaced dataUsingEncoding:NSUTF8StringEncoding];
        if (!newData.length) return ret;

        ks_log(@"[SET] %@ → %@", target, replaced);

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
        ks_log(@"[ERR] %@", e.reason);
    } @catch (...) {
    }
    return ret;
}

%ctor {
    @autoreleasepool {
        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid 启动 =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"hook 已安装");
    }
}
