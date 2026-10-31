# 升级实施计划（v2）

> 现状盘点 → 缺口 → 架构 → 改动文件 → 新表 → 新 API → 分阶段计划。
> 每个阶段的完成标准：UI + API + DB + 联调 + 错误处理，CI 构建通过。

## 1. 当前已实现

**后端（Cloudflare Workers + D1 + Durable Objects）**

| 能力 | 状态 |
| --- | --- |
| 账号密码登录（PBKDF2）、会话 token、禁止注册 | ✅ |
| 管理员建号（API + CLI）、角色校验 | ✅ |
| 一对一/群聊数据模型（chats.type） | ✅ 模型有，群功能无 |
| 会话列表、未读、最后一条消息 | ✅ |
| 消息发送/分页/已读游标/`clientId` 幂等 | ✅ |
| 单会话 WebSocket（`ChatHub`）+ 用户级 WebSocket（`UserHub`） | ✅ |
| 输入中、已读回执广播 | ✅ |

**iOS（SwiftUI）**：登录、会话列表、单聊（实时、乐观发送、双勾）、新建会话、设置、用户管理、计算器伪装、后台保活 + 本地通知。

**Android（Compose）**：与 iOS 对等，另有前台常驻服务推送、计算器伪装。

## 2. 当前缺失（与目标对比）

| 阶段 | 缺失 |
| --- | --- |
| 一 媒体 | 图片/视频/文件/语音上传下载、压缩、进度、重试、说明文字、Emoji 面板、贴纸、GIF、贴纸包 |
| 二 交互 | 回复、编辑、删除、转发、复制、多选、置顶、Reaction、搜索、撤回、引用、链接预览、格式化 |
| 三 群聊 | 建群、群资料、成员/管理员/权限、邀请链接、禁言、公告、@、入群申请 |
| 四 高级群聊 | Topics、投票、反垃圾、举报、批量删除、历史权限 |
| 五 聊天管理 | 置顶、归档、文件夹、已保存、全局/条件搜索、批量操作、壁纸 |
| 六 语音视频 | 录音/播放/波形/倍速/转写、视频消息、WebRTC 通话 |
| 七 频道 | 创建、公开/私有、订阅、管理员、发布、阅读数、评论 |
| 八 隐私安全 | 资料、在线状态、黑名单、举报、隐私设置、多设备会话、应用锁、主题/壁纸/气泡、通知设置、定时删除、E2EE 架构 |

## 3. 现有架构

```
iOS SwiftUI ─┐                         ┌─ D1 (users/sessions/chats/chat_members/messages)
Android ─────┼── HTTPS/WSS ── Worker ──┤
             │                │        └─ R2 (媒体对象，新增)
             │                ├─ ChatHub DO（单会话 WS）
             │                └─ UserHub DO（用户级 WS）
```

约定：
- 所有消息有稳定 `id`（UUID）+ 会话内 `seq`（自增，排序/分页/已读游标）
- 鉴权：`Authorization: Bearer <token>`，服务端逐接口校验角色与成员身份
- 客户端不信任本地状态，写操作一律以服务端响应为准

## 4. 需要修改的文件

**后端**
- `schema.sql`：新增 `media` 表、`messages.media_id`，后续阶段加群/频道/反应/贴纸等表
- `migrations/00X_*.sql`：增量迁移（不改旧数据）
- `src/api.ts`：媒体上传/下载、消息携带媒体；后续各阶段接口
- `src/index.ts`：`/api/media/:id` 路由
- `src/hub.ts`：广播消息体带媒体
- `src/types.ts`：Env 增加 `MEDIA: R2Bucket`
- `wrangler.toml`：R2 绑定

**iOS**
- `Models.swift`：`Media`、消息扩展字段、后续群/反应/频道模型
- `API.swift`：上传（multipart + 进度）、媒体 URL
- `AppState.swift`：媒体消息发送、上传队列、贴纸/GIF 状态
- `Views/ChatView.swift`：消息气泡渲染媒体、回复/编辑/菜单
- `Views/Composer*.swift`：附件面板、Emoji、贴纸、GIF
- `Views/MediaViews.swift`：图片/视频/文件/语音气泡与全屏预览
- `project.yml`：R2 无关；贴纸资源、可能新增 SPM 依赖

**Android**：阶段一完成后同步对等实现（用户要求先 iOS）。

## 5. 需要增加的数据库表（按阶段）

| 表 | 阶段 | 关键字段 |
| --- | --- | --- |
| `media` | 一 | id, chat_id, uploader_id, kind, mime, size, name, width, height, duration_ms, object_key, created_at |
| `messages.media_id / reply_to / edited_at / deleted_at / forwarded_from` | 一~二 | 迁移加列 |
| `message_reactions` | 二 | message_id, user_id, emoji, created_at（PK 三元组） |
| `pinned_messages` | 二/三 | chat_id, message_id, pinned_by, pinned_at |
| `chat_invites` | 三 | code, chat_id, created_by, expires_at, revoked |
| `chat_bans` | 三 | chat_id, user_id, until, by |
| `topics` | 四 | id, chat_id, title, icon, created_by |
| `polls / poll_votes` | 四 | 题目、选项、匿名、截止 |
| `folders / folder_chats` | 五 | 用户自定义文件夹 |
| `saved_messages` | 五 | user_id, message_id |
| `channels / channel_members` | 七 | 与 chats 复用或独立 |
| `devices / push_tokens` | 八 | 多设备与推送 |
| `user_settings` | 八 | 隐私、通知、主题 |

## 6. 需要新增的 API（阶段一）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/chats/:id/media` | multipart 上传，写 R2，登记 `media`，返回媒体对象 |
| GET | `/api/media/:id` | 鉴权 + 成员校验后流式返回，支持 Range（视频拖动） |
| POST | `/api/chats/:id/messages` | 增加 `mediaId`、`text` 作为说明文字 |
| GET | `/api/chats/:id/messages` | 返回消息携带 `media` 对象 |

后续阶段接口在各自实施时补充。

## 7. 分阶段实施计划

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| **一（进行中）** | ✅ R2 + media 表 + 上传/下载 API；✅ iOS 图片（多选/压缩/原图/说明/预览）、视频、文件、上传进度与重试、Emoji 面板、贴纸（4 包 64 表情）、内置动态 GIF（6 个，聊天内循环播放）、最近使用、语音消息（录制/播放/波形）；⏳ 联网 GIF 搜索（需 Key）、多图相册 | 后端已线上验证；iOS CI 通过（Run #41223415898） |
| 二（已完成） | ✅ 回复/编辑/删除/撤回/转发/复制/多选/置顶/Reaction/搜索/引用/格式化/分页；⏳ 链接 OG 卡片预览（当前是链接可点击 + 域名） | 后端线上验证：edit/react/pin/search/delete 全部通过 |
| 三 | 群组完整体系（建群、成员、管理员、邀请链接、禁言、公告、@） | 群聊全流程可用 |
| 四 | Topics、投票、反垃圾、举报、批量删除、历史权限 | 群管理进阶可用 |
| 五 | 置顶/归档/文件夹/已保存/全局与条件搜索/批量/壁纸 | 会话管理完整 |
| 六 | 语音录制播放波形倍速、视频消息、WebRTC 1v1 通话 | 真实录音播放；通话需要 TURN，单独部署说明 |
| 七 | 频道全流程 | 发布/订阅/评论可用 |
| 八 | 资料/在线/黑名单/举报/隐私/多设备/应用锁/主题壁纸/通知/定时删除/E2EE 架构 | 逐项落地 |

> 说明：六阶段的 1v1 通话需要 STUN/TURN 服务（Cloudflare Calls 或自建 coturn），会在该阶段提供部署配置；E2EE 采用「设备密钥 + 服务端只存密文」的架构设计并落地密钥协商骨架。

## 实施顺序与节奏

1. 每阶段先改后端（迁移 + API），用 `scripts/smoke-test.mjs` / 新增用例验证。
2. 再改 iOS，推 GitHub 触发 CI，编译通过后下载 IPA。
3. 最后同步 Android 对等实现并出 APK。
4. 每阶段结束更新 `docs/FEATURES.md` 与本文档进度。

## 当前阻塞

- R2 需要先在 Cloudflare 创建桶 `tgchat-media`（或在授权里补 `r2:write`），否则后端无法部署带 R2 绑定的版本。代码已就绪。
- GIF 搜索需要第三方 API Key（Tencent/Giphy），默认使用内置 GIF 源；拿到 Key 后可切换。
