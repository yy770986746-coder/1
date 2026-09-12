# iOS 快手上号器 —— 使用说明

对标安卓版 `token_v1.0.4.apk`（包名 `com.kuaishou.tokenlogin`），移植到 iOS。

---

## 一、安卓版是怎么工作的（逆向结论）

从 `token_v1.0.4.apk` 反编译（jadx），核心只有三个类：

| 类 | 作用 |
|---|---|
| `MainActivity` | 粘贴框 + 环境检测 + 一键上号 + 清数据 + 打开快手 |
| `KuaishouInjector` | 五参解析 + 写 `shared_prefs/gifshow.xml` |
| `RootUtils` | `su` 执行命令 |

**关键机制**：安卓版**不做协议登录**，它做的是**本地态注入**。

```
清空快手数据 (pm clear com.smile.gifmaker)
    ↓
写 gifshow.xml 三个键:
    gifshow_token       = <32hex>-<uid>
    gifshow_userid      = <uid>
    token_client_salt   = <32hex>
    ↓
chown u0_aXXX:u0_aXXX + chmod 660 + chcon u:object_r:app_data_file:s0
    ↓
打开快手 → 快手读到这三个键 → 直接就是登录态
```

五参解析代码（`parseInput`）只校验两件事：

```java
tokenField.lastIndexOf("-") → userId 必须是纯数字
saltField.matches("[a-fA-F0-9]{32}")
```

**其余三参（did/egid/api_st）在注入时根本没用到**——这印证了之前那条结论：**双参 `token----salt` 就能登录**。

---

## 二、iOS 版对应关系

iOS 没有 `shared_prefs/gifshow.xml`，等价物是 **App 私有 NSUserDefaults 域**。
从既有 iOS 逆向成果（`SysCore.dylib` 字符串表）确认，快手 iOS 侧偏好键**与安卓同源**：

| 安卓 gifshow.xml | iOS 原生键 | 说明 |
|---|---|---|
| `gifshow_token` | `Gif_Token` | 登录令牌 `<32hex>-<uid>` |
| `token_client_salt` | `Gif_Token_Salt` / `Gif_KwaiClientSalt` | 32 hex 盐 |
| — | `Gif_ServiceToken` | = api_st |
| — | `Gif_H5Token` | H5 侧 token |
| — | `Gif_PassToken` | 通行证 token |
| `gifshow_userid` | （无独立键，从 token 尾部取） | — |

**iOS 版策略**：双通道键名同时写入（安卓同名键 + iOS 原生键），
快手读哪个都能命中，向后兼容新老版本。

```
清空快手登录态 (killall + 清偏好键)
    ↓
向 NSUserDefaults(suiteName: "com.jiangjia.gif") 写:
    gifshow_token / gifshow_userid / token_client_salt   ← 安卓等价键
    Gif_Token / Gif_Token_Salt / Gif_KwaiClientSalt      ← iOS 原生键
    Gif_ServiceToken / api_st / egid / did               ← 可选参
    ↓
拉起快手 → Tweak 在 +load 早期写入 → 显示登录态
```

---

## 三、目录结构

```
ios快手上号器/
├── src/
│   ├── KSInjector.h      五参模型 + 偏好注入器 定义
│   ├── KSInjector.m      五参解析 / 写偏好 / 读回 / 清除 / 日志
│   └── KSTweak.xm        Tweak 主入口（constructor 早期注入 + Hook 验证）
├── app/
│   └── main.m            桌面图标 App（手动粘贴上号 GUI，对应 MainActivity）
├── ks_ios_runner.py      PC 侧主控：extract / push / pull / auto
├── build_deb.py          一键打包（生成 Theos 工程 + 出 deb）
├── test_extract.py       端到端自测（17 项断言）
├── theos_project/        自动生成的 Theos 编译工程
└── build/                产出的 .deb
```

---

## 四、快速上手

### 4.1 提取五参（PC，不需要设备）

```bash
# 从爱思/iTunes 备份包（支持 .rar/.zip/.7z 和目录）
python ks_ios_runner.py extract 快手备份.rar -o 五参.txt

# 批量
python ks_ios_runner.py extract 备份1.zip 备份2.rar 备份目录/ -o 全部五参.txt
```

提取通道（比安卓版多两条）：

1. `Library/Preferences/com.jiangjia.gif.plist` → `Gif_Token` / `Gif_Token_Salt` / `Gif_ServiceToken`
2. 老版兜底 `Library/KWApp/kwapp_host_path_db.db` → `host_id + owner_id`
3. egid：全库扫 `.db/.log/.txt/.dat`，正则捞 `global_id=(DFP[0-9A-Fa-f]{40,64})`

### 4.2 一键自动上号（PC + 越狱设备）

```bash
pip install paramiko

# 一条龙：提取 → 推设备 → 重启快手 → 确认注入
python ks_ios_runner.py auto 快手备份.rar --host 192.168.1.50

# 只推送（五参已有）
python ks_ios_runner.py push 五参.txt --host 192.168.1.50

# 回读设备当前状态 + 日志
python ks_ios_runner.py pull --host 192.168.1.50
```

设备侧需要装 **OpenSSH**（Cydia/Sileo），默认 `root/alpine`。

### 4.3 设备上手动上号

装好 `KSExtract` 桌面 App 后：

1. 打开 App → 点「粘贴」（从剪贴板读五参）
2. 点「检测」看解析结果
3. 点「一键上号」→ App 写控制文件 → 自动重启快手 → 自动确认

---

## 五、Tweak 编译

`build_deb.py` 生成的是**含占位 dylib 的安装包**（Python 无法产出 arm64 Mach-O）。
真正的 dylib 需要在 Mac 上编译：

```bash
python build_deb.py --theos          # 生成 theos_project/
cd theos_project
make package                          # 产出 .deb
```

或用 `theos_project/` 里的 Makefile 在装了 Theos 的环境直接 `make package`。

**编译产物安装位置**：
```
/var/jb/Library/MobileSubstrate/DynamicLibraries/KSLogin.dylib
/var/jb/Library/MobileSubstrate/DynamicLibraries/KSLogin.plist
```

（rootless 越狱用 `/var/jb` 前缀；传统越狱去掉 `/var/jb`）

---

## 六、Tweak 工作流程

```
快手进程启动
    ↓
__attribute__((constructor)) KSTweakInit()   ← 早于 main()
    ↓
检查 /var/mobile/Documents/ks_inject.txt
    ↓ 有内容
解析五参 → [KSPrefsInjector applyParams:]
    ↓
写 NSUserDefaults 域（12+ 键）
    ↓
写标记文件 ks_injected.done（供 PC 轮询确认）
    ↓
装载 Hook：
    NSUserDefaults -objectForKey:   → 抓快手读 token 的时机与值
    NSMutableURLRequest -setValue:  → 抓实际发出的 token/salt 请求头
```

---

## 七、文件位置速查（设备上）

| 路径 | 作用 |
|---|---|
| `/var/mobile/Documents/ks_inject.txt` | **控制文件**，写入五参即触发上号 |
| `/var/mobile/Documents/ks_params.txt` | 当前生效的五参 |
| `/var/mobile/Documents/ks_extract.txt` | Tweak 运行日志 |
| `/var/mobile/Documents/ks_injected.done` | 注入成功标记 |

---

## 八、五参格式

```
token----salt----did----egid----api_st
```

例：
```
9f3a1c7e5b2d8460af17c3e95d0b28a4-1234567890----4b8e1f2a9c3d7056e8b2a4f61d3c9e07----FA47F00F-8A86-4306-AAD3-0319FF6A0F8E----DFPF72754B1A352A854BABBAA636AA6B3CC8621B8A026FD1C734D8285EAC48EA----Ch8KAggBEhQIABAAGAMgASgBMAE4AUABSAFYAWAB
```

**解析器兼容的写法**：
- `----`（标准四连字符）
- `--`（两连字符）
- `——` / `––`（中文/英文长破折号）
- JSON：`{"token":"...","salt":"...", ...}` 或 `{"five":"..."}`
- 键值对：`token=xxx salt=xxx`

**校验规则**（双参即可登录）：
- token 必须匹配 `^[0-9a-fA-F]{32}-\d+$`
- salt 必须匹配 `^[a-fA-F0-9]{32}$`
- did / egid / api_st 可留空

---

## 九、自测

```bash
python test_extract.py
```

会造一个模拟 iOS 备份（含正确键名、DFP 日志、干扰 App），验证：

- domain 自动识别（新/老/海外版）
- 五参字段逐个比对
- uid 从 token 尾部解析
- 4 种输入格式解析
- 5 种合法性校验

当前状态：**17/17 通过**。

---

## 十、踩过的坑（已修）

| 问题 | 原因 | 修法 |
|---|---|---|
| salt 丢失、did 吃了 salt | `sep.replace("----",SEP).replace("--",SEP)` 链式替换，SEP 本身是 `----`，第二轮又切一次 | 改成正则一次扫描 `-{2,}` |
| 中文破折号识别失败 | 只处理了 `--` | 加 `\u2014+` / `\u2013+` |
| 键值对格式不认 | 无兜底分支 | 加 `token=xxx salt=xxx` 正则 |
| deb 打包 SyntaxError | `b"中文"` 字面量非 ASCII | 改 `.encode("utf-8")` |

---

## 十一、与安卓版的差异总结

| 维度 | 安卓版 | iOS 版 |
|---|---|---|
| 注入载体 | `shared_prefs/gifshow.xml` | NSUserDefaults 域 |
| 权限要求 | Root（su/Magisk/KernelSU） | 越狱（MobileSubstrate/ElleKit） |
| 写文件方式 | `su` 直接改写 + chown/chcon | Tweak 在进程内写 |
| SELinux | 需要 `chcon u:object_r:app_data_file:s0` | iOS 无 SELinux，改沙盒权限 |
| 启动方式 | `am start` | URL Scheme / LSApplicationWorkspace |
| 清数据 | `pm clear` | `killall` + 清偏好键 |
| 五参需求 | 双参即可 | 双参即可（结论一致） |
| 批量能力 | 单机 | PC 侧批量提取 + SSH 批量推送 |
