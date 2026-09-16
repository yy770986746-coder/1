// KSDid v17 —— 网络层 hook：抓出 did 的真实来源
// 目的：快手发请求时，did 是从哪个变量读的？
// 方法：hook NSURLRequest，抓 URL 里的 did=，同时打印调用栈

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <execinfo.h>

static NSString *g_logPath = nil;
static NSMutableSet *g_seenStacks = nil;
static int g_reqCount = 0;

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

// ★ 打印调用栈（只保留快手的帧）
static NSString *ks_callstack(void) {
    void *buf[64];
    int n = backtrace(buf, 64);
    NSMutableString *s = [NSMutableString string];
    NSArray *syms = [NSThread callStackSymbols];
    int shown = 0;
    for (NSString *sym in syms) {
        // 只保留 Kwai / KS / gifshow 相关的
        if (([sym rangeOfString:@"Kwai"].location != NSNotFound ||
             [sym rangeOfString:@"KS"].location != NSNotFound ||
             [sym rangeOfString:@"Kuaishou"].location != NSNotFound ||
             [sym rangeOfString:@"gifshow"].location != NSNotFound ||
             [sym rangeOfString:@"Gif"].location != NSNotFound) &&
            [sym rangeOfString:@"KSDid"].location == NSNotFound) {
            [s appendFormat:@"      %@\n", [sym stringByTrimmingCharactersInSet:
                                            [NSCharacterSet whitespaceCharacterSet]]];
            shown++;
            if (shown >= 8) break;
        }
    }
    if (!shown) [s appendString:@"      (无快手帧)\n"];
    (void)n; (void)buf;
    return s;
}

// 检查 URL 里有没有 did=
static void ks_checkURL(NSString *url, const char *src) {
    if (!url.length) return;
    if ([url rangeOfString:@"did="].location == NSNotFound) return;

    @synchronized(g_seenStacks) {
        if (!g_seenStacks) g_seenStacks = [NSMutableSet set];
        // 抓出 did 值
        NSRange r = [url rangeOfString:@"did="];
        NSString *tail = [url substringFromIndex:r.location + 4];
        NSRange amp = [tail rangeOfString:@"&"];
        NSString *didVal = (amp.location != NSNotFound)
            ? [tail substringToIndex:amp.location] : tail;
        if (didVal.length > 40) didVal = [didVal substringToIndex:40];

        g_reqCount++;
        // 只记录前 40 次，避免日志爆炸
        if (g_reqCount > 40) return;

        ks_log(@"[%s] #%d did=%@", src, g_reqCount, didVal);
        ks_log(@"%@", ks_callstack());
    }
}

// ---------- Hook ----------

%hook NSURLRequest
- (NSURL *)URL {
    NSURL *u = %orig;
    @try { ks_checkURL(u.absoluteString, "NSURLRequest.URL"); } @catch (NSException *e) {}
    return u;
}
%end

%hook NSMutableURLRequest
- (void)setURL:(NSURL *)URL {
    @try { ks_checkURL(URL.absoluteString, "setURL"); } @catch (NSException *e) {}
    %orig(URL);
}
%end

// 快手常用：KSURLRequest / 网络库
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    @try { ks_checkURL(request.URL.absoluteString, "NSURLSession"); } @catch (NSException *e) {}
    return %orig;
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    @try { ks_checkURL(url.absoluteString, "dataTaskWithURL"); } @catch (NSException *e) {}
    return %orig;
}
%end

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(0, 0), ^{
            @try {
                ks_log(@"");
                ks_log(@"########## KSDid v17 - 网络层追踪 ##########");
                ks_log(@"开始追踪带 did= 的网络请求...");
            } @catch (NSException *e) {}
        });
    }
}
