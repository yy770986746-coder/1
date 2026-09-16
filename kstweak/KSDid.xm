// 诊断版 v4：全量扫描所有 Keychain 项，找出含 did 的那个
// 已知：KSCommonIDFAKeychainKey → 49847123-... / com.kwai.openSDK.deviceId → CD9BD127-...
//       这两个都不是界面显示的 did（7F00CDE1），需继续找
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_logPath = nil;
static int g_callCount = 0;
static NSString *g_targetDID = @"7F00CDE1";

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

static NSString *ks_fullHex(NSData *d) {
    if (!d.length) return @"";
    NSMutableString *hex = [NSMutableString string];
    const uint8_t *b = (const uint8_t *)d.bytes;
    NSUInteger n = MIN((NSUInteger)400, d.length);
    for (NSUInteger i = 0; i < n; i++) [hex appendFormat:@"%02x", b[i]];
    if (d.length > n) [hex appendFormat:@"...(%lu字节)", (unsigned long)d.length];
    return hex;
}

/// 找所有 UUID（标准格式 + 32位hex变体）
static NSString *ks_findUUIDs(NSData *d) {
    NSString *raw = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
    if (!raw.length) return @"";
    NSMutableArray *found = [NSMutableArray array];

    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    for (NSTextCheckingResult *m in [re matchesInString:raw options:0
                                                  range:NSMakeRange(0, raw.length)]) {
        [found addObject:[raw substringWithRange:m.range]];
    }

    NSRegularExpression *re2 =
        [NSRegularExpression regularExpressionWithPattern:@"[0-9A-Fa-f]{32}"
                                                  options:0 error:NULL];
    for (NSTextCheckingResult *m in [re2 matchesInString:raw options:0
                                                   range:NSMakeRange(0, raw.length)]) {
        NSString *h = [[raw substringWithRange:m.range] uppercaseString];
        if ([h rangeOfString:g_targetDID].location != NSNotFound) {
            [found addObject:[NSString stringWithFormat:@"HEX32:%@", h]];
        }
    }
    return found.count ? [found componentsJoinedByString:@" | "] : @"";
}

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (!query || ret != errSecSuccess || !result || !*result) return ret;
        g_callCount++;

        NSDictionary *q = (__bridge NSDictionary *)query;
        id svc  = q[(__bridge id)kSecAttrService];
        NSString *svcS = [svc isKindOfClass:[NSString class]] ? svc : @"(无)";

        id v = (__bridge id)*result;
        NSData *data = nil;
        if ([v isKindOfClass:[NSData class]]) {
            data = (NSData *)v;
        } else if ([v isKindOfClass:[NSDictionary class]]) {
            id d2 = ((NSDictionary *)v)[(__bridge id)kSecValueData];
            if ([d2 isKindOfClass:[NSData class]]) data = d2;
        }
        if (!data.length) return ret;

        NSString *uuids = ks_findUUIDs(data);
        if (uuids.length) {
            ks_log(@"[C%d] %@ (%lu字节)", g_callCount, svcS, (unsigned long)data.length);
            ks_log(@"     UUID: %@", uuids);
            ks_log(@"     hex: %@", ks_fullHex(data));
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
        ks_log(@"===== KSDid v4 (全量UUID扫描) =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"目标 did 前缀: %@", g_targetDID);

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"hook 已安装");
    }
}
