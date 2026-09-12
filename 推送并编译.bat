@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ============================================================
echo   iOS 快手上号器 —— 一键推送到 GitHub 并自动编译
echo ============================================================
echo.
echo 准备工作：
echo   1. 先在 GitHub 网页上建一个空仓库（不要勾 README）
echo   2. 准备好你的令牌（需要 repo + workflow 两个权限）
echo.
echo 注意：令牌只在你自己电脑上用，不会发给任何人。
echo       建议用 setx 存到环境变量，别写进脚本。
echo.

REM ---- 从环境变量读令牌，没有就提示输入 ----
if "%GH_TOKEN%"=="" (
    set /p GH_TOKEN=请粘贴你的 GitHub 令牌: 
)
if "%GH_TOKEN%"=="" (
    echo [错误] 令牌不能为空
    pause
    exit /b 1
)

set /p GH_USER=请输入你的 GitHub 用户名: 
set /p GH_REPO=请输入仓库名（如 ks-ios-login）: 

if "%GH_USER%"=="" ( echo [错误] 用户名不能为空 & pause & exit /b 1 )
if "%GH_REPO%"=="" ( echo [错误] 仓库名不能为空 & pause & exit /b 1 )

cd /d "%~dp0"

echo.
echo [1/5] 检查 git 是否可用...
where git >nul 2>&1
if errorlevel 1 (
    echo [错误] 没找到 git，请先安装 Git for Windows
    echo        下载: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo [2/5] 初始化仓库...
if not exist ".git" (
    git init
    git branch -M main
) else (
    echo       已有 .git，跳过
)

echo [3/5] 提交文件...
git add -A
git -c user.name="builder" -c user.email="builder@local" commit -m "iOS 上号器：五参注入登录（无根越狱 deb）" 2>nul
if errorlevel 1 echo       （没有新改动，继续）

echo [4/5] 配置远程仓库...
git remote remove origin 2>nul
git remote add origin "https://%GH_USER%:%GH_TOKEN%@github.com/%GH_USER%/%GH_REPO%.git"

echo [5/5] 推送...
git push -u origin main
if errorlevel 1 (
    echo.
    echo [推送失败] 常见原因：
    echo   1. 令牌缺少 workflow 权限
    echo      ^-^> 去 https://github.com/settings/tokens 重新生成，
    echo         勾选 repo 和 workflow
    echo   2. 仓库名写错，或仓库不存在
    echo      ^-^> 先在网页上建一个空仓库
    echo   3. 令牌已过期或已被吊销
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   推送成功！
echo ============================================================
echo.
echo 下一步：
echo   1. 打开 https://github.com/%GH_USER%/%GH_REPO%/actions
echo   2. 等 workflow 跑完（约 3-5 分钟，首次装 ldid 会久一点）
echo   3. 点进那次运行，页面底部 Artifacts 里下载 ks-ios-deb
echo   4. 解压得到 .deb，用爱思助手装进手机
echo.
echo 也可以手动触发：
echo   https://github.com/%GH_USER%/%GH_REPO%/actions/workflows/build.yml
echo   ^-^> 右侧 Run workflow
echo.
echo 安全提示：令牌已写入 .git/config，用完记得清理：
echo   git remote set-url origin https://github.com/%GH_USER%/%GH_REPO%.git
echo.

REM 清理令牌（避免长期留在 git config 里）
git remote set-url origin "https://github.com/%GH_USER%/%GH_REPO%.git" 2>nul

pause
