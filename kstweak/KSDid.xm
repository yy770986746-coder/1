// KSDid v18 —— 终极定位：枚举全部 Keychain 条目，找出谁装着 A1B2C3D4
// v17 证据：40 个网络请求全部 did=A1B2C3D4，但我改了所有文件后它立刻又变回来
//   → did 必在 Keychain 某个我还没找到的条目里
// 本版：遍历全部条目 + 读每个条目的 data + 搜 A1B2C3D4

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

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

static NSString *ks_desc(id o) {
    if (!o) return @"(nil)";
    if ([o isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)o;
        if (s.length > 80) return [s substringToIndex:80];
        return s;
    }
    if ([o isKindOfClass:[NSData class]]) {
        NSData *d = (NSData *)o;
        return [NSString stringWithFormat:@"<NSData %luB>", (unsigned long)d.length];
    }
    return [o description];
}

// ★ 检查一条 data 里有没有目标 UUID
static NSString *ks_findUUIDs(NSData *data, NSString *needle) {
    if (!data.length) return nil;
    NSString *s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!s.length) return nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:
        @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        options:0 error:NULL];
    NSArray *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    NSMutableSet *found = [NSMutableSet set];
    for (NSTextCheckingResult *m in ms) [found addObject:[s substringWithRange:m.range]];
    if (!found.count) return nil;
    NSMutableString *out = [NSMutableString string];
    for (NSString *u in found) {
        if (needle && [u caseInsensitiveCompare:needle] == NSOrderedSame)
            [out appendFormat:@" ★★%@", u];
        else
            [out appendFormat:@" %@", u];
    }
    return out;
}

static void ks_scanAll(void) {
    NSString *target = @"A1B2C3D4-E5F6-7890-ABCD-EF1234567890";

    ks_log(@"");
    ks_log(@"===== ★★★ 全量 Keychain 扫描（找 A1B2C3D4）=====");

    NSDictionary *q = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll
    };
    CFTypeRef r = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &r);
    if (st != errSecSuccess || !r) {
        ks_log(@"[扫描] 失败 status=%d", (int)st);
        return;
    }
    NSArray *items = (__bridge_transfer NSArray *)r;
    ks_log(@"[扫描] 共 %lu 条", (unsigned long)items.count);

    int hitCount = 0;
    for (NSDictionary *it in items) {
        @try {
            NSString *svc = ks_desc(it[(__bridge id)kSecAttrService]);
            NSString *acct = ks_desc(it[(__bridge id)kSecAttrAccount]);
            NSString *agrp = ks_desc(it[(__bridge id)kSecAttrAccessGroup]);
            NSData *dat = it[(__bridge id)kSecValueData];
            if (![dat isKindOfClass:[NSData class]]) dat = nil;

            NSString *uuids = ks_findUUIDs(dat, target);

            // ★ 命中 A1B2C3D4 的，重点标出
            if (uuids && [uuids rangeOfString:@"★★A1B2C3D4"].location != NSNotFound) {
                hitCount++;
                ks_log(@"[★★命中] svce=%@", svc);
                ks_log(@"          acct=%@", acct);
                ks_log(@"          agrp=%@", agrp);
                ks_log(@"          data=%luB  uuids:%@", (unsigned long)dat.length, uuids);
                // 打印 data 的可读内容
                NSString *s = [[NSString alloc] initWithData:dat
                                                    encoding:NSUTF8StringEncoding];
                if (s.length && s.length < 600)
                    ks_log(@"          内容: %@", s);
                else {
                    NSString *b64 = [dat base64EncodedStringWithOptions:0];
                    if (b64.length < 600) ks_log(@"          b64: %@", b64);
                }
                ks_log(@"");
            } else if (uuids) {
                // 含其他 UUID 的也记一下
                ks_log(@"[UUID] svce=%@ agrp=%@%s", svc, agrp, "");
                ks_log(@"       %@", uuids);
            }
        } @catch (NSException *e) {}
    }
    ks_log(@"===== 扫描结束：命中 A1B2C3D4 的条目 = %d =====", hitCount);
    ks_log(@"");
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v18 - 全量扫描 ##########");
                ks_scanAll();
            } @catch (NSException *e) {
                ks_log(@"!!! 异常: %@", e.reason);
            }
        });
    }
}
