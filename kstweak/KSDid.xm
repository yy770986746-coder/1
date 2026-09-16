// ==================================================================
//  KSDid —— 快手自定义 did（注入插件）
//
//  原理：
//    快手把 did 加密存在 Keychain 的 "CiInfoKey_Re_N" 条目里，
//    直接改数据库不可行（svce 是 SHA1 哈希、data 是 AES 密文）。
//    本插件注入快手进程后，在 SecItemCopyMatching 返回时
//    【替换掉读到的 did】，让快手用我们指定的 did。
//
//  配置（按优先级）：
//    1) /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist  键 did
//    2) /var/mobile/Documents/ks_did.txt                          一行 UUID
//
//  安全设计：
//    - 只用 MSHookFunction hook SecItemCopyMatching（不 hook SecItemAdd，避免写入路径风险）
//    - 只在"查 did 条目 + 返回类型是 NSData"时才替换，其他一律原样返回
//    - 全程 @try/@catch，异常不影响快手
//    - 替换失败立刻返回原值，绝不返回半成品
// ==================================================================

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_customDid = nil;

// ---------- 配置读取（带缓存，避免每次都读盘） ----------

static NSString *ks_loadCustomDid(void) {
    // 1) 偏好文件
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/com.kuaishou.ksdid.plist"];
    id v = d[@"did"];
    if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length == 36)
        return v;

    // 2) 纯文本
    NSString *t = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/ks_did.txt"
                                            encoding:NSUTF8StringEncoding error:NULL];
    t = [t stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length == 36) return t;

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
    return [re numberOfMatchesInString:s options:0
                                 range:NSMakeRange(0, s.length)] > 0;
}

/// 把文本里所有 UUID 形态的串换成目标 did（等长替换）
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
        NSTextCheckingResult *m = ms[(NSUInteger)i];
        [out replaceCharactersInRange:m.range withString:newDid];
    }
    return out;
}

// ---------- hook ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    // 先调用原函数，拿到快手本该得到的结果
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    // 只在成功、有结果、有自定义 did、有 query/result 时处理
    if (ret != errSecSuccess || !result || !*result) return ret;
    if (!g_customDid.length) return ret;
    if (!query) return ret;

    @try {
        NSDictionary *q = (__bridge NSDictionary *)query;
        id svcObj  = q[(__bridge id)kSecAttrService];
        id acctObj = q[(__bridge id)kSecAttrAccount];
        NSString *name = nil;
        if ([svcObj isKindOfClass:[NSString class]])  name = svcObj;
        else if ([acctObj isKindOfClass:[NSString class]]) name = acctObj;
        if (!name.length) return ret;

        // 只关心 did 的条目
        if ([name rangeOfString:@"CiInfoKey_Re"].location == NSNotFound) return ret;

        // ★ 只处理 NSData 结果（最常见），其他类型一律不动，避免破坏调用方预期
        id val = (__bridge id)*result;
        if (![val isKindOfClass:[NSData class]]) return ret;

        NSData *data = (NSData *)val;
        if (data.length == 0 || data.length > 1024 * 256) return ret;

        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s.length) return ret;

        // 值可能是 base64(JSON)
        NSString *target = s;
        BOOL wasBase64 = NO;
        NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
        if (dec.length) {
            NSString *t2 = [[NSString alloc] initWithData:dec encoding:NSUTF8StringEncoding];
            if (t2.length && [t2 rangeOfString:@"-"].location != NSNotFound) {
                target = t2;
                wasBase64 = YES;
            }
        }

        NSString *replaced = ks_replaceUUIDs(target, g_customDid);
        if ([replaced isEqualToString:target]) return ret;   // 没变，不动

        NSData *newData = nil;
        if (wasBase64) {
            NSData *raw = [replaced dataUsingEncoding:NSUTF8StringEncoding];
            newData = [raw base64EncodedDataWithOptions:0];
        } else {
            newData = [replaced dataUsingEncoding:NSUTF8StringEncoding];
        }
        if (!newData.length) return ret;

        // 替换（原值交给 ARC/CF 管理，不手动 release，避免 double-free）
        CFTypeRef old = *result;
        *result = (__bridge_retained CFTypeRef)newData;
        if (old) CFRelease(old);

    } @catch (NSException *e) {
        // 出任何异常都不影响快手，原样返回
    } @catch (...) {
    }
    return ret;
}

// ---------- 启动 ----------

%ctor {
    @autoreleasepool {
        g_customDid = ks_loadCustomDid();
        if (g_customDid.length) {
            MSHookFunction((void *)SecItemCopyMatching,
                           (void *)my_SecItemCopyMatching,
                           (void **)&orig_SecItemCopyMatching);
        }
    }
}
