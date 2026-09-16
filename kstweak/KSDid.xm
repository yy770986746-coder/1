// 诊断版 v3：输出 Keychain 返回值的实际内容（含 hex），定位 did
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = nil;
static int g_callCount = 0;

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
    NSMutableArray *paths = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    if (home.length) {
        [paths addObject:[home stringByAppendingPathComponent:@"Documents/ks_did.txt"]];
    }
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

/// 把 NSData 转成可读描述：尝试 UTF8，失败则 hex（前 80 字节）
static NSString *ks_dataDesc(NSData *d) {
    if (!d.length) return @"(空)";
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (s.length && s.length < 400) {
        // 纯文本
        return [NSString stringWithFormat:@"文本(%lu): %@", (unsigned long)d.length, s];
    }
    // bplist?
    NSRange r = [d rangeOfData:[@"bplist" dataUsingEncoding:NSUTF8StringEncoding]
                       options:0 range:NSMakeRange(0, MIN((NSUInteger)64, d.length))];
    NSString *tag = (r.location != NSNotFound) ? @"bplist" : @"二进制";

    NSMutableString *hex = [NSMutableString string];
    const uint8_t *b = d.bytes;
    NSUInteger n = MIN((NSUInteger)80, d.length);
    for (NSUInteger i = 0; i < n; i++) [hex appendFormat:@"%02x", b[i]];

    // 找明文 UUID（如果有）
    NSString *raw = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    NSString *found = @"";
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    if (raw.length) {
        NSTextCheckingResult *m = [re firstMatchInString:raw options:0
                                                   range:NSMakeRange(0, raw.length)];
        if (m) found = [NSString stringWithFormat:@" UUID=%@", [raw substringWithRange:m.range]];
    }
    return [NSString stringWithFormat:@"%@(%lu)%@ hex=%s",
            tag, (unsigned long)d.length, found, hex.UTF8String];
}

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (!query) return ret;
        g_callCount++;

        NSDictionary *q = (__bridge NSDictionary *)query;
        id svc  = q[(__bridge id)kSecAttrService];
        id acct = q[(__bridge id)kSecAttrAccount];
        NSString *svcS = [svc isKindOfClass:[NSString class]] ? svc : @"";

        // 只关心这些候选键
        BOOL interesting = NO;
        for (NSString *k in @[@"KSCommonIDFA", @"openSDK.deviceId", @"weapon",
                              @"CiInfo", @"did", @"Did", @"DID", @"device",
                              @"EAccount", @"IDFA", @"idfa", @"DFP"]) {
            if (svcS.length && [svcS rangeOfString:k].location != NSNotFound) {
                interesting = YES; break;
            }
        }

        if (interesting) {
            ks_log(@"[C%d] svc=%@ ret=%d", g_callCount, svcS, (int)ret);
            if (result && *result) {
                id v = (__bridge id)*result;
                if ([v isKindOfClass:[NSData class]]) {
                    ks_log(@"     data: %@", ks_dataDesc((NSData *)v));
                } else if ([v isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *dd = (NSDictionary *)v;
                    id data2 = dd[(__bridge id)kSecValueData];
                    if ([data2 isKindOfClass:[NSData class]]) {
                        ks_log(@"     dict.data: %@", ks_dataDesc((NSData *)data2));
                    } else {
                        ks_log(@"     dict keys: %@", [[dd allKeys] componentsJoinedByString:@","]);
                    }
                } else {
                    ks_log(@"     %@: %@", NSStringFromClass([v class]), v);
                }
            }
        }
    } @catch (NSException *e) {
        ks_log(@"[ERR] %@", e.reason);
    } @catch (...) {}
    return ret;
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid 诊断版 v3 =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"hook 已安装");
    }
}
