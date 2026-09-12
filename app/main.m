//
//  main.m
//  iOS 快手上号器 —— 应用入口 + 主界面
//
//  对标安卓版 MainActivity：
//    粘贴框 / 一键登录 / 检测环境 / 清除数据 / 打开快手 / 日志面板
//
//  用法：iPhone 上打开 App → 粘贴五参 → 点「一键上号」
//

#import <UIKit/UIKit.h>
#import <unistd.h>
#import "KSCore.h"

#pragma mark - ========== 主界面 ==========

@interface KSViewController : UIViewController <UITextViewDelegate>

@property (nonatomic, strong) UITextView  *input;
@property (nonatomic, strong) UITextView  *logView;
@property (nonatomic, strong) UILabel     *statusLabel;
@property (nonatomic, strong) UILabel     *envLabel;
@property (nonatomic, strong) UIButton    *btnLogin;
@property (nonatomic, strong) UIButton    *btnWipe;
@property (nonatomic, strong) UISwitch    *autoOpenSwitch;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) KSTarget    *target;
@property (nonatomic, assign) BOOL        busy;

@end

@implementation KSViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"快手上号器";
    [self buildUI];

    // 探测目标 App
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        KSTarget *t = [KSTarget detect];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.target = t;
            [self refreshEnv];
        });
    });

    [KSLog add:@"iOS 快手上号器 v%@ 启动", KS_VERSION];
    [self refreshLog];
}

- (void)buildUI {
    CGFloat W = self.view.bounds.size.width;
    CGFloat y = 8;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    self.view = scroll;

    // ---- 环境状态卡 ----
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, y, W - 24, 62)];
    card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    card.layer.cornerRadius = 12;
    [scroll addSubview:card];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, W - 48, 20)];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:16];
    self.statusLabel.text = @"检测中...";
    [card addSubview:self.statusLabel];

    self.envLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 32, W - 48, 20)];
    self.envLabel.font = [UIFont systemFontOfSize:12];
    self.envLabel.textColor = [UIColor secondaryLabelColor];
    [card addSubview:self.envLabel];

    y += 70;

    // ---- 五参输入 ----
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(16, y, W - 32, 18)];
    lbl.text = @"粘贴五参";
    lbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    lbl.textColor = [UIColor secondaryLabelColor];
    [scroll addSubview:lbl];
    y += 22;

    self.input = [[UITextView alloc] initWithFrame:CGRectMake(12, y, W - 24, 100)];
    self.input.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.input.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.input.layer.cornerRadius = 10;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.spellCheckingType = UITextSpellCheckingTypeNo;
    self.input.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    self.input.delegate = self;
    [scroll addSubview:self.input];
    y += 108;

    // ---- 快捷按钮行 ----
    CGFloat bw = (W - 24 - 12) / 3.0;
    UIButton *b1 = [self mkButton:@"粘贴" color:[UIColor systemBlueColor]];
    b1.frame = CGRectMake(12, y, bw, 38);
    [b1 addTarget:self action:@selector(doPaste) forControlEvents:UIControlEventTouchUpInside];

    UIButton *b2 = [self mkButton:@"检测" color:[UIColor systemBlueColor]];
    b2.frame = CGRectMake(12 + bw + 6, y, bw, 38);
    [b2 addTarget:self action:@selector(doCheck) forControlEvents:UIControlEventTouchUpInside];

    UIButton *b3 = [self mkButton:@"清空" color:[UIColor systemGrayColor]];
    b3.frame = CGRectMake(12 + 2 * (bw + 6), y, bw, 38);
    [b3 addTarget:self action:@selector(doClearInput) forControlEvents:UIControlEventTouchUpInside];
    y += 46;

    // ---- 一键上号 ----
    self.btnLogin = [self mkButton:@"一 键 上 号" color:[UIColor systemGreenColor]];
    self.btnLogin.frame = CGRectMake(12, y, W - 24, 52);
    self.btnLogin.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    self.btnLogin.layer.cornerRadius = 12;
    [self.btnLogin addTarget:self action:@selector(doLogin) forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc]
                    initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.center = CGPointMake(W / 2 + 70, y + 26);
    self.spinner.hidesWhenStopped = YES;
    self.spinner.color = [UIColor whiteColor];
    [scroll addSubview:self.spinner];
    y += 60;

    // ---- 功能行 ----
    UIButton *b4 = [self mkButton:@"读取当前" color:[UIColor systemIndigoColor]];
    b4.frame = CGRectMake(12, y, bw, 38);
    [b4 addTarget:self action:@selector(doRead) forControlEvents:UIControlEventTouchUpInside];

    UIButton *b5 = [self mkButton:@"打开快手" color:[UIColor systemIndigoColor]];
    b5.frame = CGRectMake(12 + bw + 6, y, bw, 38);
    [b5 addTarget:self action:@selector(doOpenKS) forControlEvents:UIControlEventTouchUpInside];

    self.btnWipe = [self mkButton:@"清空数据" color:[UIColor systemRedColor]];
    self.btnWipe.frame = CGRectMake(12 + 2 * (bw + 6), y, bw, 38);
    [self.btnWipe addTarget:self action:@selector(doWipe) forControlEvents:UIControlEventTouchUpInside];
    y += 46;

    // ---- 诊断 ----
    UIButton *b6 = [self mkButton:@"诊断（检测不到快手时点这个）"
                            color:[UIColor systemGrayColor]];
    b6.frame = CGRectMake(12, y, W - 24, 38);
    b6.titleLabel.font = [UIFont systemFontOfSize:14];
    [b6 addTarget:self action:@selector(doDiagnose) forControlEvents:UIControlEventTouchUpInside];
    y += 46;

    // ---- 自动打开快手 ----
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(12, y, W - 24, 40)];
    row.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    row.layer.cornerRadius = 10;
    [scroll addSubview:row];

    UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, W - 100, 24)];
    l2.text = @"上号后自动打开快手";
    l2.font = [UIFont systemFontOfSize:14];
    [row addSubview:l2];

    self.autoOpenSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(W - 70, 4, 51, 31)];
    self.autoOpenSwitch.on = YES;
    [row addSubview:self.autoOpenSwitch];
    y += 48;

    // ---- 日志 ----
    UILabel *lbl2 = [[UILabel alloc] initWithFrame:CGRectMake(16, y, W - 32, 18)];
    lbl2.text = @"运行日志";
    lbl2.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    lbl2.textColor = [UIColor secondaryLabelColor];
    [scroll addSubview:lbl2];
    y += 20;

    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(12, y, W - 24, 260)];
    self.logView.editable = NO;
    self.logView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    self.logView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    self.logView.layer.cornerRadius = 10;
    self.logView.textContainerInset = UIEdgeInsetsMake(8, 8, 8, 8);
    [scroll addSubview:self.logView];
    y += 270;

    scroll.contentSize = CGSizeMake(W, y + 20);
}

- (UIButton *)mkButton:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 10;
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.view addSubview:b];
    return b;
}

#pragma mark - 环境刷新

- (void)refreshEnv {
    if (!self.target) {
        self.statusLabel.text = @"✗ 未检测到快手";
        self.statusLabel.textColor = [UIColor systemRedColor];
        self.envLabel.text = @"装了却检测不到？点「诊断」按钮";
        return;
    }

    BOOL hasContainer = self.target.dataContainer.length > 0;

    if (hasContainer) {
        self.statusLabel.text = @"✓ 已就绪";
        self.statusLabel.textColor = [UIColor systemGreenColor];
        self.envLabel.text = [NSString stringWithFormat:@"%@ · 沙盒已定位",
                              self.target.bundleID];
    } else {
        // App 装了，但沙盒没定位到 —— 不是"没装"，别误导用户
        self.statusLabel.text = @"⚠ 已装快手，沙盒未定位";
        self.statusLabel.textColor = [UIColor systemOrangeColor];
        self.envLabel.text = [NSString stringWithFormat:@"%@ · 点「诊断」看详情",
                              self.target.bundleID];
    }
}

#pragma mark - 诊断

- (void)doDiagnose {
    [KSLog add:@"======== 诊断开始 ========"];
    [KSLog add:@"进程权限: uid=%d (0=root, 501=mobile)", getuid()];
    [KSLog add:@"平台权限: %@",
     [KSTarget hasPlatformEntitlement] ? @"✓ 有" : @"✗ 没有（能装但写不进快手）"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *probe = @[
        @"/var/containers/Bundle/Application",
        @"/private/var/containers/Bundle/Application",
        @"/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/Application",
        @"/var/jb/Applications",
    ];
    for (NSString *p in probe) {
        BOOL exists = [fm fileExistsAtPath:p];
        NSArray *c = exists ? [fm contentsOfDirectoryAtPath:p error:NULL] : nil;
        [KSLog add:@"%@ 存在=%@ 可读=%@ 条目=%lu",
         p, exists ? @"是" : @"否",
         c ? @"是" : @"否", (unsigned long)(c ? c.count : 0)];
    }

    [KSLog add:@"---- 逐个 bundleID 探测 ----"];
    for (NSString *bid in [KSTarget allBundleIDs]) {
        NSString *bp = [KSTarget bundlePathForBundleID:bid];
        [KSLog add:@"%@ -> %@", bid, bp ?: @"未找到"];
    }

    [KSLog add:@"---- 扫到的所有 App ----"];
    for (NSString *root in @[@"/var/containers/Bundle/Application",
                             @"/private/var/containers/Bundle/Application"]) {
        NSArray *dirs = [fm contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *d in dirs) {
            NSString *sub = [root stringByAppendingPathComponent:d];
            NSArray *apps = [fm contentsOfDirectoryAtPath:sub error:NULL];
            for (NSString *a in apps) {
                if (![a hasSuffix:@".app"]) continue;
                NSString *ap = [sub stringByAppendingPathComponent:a];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                                      [ap stringByAppendingPathComponent:@"Info.plist"]];
                NSString *rb = info[@"CFBundleIdentifier"];
                if ([rb containsString:@"kwai"] || [rb containsString:@"gif"] ||
                    [rb containsString:@"kuaishou"] || [rb containsString:@"jiangjia"] ||
                    [rb containsString:@"nebula"]) {
                    [KSLog add:@"★ 疑似快手: %@  (%@)", rb, a];
                }
            }
        }
    }

    [KSLog add:@"======== 诊断结束 ========"];
    [self refreshLog];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"诊断完成"
                         message:@"结果已写入下方运行日志，请截图发我"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 动作

- (void)doPaste {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) {
        self.input.text = s;
        [KSLog add:@"已粘贴 %lu 字符", (unsigned long)s.length];
        [self doCheck];
    } else {
        [self alert:@"剪贴板为空"];
    }
    [self refreshLog];
}

- (void)doClearInput {
    self.input.text = @"";
    [self refreshLog];
}

- (void)doCheck {
    KSFive *f = [KSFive fromText:self.input.text];
    if (!f) {
        [KSLog add:@"✗ 解析失败：未识别出五参"];
        [self alert:@"五参格式错误\n\n正确格式：\ntoken----salt----did----egid----api_st"];
        [self refreshLog];
        return;
    }

    [KSLog add:@"---- 解析结果 ----"];
    [KSLog add:@"token : %@", f.token];
    [KSLog add:@"salt  : %@", f.salt];
    [KSLog add:@"did   : %@", f.did.length ? f.did : @"(空)"];
    [KSLog add:@"egid  : %@", f.egid.length ? f.egid : @"(空)"];
    [KSLog add:@"api_st: %@", f.apiSt.length ? f.apiSt : @"(空)"];
    [KSLog add:@"uid   : %@", [f userId]];
    [KSLog add:@"状态  : %@", [f usable] ? @"可用 ✓（双参即可登录）"
                                        : @"不完整 ⚠（token 须 32位hex-数字，salt 须 32位hex）"];
    [self refreshLog];
}

- (void)doLogin {
    if (self.busy) return;

    KSFive *f = [KSFive fromText:self.input.text];
    if (!f) {
        [self alert:@"请先粘贴五参\n\n格式：\ntoken----salt----did----egid----api_st"];
        return;
    }

    if (!self.target) {
        [self alert:@"没检测到快手\n\n点「诊断」按钮看详细结果"];
        return;
    }

    if (!self.target.dataContainer) {
        // 不硬拦：可能打开快手后容器才建好，交给 runLogin 现场重试
        [KSLog add:@"⚠ 沙盒尚未定位，将尝试自动重探"];
        [self refreshLog];
    }

    if (![f usable]) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"参数可能不完整"
                             message:@"token 须为 32位hex-数字，salt 须为 32位hex。\n仍要尝试写入吗？"
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"继续尝试" style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *x) { [self runLogin:f]; }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }

    [self runLogin:f];
}

- (void)runLogin:(KSFive *)f {
    [self setBusy:YES];
    [KSLog clear];
    [KSLog add:@"===== 开始上号 uid=%@ =====", [f userId]];
    [self refreshLog];

    __weak typeof(self) weakSelf = self;

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        BOOL ok = [KSInjector loginWithFive:f
                                     target:weakSelf.target
                                   progress:^(NSString *step, BOOL s) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf refreshLog];
            });
        }];

        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setBusy:NO];
            [weakSelf refreshLog];

            NSString *tag = [NSString stringWithFormat:@"【%@】", [f userId]];

            if (ok) {
                [KSLog add:@"%@上号成功！", tag];
                [weakSelf refreshLog];

                if (weakSelf.autoOpenSwitch.on) {
                    [KSTarget launch:weakSelf.target.bundleID];
                } else {
                    [weakSelf showSuccess:tag];
                }
            } else {
                [KSLog add:@"%@上号失败，请看日志", tag];
                [weakSelf refreshLog];
                [weakSelf alert:[NSString stringWithFormat:@"%@上号失败\n\n%@", tag,
                                 [[KSLog all] lastObject] ?: @""]];
            }
        });
    });
}

- (void)showSuccess:(NSString *)tag {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"上号成功"
                         message:[NSString stringWithFormat:@"%@登录成功！\n\n是否立即打开快手？", tag]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"打开快手" style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *x) {
        [KSTarget launch:self.target.bundleID];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)doRead {
    if (!self.target) { [self alert:@"未找到快手"]; return; }
    KSFive *f = [KSInjector readCurrent:self.target];
    if (f) {
        [KSLog add:@"---- 当前生效五参 ----"];
        [KSLog add:@"%@", [f toLine]];
        [KSLog add:@"uid=%@  可用=%@", [f userId], [f usable] ? @"是" : @"否"];
    } else {
        [KSLog add:@"当前无生效五参（未登录状态）"];
    }
    [self refreshLog];
}

- (void)doOpenKS {
    if (!self.target) { [self alert:@"未找到快手"]; return; }
    [KSTarget launch:self.target.bundleID];
    [self refreshLog];
}

- (void)doWipe {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"确认清空"
                         message:@"将清除快手全部缓存与登录态并关闭快手。\n（不会删除作品等用户数据）"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *x) {
        [self setBusy:YES];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            [KSInjector wipeAllData:self.target];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self setBusy:NO];
                [KSLog add:@"✓ 清空完成"];
                [self refreshLog];
                [self alert:@"快手数据已清空"];
            });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 辅助

- (void)setBusy:(BOOL)busy {
    self.busy = busy;
    self.btnLogin.enabled = !busy;
    self.btnWipe.enabled = !busy;
    self.btnLogin.alpha = busy ? 0.5 : 1.0;
    if (busy) [self.spinner startAnimating];
    else      [self.spinner stopAnimating];
    if (busy) [self.btnLogin setTitle:@"处理中..." forState:UIControlStateNormal];
    else      [self.btnLogin setTitle:@"一 键 上 号" forState:UIControlStateNormal];
}

- (void)refreshLog {
    self.logView.text = [KSLog dump];
    if (self.logView.text.length) {
        [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
    }
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"快手上号器"
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)r replacementText:(NSString *)t {
    return YES;
}

@end

#pragma mark - ========== 导航与入口 ==========

@interface KSAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation KSAppDelegate

- (BOOL)application:(UIApplication *)app
        didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    KSViewController *vc = [KSViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = NO;
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([KSAppDelegate class]));
    }
}
