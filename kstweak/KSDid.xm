// KSDid v21 —— 最终版：自动检测 + 双向替换 + 一键改
//
// 重大突破（v19/v20 实证）：
//   iOS 快手的 did 是服务端下发的，本地 Keychain/MMKV/AppGroup 改了也没用。
//   必须在网络层双向替换：
//     请求方向：NSURLRequest.URL / NSMutableURLRequest.setHTTPBody
//     响应方向：NSJSONSerialization / NSPropertyListSerialization
//
// v21 改进：
//   1. 自动学习旧 did（从响应里抓，不用写死 A1B2C3D4）
//   2. 支持动态换 did（改 ks_did.txt 后下次启动生效）
//   3. 同时把本地存储也改掉（双保险）

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>

static NSString *g_targetDid = nil;      // 想改成什么
static NSString *g_observedDids = nil;   // 从响应里学到的 did 列表
static NSString *g_logPath = nil;
static int g_reqFixed = 0, g_respFixed = 0, g_localFixed = 0;

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

static NSString *ks_loadTarget(void) {
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

// ★ 旧 did 记录文件（插件自动学习）
static NSString *ks_oldPath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/.ks_old_dids"];
}

static NSMutableSet *ks_loadOldDids(void) {
    NSMutableSet *s = [NSMutableSet set];
    NSString *p = ks_oldPath();
    NSString *t = [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL];
    if (t.length) {
        for (NSString *line in [t componentsSeparatedByString:@"\n"]) {
            NSString *v = [line stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (v.length == 36) [s addObject:[v uppercaseString]];
        }
    }
    return s;
}

static void ks_saveOldDid(NSString *did) {
    if (did.length != 36) return;
    NSString *up = [did uppercaseString];
    if (g_targetDid && [up isEqualToString:[g_targetDid uppercaseString]]) return;
    NSMutableSet *s = ks_loadOldDids();
    if ([s containsObject:up]) return;
    [s addObject:up];
    NSMutableString *out = [NSMutableString string];
    for (NSString *v in s) [out appendFormat:@"%@\n", v];
    [out writeToFile:ks_oldPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static BOOL ks_isOldDid(NSString *s) {
    if (s.length != 36) return NO;
    NSMutableSet *set = ks_loadOldDids();
    return [set containsObject:[s uppercaseString]];
}

// ---------- 通用替换 ----------

static NSString *ks_swapString(NSString *s) {
    if (!s.length || !g_targetDid.length) return s;
    if ([s rangeOfString:g_targetDid options:NSCaseInsensitiveSearch].location != NSNotFound)
        return s;

    // 用 UUID 正则找，凡是「已知的旧 did」就替换
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:
        @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
        options:0 error:NULL];
    NSArray *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!ms.count) return s;

    NSMutableString *out = [NSMutableString stringWithString:s];
    int n = 0;
    for (NSInteger i = (NSInteger)ms.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = (NSTextCheckingResult *)ms[(NSUInteger)i];
        NSString *found = [s substringWithRange:m.range];
        if ([found caseInsensitiveCompare:g_targetDid] == NSOrderedSame) continue;
        if (!ks_isOldDid(found)) continue;
        [out replaceCharactersInRange:m.range withString:g_targetDid];
        n++;
    }
    if (!n) return s;
    return out;
}

static NSData *ks_swapData(NSData *d) {
    if (!d.length || !g_targetDid.length) return d;
    @try {
        NSString *s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
        if (!s.length) return d;
        NSString *ns = ks_swapString(s);
        if ([ns isEqualToString:s]) return d;
        return [ns dataUsingEncoding:NSISOLatin1StringEncoding];
    } @catch (NSException *e) { return d; }
}

// ★ 从响应里学习 did（记录到旧列表）
static void ks_observe(NSData *data) {
    if (!data.length || data.length > 8 * 1024 * 1024) return;
    @try {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!s.length) return;
        NSRegularExpression *re = [NSRegularExpression
            regularExpressionWithPattern:
            @"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
            options:0 error:NULL];
        NSArray *ms = [re matchesInString:s options:0 range:NSMakeRange(0, s.length)];
        for (NSTextCheckingResult *m in ms) {
            NSString *v = [s substringWithRange:m.range];
            if (g_targetDid && [v caseInsensitiveCompare:g_targetDid] == NSOrderedSame) continue;
            // 只看「did」附近的（避免把无关 UUID 当 did）
            NSUInteger start = (m.range.location > 60) ? m.range.location - 60 : 0;
            NSUInteger len = MIN(120, s.length - start);
            NSString *ctx = [[s substringWithRange:NSMakeRange(start, len)] lowercaseString];
            if ([ctx rangeOfString:@"did"].location == NSNotFound &&
                [ctx rangeOfString:@"device"].location == NSNotFound) continue;
            ks_saveOldDid(v);
        }
    } @catch (NSException *e) {}
}

// ---------- 本地存储也改（双保险） ----------

static int ks_patchLocal(void) {
    if (!g_targetDid.length) return 0;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    int total = 0;

    NSMutableArray *dirs = [NSMutableArray array];
    [dirs addObject:[home stringByAppendingPathComponent:@"Documents/mmkv"]];
    [dirs addObject:[home stringByAppendingPathComponent:@"Library/Preferences"]];

    for (NSString *dir in dirs) {
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:NULL];
        for (NSString *f in files) {
            NSString *p = [dir stringByAppendingPathComponent:f];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:p isDirectory:&isDir] || isDir) continue;
            NSNumber *perm = [fm attributesOfItemAtPath:p error:NULL][NSFilePosixPermissions];
            NSData *d = [NSData dataWithContentsOfFile:p];
            if (!d.length || d.length > 8 * 1024 * 1024) continue;
            NSData *nd = ks_swapData(d);
            if (nd == d) continue;
            if ([nd writeToFile:p atomically:NO]) {
                if (perm) [fm setAttributes:@{NSFilePosixPermissions: perm}
                                ofItemAtPath:p error:NULL];
                total++;
            }
        }
    }
    return total;
}

// ---------- Hooks ----------

%hook NSURLRequest
- (NSURL *)URL {
    NSURL *u = %orig;
    @try {
        NSString *us = u.absoluteString;
        NSString *ns = ks_swapString(us);
        if (![ns isEqualToString:us]) {
            NSURL *nu = [NSURL URLWithString:ns];
            if (nu) {
                @synchronized(@1) { g_reqFixed++; }
                return nu;
            }
        }
    } @catch (NSException *e) {}
    return u;
}
%end

%hook NSMutableURLRequest
- (void)setHTTPBody:(NSData *)data {
    NSData *nd = data;
    @try {
        if (data.length) {
            NSData *sw = ks_swapData(data);
            if (sw != data) {
                nd = sw;
                @synchronized(@1) { g_reqFixed++; }
                if (g_reqFixed <= 5) ks_log(@"[请求Body替换] #%d", g_reqFixed);
            }
        }
    } @catch (NSException *e) {}
    %orig(nd);
}
%end

%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    @try { ks_observe(data); } @catch (NSException *e) {}
    NSData *nd = ks_swapData(data);
    if (nd != data) {
        @synchronized(@1) { g_respFixed++; }
        if (g_respFixed <= 5) ks_log(@"[响应JSON替换] #%d", g_respFixed);
        NSError *e2 = nil;
        id r = %orig(nd, opt, &e2);
        if (r) return r;
    }
    return %orig;
}
%end

%hook NSPropertyListSerialization
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)fmt error:(NSError **)error {
    @try { ks_observe(data); } @catch (NSException *e) {}
    NSData *nd = ks_swapData(data);
    if (nd != data) {
        @synchronized(@1) { g_respFixed++; }
        if (g_respFixed <= 5) ks_log(@"[响应plist替换] #%d", g_respFixed);
        NSError *e2 = nil;
        id r = %orig(nd, opt, fmt, &e2);
        if (r) return r;
    }
    return %orig;
}
%end

%ctor {
    @autoreleasepool {
        g_targetDid = ks_loadTarget();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v21 ##########");
                ks_log(@"目标 did = %@", g_targetDid ?: @"(未配置)");
                NSMutableSet *old = ks_loadOldDids();
                ks_log(@"已记录的旧 did = %lu 个", (unsigned long)old.count);
                for (NSString *v in old) ks_log(@"   %@", v);
                int n = ks_patchLocal();
                ks_log(@"[本地存储] 改了 %d 个文件", n);
                ks_log(@"");
            } @catch (NSException *e) {}
        });

        // 3 秒后再刷一次本地（快手会回写）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                int n = ks_patchLocal();
                ks_log(@"[本地存储 2nd] %d 个文件", n);
            } @catch (NSException *e) {}
        });
    }
}
