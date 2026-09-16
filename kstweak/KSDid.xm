// 扩展版：记录所有 SecItemCopyMatching 调用（不只 did），找出快手读 did 的真实方式

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

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
            if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length == 36) return v;
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

// 计数器，避免日志刷爆
static int g_callCount = 0;

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (!query) return ret;
        g_callCount++;

        NSDictionary *q = (__bridge NSDictionary *)query;
        id svc  = q[(__bridge id)kSecAttrService];
        id acct = q[(__bridge id)kSecAttrAccount];

        // 只记录前 100 次 + 含 CiInfo/did 关键字的
        BOOL isDidK = NO;
        for (id o in @[svc ?: [NSNull null], acct ?: [NSNull null]]) {
            if ([o isKindOfClass:[NSString class]]) {
                NSString *s = (NSString *)o;
                if ([s rangeOfString:@"CiInfo"].location != NSNotFound ||
                    [s rangeOfString:@"did"].location != NSNotFound ||
                    [s rangeOfString:@"Did"].location != NSNotFound ||
                    [s rangeOfString:@"DID"].location != NSNotFound ||
                    [s rangeOfString:@"cloud"].location != NSNotFound ||
                    [s rangeOfString:@"EAccount"].location != NSNotFound) {
                    isDidK = YES;
                }
            }
        }

        if (isDidK || g_callCount <= 60) {
            ks_log(@"[C%d] ret=%d svc=%@ acct=%@",
                   g_callCount, (int)ret,
                   [svc isKindOfClass:[NSString class]] ? svc : @"(非字符串)",
                   [acct isKindOfClass:[NSString class]] ? acct : @"(非字符串)");

            if (result && *result) {
                id v = (__bridge id)*result;
                if ([v isKindOfClass:[NSData class]]) {
                    NSData *d = (NSData *)v;
                    NSString *s2 = [[NSString alloc] initWithData:d
                                                         encoding:NSUTF8StringEncoding];
                    if (s2.length && s2.length < 300) ks_log(@"     值: %@", s2);
                    else ks_log(@"     NSData %lu 字节", (unsigned long)d.length);
                } else {
                    ks_log(@"     类型: %@", NSStringFromClass([v class]));
                }
            }
        }

        // 命中 did 就替换
        if (isDidK && g_customDid.length && ret == errSecSuccess && result && *result) {
            id val = (__bridge id)*result;
            NSData *data = nil;
            BOOL isDictResult = NO;
            if ([val isKindOfClass:[NSData class]]) data = (NSData *)val;
            else if ([val isKindOfClass:[NSDictionary class]]) {
                isDictResult = YES;
                id d2 = ((NSDictionary *)val)[(__bridge id)kSecValueData];
                if ([d2 isKindOfClass:[NSData class]]) data = d2;
            }
            if (data.length && data.length < 256 * 1024) {
                NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (s.length) {
                    NSString *target = s;
                    BOOL wasB64 = NO;
                    NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
                    if (dec.length) {
                        NSString *t2 = [[NSString alloc] initWithData:dec
                                                             encoding:NSUTF8StringEncoding];
                        if (t2.length && [t2 rangeOfString:@"-"].location != NSNotFound) {
                            target = t2; wasB64 = YES;
                        }
                    }
                    NSString *rep = ks_replaceUUIDs(target, g_customDid);
                    if (![rep isEqualToString:target]) {
                        NSData *nd = wasB64
                            ? [[rep dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:0]
                            : [rep dataUsingEncoding:NSUTF8StringEncoding];
                        if (nd.length) {
                            ks_log(@"[SET] %@ → %@", target, rep);
                            if (!isDictResult) {
                                CFTypeRef old = *result;
                                *result = (__bridge_retained CFTypeRef)nd;
                                if (old) CFRelease(old);
                            } else {
                                NSMutableDictionary *md =
                                    [NSMutableDictionary dictionaryWithDictionary:val];
                                md[(__bridge id)kSecValueData] = nd;
                                CFTypeRef old = *result;
                                *result = (__bridge_retained CFTypeRef)md;
                                if (old) CFRelease(old);
                            }
                        }
                    } else {
                        ks_log(@"[SKIP] 无 UUID 可替换");
                    }
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
        ks_log(@"===== KSDid 诊断版 v2 =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"hook 已安装");
    }
}
