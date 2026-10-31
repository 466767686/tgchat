# Android 客户端

Kotlin + Jetpack Compose，`compileSdk 35`，`minSdk 26`，Material 3。

## 构建

需要 JDK 17、Android SDK（platform 35 + build-tools 35.0.0）、Gradle 8.9。

```bash
cd android
echo "sdk.dir=/path/to/android-sdk" > local.properties
./build.sh assembleDebug      # app/build/outputs/apk/debug/app-debug.apk
./build.sh assembleRelease    # app/build/outputs/apk/release/app-release.apk（已签名）
# 普通 x86_64 机器也可以直接用 gradlew：
./gradlew assembleDebug
```

发布版签名配置在 `app/build.gradle.kts` 的 `signingConfigs.release`，指向 `android/keystore/tgchat.jks`（口令 `tgchat123`）。**正式发布前请替换成你自己的 keystore。**

## 指定默认服务器地址

```bash
./gradlew assembleRelease -Ptgchat.baseUrl=https://tgchat-api.xxx.workers.dev
```

不指定时使用 `https://tgchat-api.example.workers.dev`，运行时也可以在登录页底部修改。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `AppViewModel.kt` | 全局状态：会话、消息缓存、轮询、WebSocket、乐观发送、导航栈 |
| `data/ApiClient.kt` | OkHttp + kotlinx.serialization 的 REST 客户端 |
| `data/RealtimeClient.kt` | OkHttp WebSocket，解析 message/typing/read 事件 |
| `data/SessionStore.kt` | DataStore 保存 token、缓存用户、服务器地址、主题 |
| `ui/screens/*` | 登录、会话列表、聊天、新建会话、设置、用户管理 |
| `ui/components/*` | 头像、气泡、日期胶囊、聊天背景、通用控件 |
| `ui/theme/*` | Telegram 配色（Day/Night）与 Material 3 主题 |

## 关于本机（aarch64）构建的一处特殊处理

Android SDK 官方只提供 **x86_64 的 aapt2**。本项目的构建机是 aarch64 Linux（Android 上的 proot 容器），因此用 qemu user-mode 运行 x86_64 版 aapt2：

- `./build.sh` 会自动追加 `-Pandroid.aapt2FromMavenOverride=/root/toolchain/aapt2-override/aapt2`
- 该文件是一个 shell 包装脚本，内部执行
  `qemu-x86_64-static -L /root/toolchain/x86libs /root/toolchain/aapt2-bin/aapt2 "$@"`

在普通 x86_64 开发机或 CI 上**不需要这个配置**，用 `./gradlew` 构建即可。

## 网络

- REST 走 `Authorization: Bearer <token>`
- WebSocket：`wss://<host>/api/ws?chat=<chatId>&token=<token>`
- 明文 HTTP 已允许（`usesCleartextTraffic="true"`），方便本地联调；正式环境请一律使用 HTTPS
