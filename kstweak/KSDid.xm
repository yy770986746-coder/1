// ==================================================================
//  KSDidTweak —— 快手自定义 did（注入插件）
//
//  原理：
//    快手把 did 加密存在 Keychain 的 "CiInfoKey_Re_N" 条目里，
//    直接改数据库不可行（svce 是 SHA1 哈希、data 是 AES 密文）。
//    本插件注入快手进程后，在 SecItemCopyMatching 返回时
//    【替换掉读到的 did】，从而让快手用我们指定的 did。
//
//  配置来源（按优先级）：
//    1) /var/mobile/Library/Preferences/com.kuaishou.ksdid.plist
//       键 did = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
//    2) /var/mobile/Documents/ks_did.txt（纯文本一行）
//    3) AppGroup group.com.kwai.video 的 KSAppCommonParamsKey.did
//
//  只影响 did，不动 token / salt / egid 等其他参数。
// ==================================================================

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

// ---------- 配置读取 ----------

static NSString *g_customDid = nil;

static NSString *ks_loadCustomDid(void) {
    // 1) 偏好文件
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/com.kuaishou.ksdid.plist"];
    NSString *v = d[@"did"];
    if ([v isKindOfClass:[NSString class]] && v.length == 36) return v;

    // 2) 纯文本文件
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

/// 把文本里所有 UUID 形态的串换成目标 did（等长替换，安全）
static NSString *ks_replaceUUIDs(NSString *src, NSString *newDid) {
    if (!src.length || !ks_isUUID(newDid)) return src;
    NSRegularExpression *re =
        [NSRegularExpression regularExpressionWithPattern:
         @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
          "[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" options:0 error:NULL];
    NSArray *ms = [re matchesInString:src options:0 range:NSMakeRange(0, src.length)];
    if (!ms.count) return src;

    NSMutableString *out = [NSMutableString stringWithString:src];
    // 从后往前替换，避免偏移失效
    for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = ms[(NSUInteger)i];
        [out replaceCharactersInRange:m.range withString:newDid];
    }
    return out;
}

// ---------- 1) 读 Keychain 时替换 did ----------

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);
    if (!g_customDid.length || ret != errSecSuccess || !result || !*result) return ret;

    @try {
        NSDictionary *q = (__bridge NSDictionary *)query;
        NSString *acct = q[(__bridge id)kSecAttrAccount];
        NSString *svc  = q[(__bridge id)kSecAttrService];
        NSString *name = acct ?: svc ?: @"";
        if (![name containsString:@"CiInfoKey_Re"]) return ret;

        id val = (__bridge id)*result;
        NSData *data = nil;

        if ([val isKindOfClass:[NSData class]]) {
            data = (NSData *)val;
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            id d2 = ((NSDictionary *)val)[(__bridge id)kSecValueData];
            if ([d2 isKindOfClass:[NSData class]]) data = d2;
        }
        if (!data.length) return ret;

        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s.length) return ret;

        // 值可能是 base64(JSON)，两种都处理
        NSString *target = s;
        BOOL wasBase64 = NO;
        NSData *dec = [[NSData alloc] initWithBase64EncodedString:s options:0];
        if (dec) {
            NSString *t2 = [[NSString alloc] initWithData:dec
                                                 encoding:NSUTF8StringEncoding];
            if (t2.length && [t2 containsString:@"-"]) {
                target = t2;
                wasBase64 = YES;
            }
        }

        NSString *replaced = ks_replaceUUIDs(target, g_customDid);
        if ([replaced isEqualToString:target]) return ret;   // 没有 UUID，不动

        NSData *newData = nil;
        if (wasBase64) {
            newData = [[replaced dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:0];
        } else {
            newData = [replaced dataUsingEncoding:NSUTF8StringEncoding];
        }
        if (!newData.length) return ret;

        CFTypeRef replacement = (__bridge_retained CFTypeRef)newData;
        if (val && CFGetTypeID((__bridge CFTypeRef)val) == CFDataGetTypeID()) {
            // 直接返回 NSData
            *result = replacement;
        } else if ([val isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *md = [NSMutableDictionary dictionaryWithDictionary:val];
            md[(__bridge id)kSecValueData] = newData;
            CFRelease(replacement);
            *result = (__bridge_retained CFTypeRef)md;
        }
    } @catch (NSException *e) {}
    return ret;
}

// ---------- 2) 启动时安装 ----------

static void ks_install(void) {
    g_customDid = ks_loadCustomDid();
    if (!g_customDid.length) {
        NSLog(@"[KSDid] 未配置 did，插件不生效");
        return;
    }
    NSLog(@"[KSDid] 已启用，自定义 did = %@", g_customDid);

    MSHookFunction((void *)SecItemCopyMatching,
                   (void *)my_SecItemCopyMatching,
                   (void **)&orig_SecItemCopyMatching);
}

%ctor {
    @autoreleasepool {
        ks_install();
    }
}
