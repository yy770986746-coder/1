// KSDid v20 —— 双向替换 did（请求 + 响应）
// v19 铁证：
//   [resp/JSON] {"cloud_did":"A1B2C3D4-..."}          ← 服务端下发
//   [resp/JSON] "did":"A1B2C3D4-..."                  ← 服务端下发
//   [resp/plist] BiometryType_Reported_A1B2C3D4-...   ← 服务端下发
//   请求 40 个全是 did=A1B2C3D4                        ← 用的是服务端的值
// 本版：在 NSURLRequest(请求) 和 NSJSONSerialization(响应) 两端把旧 did 换成新 did

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *g_oldDid = @"A1B2C3D4-E5F6-7890-ABCD-EF1234567890";
static NSString *g_newDid = nil;
static NSString *g_logPath = nil;
static int g_reqFixed = 0, g_respFixed = 0;

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

// ★ 通用替换：把字符串里所有 oldDid 换成 newDid
static NSString *ks_swap(NSString *s) {
    if (!s.length || !g_newDid.length) return s;
    if ([s rangeOfString:g_oldDid options:NSCaseInsensitiveSearch].location == NSNotFound)
        return s;
    return [s stringByReplacingOccurrencesOfString:g_oldDid
                                        withString:g_newDid
                                           options:NSCaseInsensitiveSearch
                                             range:NSMakeRange(0, s.length)];
}

static NSData *ks_swapData(NSData *d) {
    if (!d.length || !g_newDid.length) return d;
    @try {
        NSString *s = [[NSString alloc] initWithData:d encoding:NSISOLatin1StringEncoding];
        if (!s.length) return d;
        if ([s rangeOfString:g_oldDid options:NSCaseInsensitiveSearch].location == NSNotFound)
            return d;
        NSString *ns = ks_swap(s);
        if ([ns isEqualToString:s]) return d;
        return [ns dataUsingEncoding:NSISOLatin1StringEncoding];
    } @catch (NSException *e) { return d; }
}

// ============ Hook 请求 ============

%hook NSURLRequest
- (NSURL *)URL {
    NSURL *u = %orig;
    @try {
        NSString *us = u.absoluteString;
        if ([us rangeOfString:g_oldDid options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSString *ns = ks_swap(us);
            NSURL *nu = [NSURL URLWithString:ns];
            if (nu) {
                @synchronized(@1) { g_reqFixed++; }
                if (g_reqFixed <= 10) ks_log(@"[请求URL改] %d", g_reqFixed);
                return nu;
            }
        }
    } @catch (NSException *e) {}
    return u;
}
%end

// HTTPBody（POST 请求体）
%hook NSMutableURLRequest
- (void)setHTTPBody:(NSData *)data {
    NSData *nd = data;
    @try {
        if (data.length) {
            NSData *sw = ks_swapData(data);
            if (sw != data) {
                nd = sw;
                @synchronized(@1) { g_reqFixed++; }
                if (g_reqFixed <= 10) ks_log(@"[请求Body改] %d", g_reqFixed);
            }
        }
    } @catch (NSException *e) {}
    %orig(nd);
}
- (void)setURL:(NSURL *)URL {
    @try {
        NSString *us = URL.absoluteString;
        if ([us rangeOfString:g_oldDid options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSString *ns = ks_swap(us);
            NSURL *nu = [NSURL URLWithString:ns];
            if (nu) URL = nu;
        }
    } @catch (NSException *e) {}
    %orig(URL);
}
%end

// ============ Hook 响应 ============

// JSON 响应解析
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    NSData *nd = ks_swapData(data);
    if (nd != data) {
        @synchronized(@1) { g_respFixed++; }
        if (g_respFixed <= 10) ks_log(@"[响应JSON改] %d", g_respFixed);
        NSError *e2 = nil;
        id r = %orig(nd, opt, &e2);
        if (r) return r;
    }
    return %orig;
}
%end

// 二进制 plist 响应
%hook NSPropertyListSerialization
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)fmt error:(NSError **)error {
    NSData *nd = ks_swapData(data);
    if (nd != data) {
        @synchronized(@1) { g_respFixed++; }
        if (g_respFixed <= 10) ks_log(@"[响应plist改] %d", g_respFixed);
        NSError *e2 = nil;
        id r = %orig(nd, opt, fmt, &e2);
        if (r) return r;
    }
    return %orig;
}
%end

// 字符串响应（XML plist / 文本）
%hook NSString
+ (instancetype)stringWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding)enc
                                  error:(NSError **)error {
    NSString *s = %orig;
    @try {
        if (s.length) {
            NSString *ns = ks_swap(s);
            if (![ns isEqualToString:s]) {
                @synchronized(@1) { g_respFixed++; }
                if (g_respFixed <= 10) ks_log(@"[响应字符串改] %d", g_respFixed);
                return ns;
            }
        }
    } @catch (NSException *e) {}
    return s;
}
%end

%ctor {
    @autoreleasepool {
        g_newDid = ks_loadCustomDid();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v20 - 双向替换did ##########");
                ks_log(@"旧 did = %@", g_oldDid);
                ks_log(@"新 did = %@", g_newDid ?: @"(未配置)");
                ks_log(@"");
            } @catch (NSException *e) {}
        });
    }
}
