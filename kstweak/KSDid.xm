// 诊断版 v7：正确读取 CiInfoKey_Re_N（返回的是 NSString 不是 NSData）
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

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

/// 通用 dump：不假设返回类型
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
        if (st != errSecSuccess || !r) {
            ks_log(@"     (读取失败)");
            return;
        }

        // r 可能是 NSData / NSDictionary / NSString
        id obj = (__bridge_transfer id)r;

        if ([obj isKindOfClass:[NSString class]]) {
            ks_log(@"     类型: NSString");
            ks_log(@"     ★ 值: %@", obj);
            return;
        }
        if ([obj isKindOfClass:[NSData class]]) {
            NSData *d = (NSData *)obj;
            ks_log(@"     类型: NSData (%lu 字节)", (unsigned long)d.length);
            NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
            if (t.length) ks_log(@"     ★ 值: %@", t);
            return;
        }
        if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)obj;
            ks_log(@"     类型: NSDictionary, keys=%@",
                   [[d allKeys] componentsJoinedByString:@","]);
            id acct = d[(__bridge id)kSecAttrAccount];
            if ([acct isKindOfClass:[NSString class]]) ks_log(@"     account: %@", acct);
            id vd = d[(__bridge id)kSecValueData];
            if ([vd isKindOfClass:[NSData class]]) {
                NSData *dd = (NSData *)vd;
                ks_log(@"     data: %lu 字节", (unsigned long)dd.length);
                NSString *t = [[NSString alloc] initWithData:dd encoding:NSUTF8StringEncoding];
                if (t.length) ks_log(@"     ★ 文本: %@", t);
                NSMutableString *hex = [NSMutableString string];
                const uint8_t *b = (const uint8_t *)dd.bytes;
                for (NSUInteger i = 0; i < MIN((NSUInteger)300, dd.length); i++)
                    [hex appendFormat:@"%02x", b[i]];
                ks_log(@"     hex: %@", hex);
            } else if ([vd isKindOfClass:[NSString class]]) {
                ks_log(@"     ★ data(字符串): %@", vd);
            }
            return;
        }
        ks_log(@"     未知类型: %@", NSStringFromClass([obj class]));
    } @catch (NSException *e) {
        ks_log(@"  异常: %@", e.reason);
    }
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        ks_log(@"===== KSDid v7 =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_log(@"[IDFV] %@", [[UIDevice currentDevice] identifierForVendor].UUIDString);
            ks_log(@"[IDFA] %@", [[[NSClassFromString(@"ASIdentifierManager")
                                    performSelector:@selector(sharedManager)]
                                   performSelector:@selector(advertisingIdentifier)] UUIDString]);
            ks_dumpKey(@"CiInfoKey_Re_N");
            // 试其他后缀
            ks_dumpKey(@"CiInfoKey_Re_1");
            ks_dumpKey(@"CiInfoKey_Re_2");
            ks_log(@"===== 完成 =====");
        });
    }
}
