# FreePaste Release 构建

> 最后更新：2026-10-17

## 构建

本地签名配置与原 Debug 构建相同，在仓库根目录执行：

```bash
./scripts/build-release.sh
```

生成脚本同级的两个文件：

- `scripts/FreePaste-Release.app`
- `scripts/FreePaste-Release.dmg`

这是启用编译优化的 Release，包含 Apple Silicon 和 Intel 两种架构，不含 Debug 动态库，也不允许调试器连接。版本号沿用工程设置。沙盒、应用标识和签名团队保持不变，避免改变历史数据的存储位置。

原有 `build-fixed-debug.sh`、`rebuild-and-run.sh` 继续用于 Debug 调试；新的 Release 入口不覆盖 Debug 产物，也不自动退出或启动应用。两个入口复用 `.deriveddata/` 缓存。

## 自己使用

退出旧的 FreePaste，打开 `scripts/FreePaste-Release.dmg`，将其中的 `FreePaste.app` 拖到 Applications，推出镜像后从 Applications 启动。不要同时运行两个副本。

也可以退出旧应用后直接启动：

```bash
open scripts/FreePaste-Release.app
```

换安装位置或签名身份后可能需要重新授权；安装包不包含用户的历史数据库。

## 对外发行

现在可以先自用 Release，无须为了切换编译模式购买开发者会员。当前仍沿用 Apple Development 签名，未做 Apple 公证。

以后准备面向普通用户正式分发时，再补 Developer ID 签名和公证，然后把 DMG 作为对应版本的 GitHub Release 附件上传，不提交二进制到源码仓库。本脚本不自动处理这些步骤，也不创建 Git 标签或上传文件。[Apple 发行要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

2026-10-17 已在本机构建、签名和打包验证 Release；Intel 实机运行和正式发行签名、公证尚未验证。
