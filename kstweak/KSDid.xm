// 诊断版 v6：dump CiInfoKey_Re_N 的完整内容（did 的 Keychain 项）
// v5 已确认：CiInfoKey_Re_N 存在（292 字节），IDFV=2D012E52-...，IDFA=49847123-...
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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

static NSString *ks_hex(NSData *d, NSUInteger max) {
    if (!d.length) return @"";
    NSMutableString *s = [NSMutableString string];
    const uint8_t *b = (const uint8_t *)d.bytes;
    NSUInteger n = MIN(max, d.length);
    for (NSUInteger i = 0; i < n; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

static void ks_dumpKey(NSString *key) {
    @try {
        NSDictionary *q = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: key,
            (__bridge id)kSecReturnData: @YES,
            (__bridge id)kSecReturnAttributes: @YES,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
        };
        CFTypeRef r = NULL;
        OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
        ks_log(@"---- %@ (status=%d) ----", key, (int)st);
        if (st != errSecSuccess || !r) { ks_log(@"     (读取失败)"); return; }

        NSDictionary *d = (__bridge_transfer NSDictionary *)r;
        NSData *data = d[(__bridge id)kSecValueData];
        NSData *acct = d[(__bridge id)kSecAttrAccount];
        NSString *acctS = [[NSString alloc] initWithData:acct encoding:NSUTF8StringEncoding];

        ks_log(@"     account: %@", acctS ?: @"(非文本)");
        ks_log(@"     长度: %lu 字节", (unsigned long)data.length);

        NSString *txt = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (txt.length) ks_log(@"     文本: %@", txt);

        NSRange br = [data rangeOfData:[@"bplist" dataUsingEncoding:NSUTF8StringEncoding]
                               options:0 range:NSMakeRange(0, MIN((NSUInteger)32, data.length))];
        ks_log(@"     格式: %@", br.location != NSNotFound ? @"bplist" : @"二进制");

        NSString *raw = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSRegularExpression *re =
            [NSRegularExpression regularExpressionWithPattern:
             @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
              "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
        for (NSTextCheckingResult *m in [re matchesInString:raw options:0
                                                      range:NSMakeRange(0, raw.length)]) {
            ks_log(@"     ★ UUID: %@", [raw substringWithRange:m.range]);
        }

        ks_log(@"     hex: %@", ks_hex(data, 400));
    } @catch (NSException *e) {
        ks_log(@"  异常: %@", e.reason);
    }
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        ks_log(@"===== KSDid v6 (dump CiInfoKey) =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_log(@"[IDFV] %@", [[UIDevice currentDevice] identifierForVendor].UUIDString);
            ks_dumpKey(@"CiInfoKey_Re_N");
            ks_dumpKey(@"CiInfoKey_Re");
            ks_log(@"===== 完成 =====");
        });
    }
}
