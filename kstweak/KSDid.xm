// KSDid v9 —— 正式版：自定义 did（真实生效，非界面伪装）
//
// ★ 已确认 did 的权威存储：
//   Keychain 条目 "CiInfoKey_Re_N"
//     └── NSKeyedArchiver bplist (292字节)
//           └── base64 JSON:
//               {"model_Info":"iPhone13,2","from":0,
//                "cloud_did":"<这里就是 did>","did_tag":"5","action":0}
//
// 原理：hook SecItemCopyMatching，在快手读取该条目时，
//       把 cloud_did 替换成用户指定的值 —— 快手拿到的就是自定义 did，
//       所有网络请求（含服务器校验）都会带上这个值。
//
// 配置：快手沙盒 Documents/ks_did.txt（一行 UUID）
//       或 /var/mobile/Documents/ks_did.txt
//
// 日志：快手沙盒 Documents/ksdid_log.txt

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>

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

/// 把 base64 JSON 里的 cloud_did 换成自定义值，返回新的 base64
static NSString *ks_replaceCloudDid(NSString *b64) {
    if (!b64.length || !g_customDid.length) return nil;

    NSData *raw = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!raw.length) return nil;
    NSString *json = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
    if (!json.length) return nil;

    // 精确替换 cloud_did 的值（保持其他字段不变）
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"(\"cloud_did\"\\s*:\\s*\")([^\"]*)(\")" options:0 error:NULL];
    if (![re numberOfMatchesInString:json options:0 range:NSMakeRange(0, json.length)])
        return nil;

    NSString *newJson = [re stringByReplacingMatchesInString:json options:0
                                                       range:NSMakeRange(0, json.length)
                                                withTemplate:
                       [NSString stringWithFormat:@"$1%@$3", g_customDid]];
    if ([newJson isEqualToString:json]) return nil;   // 值本来就是这个

    NSData *out = [newJson dataUsingEncoding:NSUTF8StringEncoding];
    return [out base64EncodedStringWithOptions:0];
}

// ---------- hook ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        if (ret != errSecSuccess || !query || !result || !*result) return ret;
        if (!g_customDid.length) return ret;

        id obj = (__bridge id)*result;
        if (![obj isKindOfClass:[NSDictionary class]]) return ret;

        NSDictionary *d = (NSDictionary *)obj;
        NSData *data = d[(__bridge id)kSecValueData];
        if (!data.length || data.length > 64 * 1024) return ret;

        // 解析 bplist
        NSError *err = nil;
        id parsed = [NSPropertyListSerialization propertyListWithData:data
                                                             options:NSPropertyListMutableContainers
                                                              format:NULL error:&err];
        if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) return ret;

        NSMutableDictionary *plist = (NSMutableDictionary *)parsed;
        NSMutableArray *objs = plist[@"$objects"];
        if (![objs isKindOfClass:[NSMutableArray class]]) return ret;

        BOOL changed = NO;
        for (NSUInteger i = 0; i < objs.count; i++) {
            id o = objs[i];
            if (![o isKindOfClass:[NSString class]]) continue;
            NSString *s = (NSString *)o;
            if (s.length < 20) continue;
            // 只处理 base64(JSON 含 cloud_did) 的那一项
            if (![s rangeOfString:@"cloud_did"].length) {
                // 可能是 base64，先解码看看
                NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
                if (!dec.length) continue;
                NSString *t = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
                if (!t.length || [t rangeOfString:@"cloud_did"].location == NSNotFound) continue;

                NSString *nb = ks_replaceCloudDid(s);
                if (nb.length) {
                    objs[i] = nb;
                    changed = YES;
                    ks_log(@"[SET] base64 项已改: %@ → %@", t, nb);
                }
                continue;
            }
            // 已是明文 JSON
            NSString *nb = nil;
            NSData *raw = [s dataUsingEncoding:NSUTF8StringEncoding];
            NSString *nb64 = ks_replaceCloudDid([raw base64EncodedStringWithOptions:0]);
            if (nb64.length) { nb = nb64; }
            if (nb.length) { objs[i] = nb; changed = YES; }
        }
        if (!changed) return ret;

        NSData *newData = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                     format:NSPropertyListBinaryFormat_v1_0
                                                                    options:0 error:NULL];
        if (!newData.length) return ret;

        NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:d];
        md[(__bridge id)kSecValueData] = newData;

        CFTypeRef old = *result;
        *result = (__bridge_retained CFTypeRef)md;
        if (old) CFRelease(old);
        ks_log(@"[OK] 已替换 cloud_did → %@", g_customDid);
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
        ks_log(@"===== KSDid v9 (正式版) =====");
        ks_log(@"沙盒: %@", NSHomeDirectory());
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置，插件不生效)");

        if (g_customDid.length) {
            MSHookFunction((void *)SecItemCopyMatching,
                           (void *)my_SecItemCopyMatching,
                           (void **)&orig_SecItemCopyMatching);
            ks_log(@"hook 已安装");
        }
    }
}
