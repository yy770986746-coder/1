// 诊断版：把 hook 的每次调用都写到文件，便于 SSH 查看
// 只做记录，不改变行为（先确认命中再改）

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *g_customDid = nil;
static NSString *g_logPath = @"/var/mobile/Documents/ksdid_log.txt";

static void ks_log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"%@\n", msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:g_logPath];
    if (fh) {
        @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
        @catch (NSException *e) {}
        @finally { [fh closeFile]; }
    } else {
        [line writeToFile:g_logPath atomically:YES
                 encoding:NSUTF8StringEncoding error:NULL];
    }
}

static NSString *ks_loadCustomDid(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:
                       @"/var/mobile/Library/Preferences/com.kuaishou.ksdid.plist"];
    id v = d[@"did"];
    if ([v isKindOfClass:[NSString class]] && ((NSString *)v).length == 36) return v;
    NSString *t = [NSString stringWithContentsOfFile:@"/var/mobile/Documents/ks_did.txt"
                                            encoding:NSUTF8StringEncoding error:NULL];
    t = [t stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length == 36 ? t : nil;
}

static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);

static OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus ret = orig_SecItemCopyMatching(query, result);

    @try {
        // 记录所有包含 CiInfoKey 的查询
        if (query) {
            NSDictionary *q = (__bridge NSDictionary *)query;
            id svcObj = q[(__bridge id)kSecAttrService];
            id acctObj = q[(__bridge id)kSecAttrAccount];
            NSString *svc = [svcObj isKindOfClass:[NSString class]] ? svcObj : @"(非字符串)";
            NSString *acct = [acctObj isKindOfClass:[NSString class]] ? acctObj : @"(非字符串)";

            BOOL interesting = NO;
            if ([svc isKindOfClass:[NSString class]] &&
                [svc rangeOfString:@"CiInfo"].location != NSNotFound) interesting = YES;
            if ([acct isKindOfClass:[NSString class]] &&
                [acct rangeOfString:@"CiInfo"].location != NSNotFound) interesting = YES;

            if (interesting || ret == errSecSuccess) {
                NSString *valDesc = @"(nil)";
                if (result && *result) {
                    id v = (__bridge id)*result;
                    Class cls = [v class];
                    if ([v isKindOfClass:[NSData class]]) {
                        valDesc = [NSString stringWithFormat:@"NSData(%lu字节)", (unsigned long)[(NSData *)v length]];
                    } else {
                        valDesc = NSStringFromClass(cls);
                    }
                }
                ks_log(@"[CALL] ret=%d svc=%@ acct=%@ result=%@",
                       (int)ret, svc, acct, valDesc);
            }
        }
    } @catch (NSException *e) {
        ks_log(@"[CALL] 异常: %@", e.reason);
    }
    return ret;
}

%ctor {
    @autoreleasepool {
        // 清空旧日志
        [[NSFileManager defaultManager] removeItemAtPath:g_logPath error:NULL];
        g_customDid = ks_loadCustomDid();
        ks_log(@"===== KSDid 诊断版启动 =====");
        ks_log(@"自定义 did = %@", g_customDid ?: @"(未配置)");

        MSHookFunction((void *)SecItemCopyMatching,
                       (void *)my_SecItemCopyMatching,
                       (void **)&orig_SecItemCopyMatching);
        ks_log(@"SecItemCopyMatching hook 已安装");
    }
}
