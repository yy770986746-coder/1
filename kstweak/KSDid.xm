// KSDid v19 —— 抓服务端响应：看 did 是不是服务端下发的
// v18 证据：Keychain 161 条全扫，0 条含 A1B2C3D4
//          本地 MMKV/AppGroup/plist 全已改成 B28005FA
//          但网络请求 40 个全是 did=A1B2C3D4
// → hook 网络响应，搜响应体里有没有 A1B2C3D4

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *g_logPath = nil;
static int g_respCount = 0;

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

static NSString *g_target = @"A1B2C3D4";

// 检查 data 里有没有目标值
static void ks_checkData(NSData *data, const char *src) {
    if (!data || data.length < 10) return;
    @try {
        NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!s) s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!s.length) return;
        NSRange r = [s rangeOfString:g_target];
        if (r.location == NSNotFound) return;

        @synchronized(@1) {
            g_respCount++;
            if (g_respCount > 30) return;
            ks_log(@"[%s] 响应 #%d (%luB) 含 %@", src, g_respCount,
                   (unsigned long)data.length, g_target);
            // 打印上下文
            NSUInteger start = (r.location > 120) ? r.location - 120 : 0;
            NSUInteger len = MIN(400, s.length - start);
            NSString *ctx = [s substringWithRange:NSMakeRange(start, len)];
            ks_log(@"  上下文: %@", [ctx stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
            ks_log(@"");
        }
    } @catch (NSException *e) {}
}

// ---------- Hook 网络响应 ----------

%hook NSURLSessionDataTask
- (void)setState:(NSInteger)state {
    %orig(state);
}
%end

// 最直接：hook NSURLSession 的 completionHandler
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        @try {
            if (data) {
                ks_checkData(data, "resp/completion");
                // 也检查 header
                if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                    NSHTTPURLResponse *h = (NSHTTPURLResponse *)resp;
                    NSString *hdr = [h.allHeaderFields description];
                    if ([hdr rangeOfString:g_target].location != NSNotFound)
                        ks_log(@"[resp/header] 含 %@: %@", g_target, hdr);
                }
            }
        } @catch (NSException *e) {}
        handler(data, resp, err);
    };
    return %orig(request, wrapped);
}
%end

// hook NSJSONSerialization（响应解析）
%hook NSJSONSerialization
+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)opt error:(NSError **)error {
    @try { ks_checkData(data, "resp/JSON"); } @catch (NSException *e) {}
    return %orig;
}
%end

// hook NSPropertyListSerialization
%hook NSPropertyListSerialization
+ (id)propertyListWithData:(NSData *)data options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)fmt error:(NSError **)error {
    @try { ks_checkData(data, "resp/plist"); } @catch (NSException *e) {}
    return %orig;
}
%end

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v19 - 服务端响应追踪 ##########");
                ks_log(@"目标: 找响应里含 %@ 的内容", g_target);
                ks_log(@"");
            } @catch (NSException *e) {}
        });
    }
}
