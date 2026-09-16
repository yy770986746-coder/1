// 诊断版 v8：解析 CiInfoKey_Re_N 的 bplist，输出完整明文内容
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

/// 递归 dump 对象
static void ks_walk(id o, int depth) {
    NSString *pad = [@"" stringByPaddingToLength:(NSUInteger)(depth * 2)
                                      withString:@" " startingAtIndex:0];
    if ([o isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)o;
        for (id k in d) {
            ks_log(@"%@  %@:", pad, k);
            ks_walk(d[k], depth + 1);
        }
    } else if ([o isKindOfClass:[NSArray class]]) {
        NSArray *a = (NSArray *)o;
        for (NSUInteger i = 0; i < a.count; i++) {
            ks_log(@"%@  [%lu]", pad, (unsigned long)i);
            ks_walk(a[i], depth + 1);
        }
    } else if ([o isKindOfClass:[NSData class]]) {
        NSData *d = (NSData *)o;
        ks_log(@"%@  NSData %lu 字节", pad, (unsigned long)d.length);
        NSString *t = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
        if (t.length) ks_log(@"%@  ★ 文本: %@", pad, t);
    } else {
        NSString *s = [o description];
        ks_log(@"%@  %@ (%@)", pad, s, NSStringFromClass([o class]));
        // base64 解码尝试
        if ([o isKindOfClass:[NSString class]] && s.length > 20) {
            NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
            if (dec.length) {
                NSString *t2 = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
                if (t2.length) ks_log(@"%@  ★ base64解码: %@", pad, t2);
            }
        }
    }
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
        ks_log(@"====== %@ (status=%d) ======", key, (int)st);
        if (st != errSecSuccess || !r) { ks_log(@"  (失败)"); return; }

        id obj = (__bridge_transfer id)r;
        if (![obj isKindOfClass:[NSDictionary class]]) {
            ks_walk(obj, 1);
            return;
        }
        NSDictionary *d = (NSDictionary *)obj;
        NSData *data = d[(__bridge id)kSecValueData];

        ks_log(@"  data 长度: %lu", (unsigned long)data.length);

        // 试 bplist 解析
        NSError *err = nil;
        id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                             options:0
                                                              format:NULL
                                                               error:&err];
        if (parsed) {
            ks_log(@"  ★ bplist 解析成功:");
            ks_walk(parsed, 2);
        } else {
            ks_log(@"  bplist 解析失败: %@", err.localizedDescription);
            ks_walk(data, 2);
        }
    } @catch (NSException *e) {
        ks_log(@"  异常: %@", e.reason);
    }
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] removeItemAtPath:
         [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/ksdid_log.txt"]
                                                 error:NULL];
        ks_log(@"===== KSDid v8 (解析 CiInfoKey 明文) =====");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            ks_dumpKey(@"CiInfoKey_Re_N");
            ks_log(@"===== 完成 =====");
        });
    }
}
