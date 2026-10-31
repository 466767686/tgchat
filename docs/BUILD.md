# 构建与验证记录

## 构建环境

| 项目 | 值 |
| --- | --- |
| 主机 | Linux aarch64（Android 13 上的 proot 容器），8 核，5.5 GB 内存 |
| JDK | OpenJDK 17.0.2（aarch64） |
| Gradle | 8.9 |
| Android Gradle Plugin | 8.7.3 |
| Kotlin | 2.0.21 + Compose Compiler 插件 |
| Android SDK | platforms;android-35、build-tools;35.0.0 |
| aapt2 | AGP 自带的 x86_64 版 2.19-12006047，经 qemu-x86_64-static 运行 |
| Node.js | 24.19.0 |

## 验证结果

### Android 构建

```text
$ gradle :app:assembleDebug        → BUILD SUCCESSFUL in 3m 47s
  app/build/outputs/apk/debug/app-debug.apk           18 MB

$ gradle :app:assembleRelease      → BUILD SUCCESSFUL in 11m 26s
  app/build/outputs/apk/release/app-release.apk       12 MB
```

签名与清单校验：

```text
$ apksigner verify --verbose app-release.apk
Verifies
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1

$ aapt2 dump badging app-release.apk
package: name='com.tgchat.app' versionCode='1' versionName='1.0.0'
minSdkVersion:'26'
targetSdkVersion:'35'
uses-permission: name='android.permission.INTERNET'
uses-permission: name='android.permission.ACCESS_NETWORK_STATE'
```

最终（加入登录页服务器提示后）增量重建：`assembleDebug + assembleRelease` → BUILD SUCCESSFUL in 1m 48s。

产物：

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `dist/tgchat-1.0.0-release.apk` | 11.8 MB | `0f980cd53456622dd0c5bf95f58241c1c61e060a88569e5fa08283456b711344` |
| `app-debug.apk` | 18 MB | 调试版，包名 `com.tgchat.app.debug` |

编译告警只剩 4 条 `Icons.Rounded.Send/Logout` 的「建议使用 AutoMirrored 版本」提示，不影响运行。

### 后端

```text
$ npx tsc --noEmit                 → exit 0
$ npx wrangler deploy --dry-run    → Total Upload: 28.11 KiB / gzip: 7.27 KiB
  绑定：env.CHAT_HUB (Durable Object)、env.DB (D1)、SESSION_TTL_DAYS、PBKDF2_ITERATIONS
```

### 接口联调（真实 HTTP + 真实 SQLite）

`backend/scripts/local-dev.mjs` 用 esbuild 打包同一份 Worker 源码跑在 Node.js 上，D1 由 `node:sqlite` 模拟。冒烟测试结果：

```text
$ node scripts/smoke-test.mjs
结果：20 通过，0 失败
```

覆盖：健康检查、管理员登录、错误密码 401、管理员建号、新账号登录、普通用户 403、匿名 401、建号自动建会话、发消息落库、clientId 幂等、未读数、最后一条消息、历史消息、已读游标、非 WebSocket 拒绝、非成员拒绝。

### 客户端网络层（JVM 单元测试，连真实后端）

```text
$ gradle :app:testDebugUnitTest
BUILD SUCCESSFUL — tests=2, failures=0
```

`ApiClientTest` 使用 App 里同一个 `ApiClient` 走完整流程：登录 → 管理员建号 → 新号登录 → 拉会话 → 发消息 → 重复 clientId → 拉历史 → 上报已读 → 校验未读数归零，以及错误密码返回 401。

### 线上部署与真实网络验证

后端已部署到 Cloudflare（免费版即可）：

```text
$ npx wrangler d1 create tgchat          → database_id 66bd610a-…
$ npx wrangler d1 execute --remote       → 5 张表创建成功
$ node scripts/create-user.mjs --role admin --remote
$ npx wrangler deploy                    → https://tgchat-api.doukuai798.workers.dev
```

对线上地址跑 `scripts/live-test.mjs`（真实 HTTPS + 真实 WSS）：

```text
$ node scripts/live-test.mjs https://tgchat-api.doukuai798.workers.dev
结果：10 通过，0 失败
```

覆盖：健康检查、管理员登录、线上建号、新号登录、**WebSocket 握手（Durable Object）**、
管理员发消息、**消息通过 WebSocket 实时推送到对方**、历史消息落库、已读游标、无效 token 的 WS 被拒绝。

另外做了接口行为探测：

```text
POST /api/auth/register  → 404（没有注册接口）
GET  /api/me（无 token）  → 401
POST /api/auth/login（错密码）→ 401
OPTIONS /api/auth/login  → 204（CORS 预检）
```

### iOS 客户端（GitHub Actions 云编译）

`.github/workflows/ios.yml` 在 `macos-latest` 上执行：`brew install xcodegen` → `xcodegen generate` → `xcodebuild ... CODE_SIGNING_ALLOWED=NO` → 打包 `Payload/TgChat.app` → 上传 `TgChat-unsigned.ipa`。

```text
Run #41216505966  iOS unsigned IPA  →  success（6 个步骤全部通过）
产物：TgChat-unsigned.ipa  351,593 bytes
Payload/TgChat.app/TgChat   Mach-O 64-bit arm64 executable
Info.plist: com.tgchat.app, 1.0.0 (1), MinimumOSVersion 16.0
未签名（无 _CodeSignature），符合预期
```

试过 `macos-13` / `macos-14`：`macos-14` 的 job 启动即被取消（该镜像已退役），`macos-latest` 正常，因此工作流固定用 `macos-latest`。安卓与 iOS 客户端共用同一个后端（REST + WSS），无需额外服务端配置。

## 没有验证到的部分

- **真机/模拟器上的 UI 运行**：这个构建环境没有可用的 Android 模拟器（aarch64 容器、无 KVM），也无法自动安装 APK。UI 的验证到「编译通过 + 资源打包正确 + 逻辑单测通过」为止。
- 线上部署与真实收发消息已验证；客户端在真机上的实际界面仍需安装后确认。

## 复现步骤

```bash
# 后端
cd backend && npm install
node scripts/local-dev.mjs --port 8787     # 或用 npx wrangler dev
node scripts/smoke-test.mjs

# 客户端
cd android
./build.sh assembleDebug                    # 或 assembleRelease
./build.sh testDebugUnitTest                # 需要本地后端在 8787 监听
```

## aarch64 环境为什么要用 qemu 跑 aapt2

Google 只为 Linux 发布了 **x86_64** 的 aapt2 可执行文件，而本机是 aarch64。做法：

1. 从 AGP 的 maven 仓库取出 `aapt2-8.7.3-12006047-linux.jar` 里的 `aapt2`（x86_64 ELF）；
2. 用 `qemu-x86_64-static -L <x86_64 glibc sysroot>` 运行它（sysroot 取自 Debian 的 libc6/libgcc-s1 amd64 包）；
3. 用这个 shell 包装脚本冒充 aapt2，通过 `-Pandroid.aapt2FromMavenOverride=...` 交给 AGP。

包装脚本内容：

```sh
#!/bin/sh
exec /root/toolchain/qemu3/usr/bin/qemu-x86_64-static -L /root/toolchain/x86libs \
     /root/toolchain/aapt2-bin/aapt2 "$@"
```

在普通 x86_64 机器或 CI 上**删除** `./build.sh` 里的 override 即可，让 AGP 自己下载 aapt2。
