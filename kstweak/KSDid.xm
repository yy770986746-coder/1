// 诊断版 v5：读出 IDFV / IDFA，验证 did 与它们的关系
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

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

// ---------- 读 IDFV / IDFA ----------

static void ks_dumpIdentifiers(void) {
    // IDFV
    @try {
        if ([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)]) {
            NSUUID *idfv = [[UIDevice currentDevice] identifierForVendor];
            ks_log(@"[IDFV] %@", idfv.UUIDString ?: @"(nil)");
        }
    } @catch (NSException *e) { ks_log(@"[IDFV] 异常: %@", e.reason); }

    // IDFA
    @try {
        Class ASIdentifierManager = NSClassFromString(@"ASIdentifierManager");
        if (ASIdentifierManager) {
            id mgr = [ASIdentifierManager performSelector:@selector(sharedManager)];
            if (mgr) {
                if ([mgr respondsToSelector:@selector(advertisingIdentifier)]) {
                    NSUUID *idfa = [mgr performSelector:@selector(advertisingIdentifier)];
                    ks_log(@"[IDFA] %@", idfa.UUIDString ?: @"(nil)");
                }
                SEL sel = NSSelectorFromString(@"isAdvertisingTrackingEnabled");
                if ([mgr respondsToSelector:sel]) {
                    BOOL b = ((BOOL(*)(id, SEL))objc_msgSend)(mgr, sel);
                    ks_log(@"[IDFA] trackingEnabled=%d", (int)b);
                }
            }
        } else {
            ks_log(@"[IDFA] ASIdentifierManager 不存在");
        }
    } @catch (NSException *e) { ks_log(@"[IDFA] 异常: %@", e.reason); }

    // 其他系统标识
    @try {
        NSDictionary *d = [[NSBundle mainBundle] infoDictionary];
        ks_log(@"[Bundle] %@", d[@"CFBundleIdentifier"] ?: @"?");
    } @catch (NSException *e) {}

    // Keychain 里所有 CiInfo / did 相关（用明文 key 试）
    NSArray *keys = @[@"CiInfoKey_Re_N", @"CiInfoKey_Re", @"cloud_did",
                      @"did", @"kuaishou_did", @"KSDidKeychainKey"];
    for (NSString *k in keys) {
        @try {
            NSDictionary *q = @{
                (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                (__bridge id)kSecAttrService: k,
                (__bridge id)kSecReturnData: @YES,
                (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
            };
            CFTypeRef r = NULL;
            OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
            if (st == errSecSuccess && r) {
                NSData *dd = (__bridge_transfer NSData *)r;
                NSString *s = [[NSString alloc] initWithData:dd encoding:NSUTF8StringEncoding];
                ks_log(@"[KC %@] %@", k, s.length ? s : [NSString stringWithFormat:@"%lu 字节", (unsigned long)dd.length]);
            }
        } @catch (NSException *e) {}
    }
}

// ---------- hook: 拦截 did 相关查询 ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static int g_n = 0;

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);
    // v5 只做观察，不修改
    return ret;
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        ks_log(@"===== KSDid v5 (读系统标识) =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());

        // 延迟执行，等 App 完全启动
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_dumpIdentifiers();
            ks_log(@"===== 标识读取完成 =====");
        });
    }
}
