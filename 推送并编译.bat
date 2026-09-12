@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

echo ============================================================
echo   iOS 快手上号器 —— 推送到 GitHub 并自动编译
echo ============================================================
echo.
echo 本地仓库已经准备好（分支 main，29 个文件已提交）。
echo 你只需要提供：仓库地址 + 令牌。
echo.
echo 令牌权限：勾 repo + workflow 两项。只在本次推送用，
echo           用完脚本会把远程地址改回不带令牌的形式。
echo.

cd /d "%~dp0"

REM ---- 仓库地址 ----
if "%GH_REPO_URL%"=="" (
    set /p GH_REPO_URL=粘贴 GitHub 仓库地址（如 https://github.com/用户名/仓库名）: 
)
if "%GH_REPO_URL%"=="" ( echo [错误] 仓库地址不能为空 & pause & exit /b 1 )

REM 去掉末尾 .git 和斜杠，统一格式
set GH_REPO_URL=%GH_REPO_URL:.git=%
if "%GH_REPO_URL:~-1%"=="/" set GH_REPO_URL=%GH_REPO_URL:~0,-1%
echo       仓库: %GH_REPO_URL%

REM ---- 令牌 ----
if "%GH_TOKEN%"=="" (
    set /p GH_TOKEN=粘贴 GitHub 令牌: 
)
if "%GH_TOKEN%"=="" ( echo [错误] 令牌不能为空 & pause & exit /b 1 )

REM ---- 从地址里解析用户名和仓库名 ----
for /f "tokens=1,2 delims=/" %%a in ("%GH_REPO_URL:https://github.com/=%") do (
    set GH_USER=%%a
    set GH_REPO=%%b
)
if "%GH_USER%"=="" ( echo [错误] 解析不出用户名 & pause & exit /b 1 )
if "%GH_REPO%"=="" ( echo [错误] 解析不出仓库名 & pause & exit /b 1 )
echo       用户: %GH_USER%   仓库: %GH_REPO%
echo.

echo [1/5] 检查 git...
where git >nul 2>&1
if errorlevel 1 ( echo [错误] 没找到 git，先装 Git for Windows & pause & exit /b 1 )

echo [2/5] 确保仓库已初始化...
if not exist ".git" (
    git init
    git branch -M main
)

echo [3/5] 提交本地改动...
git add -A
git -c user.name="builder" -c user.email="builder@local" commit -m "iOS 上号器：五参注入登录（无根越狱 deb）" 2>nul
if errorlevel 1 echo       （没有新改动，继续）
git branch -M main

echo [4/5] 配置远程（临时带令牌）...
git remote remove origin 2>nul
git remote add origin "https://%GH_USER%:%GH_TOKEN%@github.com/%GH_USER%/%GH_REPO%.git"

echo [5/5] 推送...
REM 先试着直接把现有 main 推上去（空仓库/内容一致的情况）
git push -u origin main
if errorlevel 1 (
    echo.
    echo       直接推送失败，尝试先合并远程内容再推...
    git fetch origin 2>nul
    if not errorlevel 1 (
        git pull --rebase origin main 2>nul || git pull --rebase --allow-unrelated-histories origin main 2>nul
        git push -u origin main
    )
)

if errorlevel 1 (
    echo.
    echo ============================================================
    echo [推送失败] 对照下面的原因排查：
    echo   1. 令牌缺 workflow 权限  → 去 https://github.com/settings/tokens
    echo                              重新生成，勾 repo + workflow
    echo   2. 仓库不存在或名字写错  → 先在网页上建一个空仓库（不勾 README）
    echo   3. 令牌过期或被吊销
    echo   4. 仓库非空且冲突        → 手动解决后重跑本脚本
    echo ============================================================
    git remote set-url origin "https://github.com/%GH_USER%/%GH_REPO%.git" 2>nul
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   推送成功！
echo ============================================================
echo.
echo 下一步：
echo   1. 打开 %GH_REPO_URL%/actions
echo   2. 等 workflow 跑完（约 3-6 分钟，首次装 ldid 会久一点）
echo   3. 点进那次运行，页面底部 Artifacts 下载 ks-ios-deb
echo   4. 解压得到 .deb，用爱思助手装进手机
echo.
echo 手动触发编译：
echo   %GH_REPO_URL%/actions/workflows/build.yml  ^-^-^>  Run workflow
echo.

REM ---- 清理令牌，别长期留在 git config 里 ----
git remote set-url origin "https://github.com/%GH_USER%/%GH_REPO%.git" 2>nul
echo 已把远程地址改回不带令牌的形式。
echo.
pause
