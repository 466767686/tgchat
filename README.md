# Telegram Clone · Android 客户端 + Cloudflare 后端

一个**真正可用**的 Telegram 风格聊天应用：Kotlin / Jetpack Compose 客户端，Cloudflare Workers + D1 + Durable Objects 后端。账号密码登录直连后端，消息真实落库并通过 WebSocket 实时推送，应用内不提供注册入口。

```
android/  Kotlin + Jetpack Compose 客户端（Telegram 风格 UI，Material 3，深色/浅色主题）
backend/  Cloudflare Worker：REST API + WebSocket(Durable Object) + D1 数据库
docs/     部署说明、API 文档、功能清单
```

> **当前实例已部署**：`https://chat.132778.xyz`（自定义域名，国内可达；Worker 本体 `tgchat-api`，D1 数据库 `tgchat`，区域 APAC）。
> 客户端默认服务器地址已编译为该地址，装好即可登录。

## 已实现（速览）

| 能力 | 状态 |
| --- | --- |
| 用户名 + 密码登录（真实后端） | ✅ |
| 禁止自助注册（仅管理员建号） | ✅ |
| 管理员后台：App 内建号 / CLI 建号 | ✅ |
| 会话列表、未读数、最后一条消息、时间 | ✅ |
| 一对一聊天、群聊数据模型 | ✅ |
| 消息发送（乐观更新、失败重试、幂等 clientId） | ✅ |
| 实时接收（WebSocket + Durable Object，断线重连） | ✅ |
| 「正在输入…」提示、已读双勾 | ✅ |
| 历史消息分页加载 | ✅ |
| 主题：跟随系统 / 浅色 / 深色 | ✅ |
| 服务器地址可在应用内配置 | ✅ |
| 安卓后台消息通知（常驻连接，关掉 App 也能收） | ✅ |
| iOS 后台通知（保活 + 本地通知） | ✅ |

完整清单见 [docs/FEATURES.md](docs/FEATURES.md)。

## iOS 客户端（SwiftUI，未签名 IPA 由 GitHub Actions 产出）

`ios/` 下是同一后端的 SwiftUI 客户端，包含登录、会话列表、聊天（实时收发 / 输入中 / 双勾）、新建会话、设置、用户管理。

**计算器伪装**：App 图标和名称都是「计算器」，启动后显示一个可正常使用的计算器；输入解锁密码（默认 `1234`）后按 `=` 才会进入聊天。切到后台自动重新锁定；在「设置 → 隐私」里可以改密码或关闭伪装。

构建方式（不需要 Mac）：仓库推到 GitHub 后，Actions 里的 **iOS unsigned IPA** 工作流会自动用 `macos-latest` runner 编译并上传 `TgChat-unsigned.ipa` 工件；本仓库的成品质检在 `dist/TgChat-1.0.0-unsigned.ipa`（约 0.4 MB，arm64，iOS 16+），用你自己的证书重签安装即可。

> 注意：`macos-14` 标签在这个账号下会被立刻取消（镜像已下线），工作流固定使用 `macos-latest`。

```bash
# 本地有 Mac 的话
cd ios && brew install xcodegen && xcodegen generate
xcodebuild -project TelegramClone.xcodeproj -scheme TgChat -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
```

## 快速开始

### 1. 部署后端

```bash
cd backend
npm install
npx wrangler login

# 创建 D1 数据库、写入 database_id、建表、创建管理员（一条命令）
ADMIN_USERNAME=admin ADMIN_PASSWORD='你的密码' npm run bootstrap

npx wrangler deploy
# → https://tgchat-api.<你的子域>.workers.dev
```

详细步骤（含手动模式）见 [docs/DEPLOY.md](docs/DEPLOY.md)。

### 2. 安装并登录 App

安装 `dist/tgchat-1.0.0-release.apk`（或 `android/app/build/outputs/apk/release/app-release.apk`），首次启动后先点登录页底部的「服务器 · …」把地址改成你的 Worker 地址，再用管理员账号登录。

管理员可在「设置 → 用户管理」中直接创建其他账号，无需再动命令行。

### 3. 本地联调（可选，不用先部署 Cloudflare）

```bash
cd backend
npm run dev                      # wrangler dev（需要能运行 workerd 的环境）
# 或（workerd 起不来的沙箱/Android 环境）：
node scripts/local-dev.mjs --port 8787
# 默认账号 admin / admin12345，数据落在 backend/.local/tgchat.db
```

然后在 App 登录页把服务器地址改成 `http://127.0.0.1:8787` 即可直接登录（手机与后端在同一台设备上时有效）。

## 目录结构

```
backend/
  src/index.ts        Worker 入口、路由分发、CORS、WebSocket 升级
  src/api.ts          所有 REST 接口实现
  src/hub.ts          Durable Object：每个会话一个实例，负责实时广播
  src/crypto.ts       PBKDF2 口令散列、会话 token
  schema.sql          D1 表结构
  scripts/            建号、一键初始化、本地 Node 联调服务器
android/
  app/src/main/java/com/tgchat/app/
    AppViewModel.kt   状态、轮询、WebSocket、乐观发送
    data/             API 客户端、WebSocket 客户端、本地会话存储
    ui/screens/       登录、会话列表、聊天、新建会话、设置、用户管理
    ui/components/    头像、气泡、聊天背景、通用控件
    ui/theme/         Telegram 配色与 Material 3 主题
docs/
  DEPLOY.md           部署、环境变量、建号、备份
  API.md              接口文档
  FEATURES.md         已实现 / 未实现
```

## 消息推送

- **安卓**：`RealtimeService` 前台服务保持一条**用户级 WebSocket**（`/api/ws?user=1`），App 退到后台或被划掉仍能收到消息并弹系统通知；点通知直接进入对应会话；开机自启；退出登录会关闭服务并清除凭证。首次启动需要授予通知权限，部分国产 ROM 还要在系统设置里允许「自启动 / 后台运行」。
- **iOS**：采用「后台保活 + 本地通知」——`UIBackgroundModes: audio` + 静音音频循环让 App 在后台保持运行，用户级 WebSocket（`/api/ws?user=1`）持续在线，新消息立即弹本地通知，点击直达会话。限制：**手动上滑划掉 App 后不再收到**（iOS 会终止进程，任何非 APNs 方案都一样）；耗电会略有增加。若卖家能提供 APNs 密钥，可升级为真正的系统推送。

## 构建与验证

| 检查 | 结果 |
| --- | --- |
| `assembleDebug` / `assembleRelease` | ✅ BUILD SUCCESSFUL（18 MB / 12 MB） |
| APK 签名（apksigner） | ✅ v2 方案校验通过 |
| 清单/权限（aapt2 badging） | ✅ minSdk 26、targetSdk 35、INTERNET |
| `wrangler deploy --dry-run` | ✅ 28.11 KiB，D1 + Durable Object 绑定正确 |
| 后端冒烟测试（真实 HTTP + SQLite） | ✅ 20/20 |
| 客户端 ApiClient 单测（连真实后端） | ✅ 2/2 |

细节见 [docs/BUILD.md](docs/BUILD.md)。真机 UI 运行与真实 Cloudflare 部署需要账号/设备，未在本环境执行，步骤见部署文档。

```bash
cd android
./build.sh assembleDebug    # 本机（aarch64）用这个脚本，会自动注入 qemu aapt2
```

## 说明

- **安全**：密码使用 PBKDF2-SHA256（默认 25000 轮，可按需调高，见部署文档）加盐散列；登录态是随机 token（库里只存 SHA-256）；传输走 HTTPS/WSS。
- **免费额度**：Worker 免费版单请求 CPU 限 10ms，默认 25000 轮散列是为它准备的；付费版可以调到 100000 轮。
- **不包含**：图片/文件消息、推送通知、注册与找回密码、端到端加密等，见功能清单。
