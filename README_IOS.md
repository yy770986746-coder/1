# iOS 快手上号器 —— 手机版安装使用说明

一个 iPhone 上直接用的 App：**粘贴五参 → 点一键上号 → 自动打开快手**。
对标安卓版 `token_v1.0.4.apk`，不需要电脑、不需要 SSH。

**适配环境**：无根越狱（Dopamine / palera1n · iOS 15-16）· 安装到 `/var/jb`

---

## 一、先讲清楚一件事

安卓版靠 `su` 去改快手的数据目录。iOS 上 App 默认**碰不到别的 App 的沙盒**。

所以这个 App 用的是越狱机的另一条路：给它 `platform-application` 权限（写在 `entitlements.plist` 里）。有了这个权限，App 就能直接读写快手的容器，效果等于安卓的 root。

**这是编译时必须要做的一步**，下面第 4 节会强调。

---

## 二、技术原理对照

| 步骤 | 安卓版 | iOS 版 |
|---|---|---|
| 清数据 | `pm clear com.smile.gifmaker` | 删快手的 `Library/{Preferences,Caches,Cookies,WebKit}` |
| 写登录态 | 写 `shared_prefs/gifshow.xml` | 写 `<沙盒>/Library/Preferences/com.jiangjia.gif.plist` |
| 登录键 | `gifshow_token`<br>`gifshow_userid`<br>`token_client_salt` | `Gif_Token`<br>`Gif_Token_Salt`<br>`Gif_KwaiClientSalt`<br>（安卓同名的三键也一起写） |
| 权限 | `chown u0_aXXX` + `chmod 660`<br>`chcon u:object_r:app_data_file:s0` | `chown mobile:mobile` + `chmod 660`<br>（iOS 无 SELinux） |
| 刷新缓存 | — | `killall cfprefsd` |
| 拉起 App | `am start -n .../HomeActivity` | URL Scheme + `LSApplicationWorkspace` |

**两套键名都写**，因为快手 iOS 版本迭代中两种命名都出现过，写全了保证命中。

---

## 三、文件说明

```
ios快手上号器/
├── app/
│   ├── KSCore.h / KSCore.m   核心引擎：五参解析 / 沙盒定位 / 写入 / 拉起
│   └── main.m                界面：粘贴框 / 一键上号 / 日志
├── theos_build/ksextract/    ★ Theos 工程（越狱机上直接 make package）
├── xcode_project/            ★ Xcode 工程（Mac 上编译）
├── build/                    产出的 deb
├── build_app.py              一键生成工程 + 打包
├── ks_ios_runner.py          PC 侧提取五参（可选，不影响手机端使用）
└── test_extract.py           自测
```

---

## 四、编译安装（三选一）

### 方式 A：越狱机上直接编译（最省事，推荐）

手机上装好 Theos（Sileo 搜 Theos 或 `theos` 源），然后：

```bash
cd theos_build/ksextract
make package
dpkg -i packages/*.deb
uicache -a
```

Theos 会自动处理签名，`-Sentitlements.plist` 已经在 Makefile 里配好了。

### 方式 B：Mac 上 Xcode 编译

```bash
cd xcode_project
xcodebuild -project KSExtract.xcodeproj -scheme KSExtract \
           -sdk iphoneos -configuration Release \
           CODE_SIGNING_ALLOWED=NO \
           CONFIGURATION_BUILD_DIR=./out
```

**关键一步 —— 注入平台权限：**

```bash
ldid -Sentitlements.plist ./out/KSExtract
```

然后用 `build_app.py` 打包：

```bash
python build_app.py --pack xcode_project/out/KSExtract.app
```

### 方式 C：只想要现成 deb

```bash
python build_app.py --pack <你的 KSExtract.app 路径>
```

产出 `build/ks_KSExtract_1.0.0_iphoneos-arm64_FULL.deb`，用爱思助手装。

> ⚠️ **`ldid -S` 这步不能省。** 少了它 App 就是普通沙盒 App，写不进快手目录，点登录会提示"写入失败"。

---

## 五、手机上的使用流程

1. **打开 App** —— 顶部会显示检测结果
   - `✓ 已就绪 · com.jiangjia.gif · 沙盒已定位 · 权限正常`
   - 如果显示"未安装快手"或"沙盒未定位"，先手动打开一次快手再回来

2. **粘贴五参** —— 点「粘贴」自动读剪贴板，或直接输入
   格式：`token----salt----did----egid----api_st`

3. **点「检测」**（可选）—— 看解析结果，确认 token/salt 正确

4. **点「一键上号」** —— 自动执行 6 步：
   ```
   [1/6] 检查目标 App
   [2/6] 校验五参
   [3/6] 结束快手进程
   [4/6] 清除旧登录态
   [5/6] 写入五参
   [6/6] 拉起快手
   ```
   成功后自动打开快手，直接就是登录态。

### 其他按钮

| 按钮 | 作用 |
|---|---|
| 读取当前 | 回读快手当前生效的五参，验证有没有写进去 |
| 打开快手 | 手动拉起快手 |
| 清空数据 | 清快手缓存和登录态（不删作品） |

---

## 六、五参格式

```
token----salt----did----egid----api_st
```

**验证结论（和安卓版一致）：双参 `token----salt` 就能登录**，后三参可以留空。

解析器兼容这些写法：
- `----`（标准）
- `--`（两连字符）
- `——`（中文破折号）
- JSON：`{"token":"...","salt":"..."}`
- 键值对：`token=xxx salt=xxx`

校验规则：
- token 必须 `^[0-9a-fA-F]{32}-\d+$`（32位hex + 短横线 + 纯数字uid）
- salt 必须 `^[a-fA-F0-9]{32}$`
- 双参不合法时会弹窗提醒，但可以选择"继续尝试"

### 五参从哪来

如果你已经有快手账号的备份包，在电脑上跑：

```bash
python ks_ios_runner.py extract 快手备份.rar -o 五参.txt
```

会自动从 `com.jiangjia.gif.plist` 提取 `Gif_Token` / `Gif_Token_Salt` / `Gif_ServiceToken`，
并从日志里捞 DFP 指纹作为 egid。

---

## 七、常见问题

| 现象 | 原因 | 解决 |
|---|---|---|
| 显示"权限受限" | 没注入 entitlements | 重新用 `ldid -Sentitlements.plist` 签名 |
| 提示"写入失败" | 同上，或快手沙盒没定位到 | 先手动打开一次快手 |
| 注入成功但快手还是未登录 | 快手版本键名变了 | 点「读取当前」看实际键值，把新键名加进 `KSCore.m` 的 `writeOnly:` |
| 点登录后快手没起来 | URL Scheme 被拦 | 手动点快手图标，登录态已经写好了 |
| 快手启动崩溃 | plist 被写坏 | 点「清空数据」后重试 |

### 日志在哪

App 界面下方的「运行日志」实时显示，每步都有打点。出问题把日志截图即可定位。

---

## 八、和上一版的区别

上一版做成了 Tweak（依赖 OpenSSH、PC 推文件、Mac 编译），流程太重。

这一版是**完整的独立 App**：
- ✅ iPhone 桌面上有图标，点开就能用
- ✅ 不需要电脑、不需要 SSH、不需要网络
- ✅ 直接粘贴五参 → 一键登录，和安卓 APK 体验一致
- ✅ 内置日志面板，问题当场能看

源码在 `app/`，编译产物在 `build/`。
