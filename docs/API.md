# API 文档

Base URL：`https://<你的 Worker 域名>`，所有接口以 `/api` 开头。

- 请求/响应均为 JSON（`Content-Type: application/json`）
- 认证方式：`Authorization: Bearer <token>`，token 来自登录接口
- 错误响应：`{"error": "可读错误信息", "code": "machine_code"}`，HTTP 状态码语义化

## 数据结构

```jsonc
// User
{
  "id": "uuid",
  "username": "alice",
  "displayName": "Alice",
  "avatarColor": "#3390EC",
  "role": "user",            // "user" | "admin"
  "lastSeenAt": 1712345678901
}

// Message
{
  "seq": 42,                 // 会话内自增序号，用于分页/已读游标
  "id": "uuid",
  "chatId": "uuid",
  "senderId": "uuid",
  "senderName": "Alice",
  "senderColor": "#3390EC",
  "text": "hello",
  "createdAt": 1712345678901,
  "clientId": "客户端生成的幂等 id 或 null"
}

// Chat
{
  "id": "uuid",
  "type": "direct",          // "direct" | "group"
  "title": null,             // 群聊标题
  "createdAt": 1712345678901,
  "lastReadSeq": 42,         // 我的已读游标
  "otherReadSeq": 40,        // 对方（群聊为最大）已读游标，用于双勾
  "unread": 2,
  "lastMessage": Message | null,
  "members": [User]
}
```

## 接口一览

| 方法 | 路径 | 权限 | 说明 |
| --- | --- | --- | --- |
| GET | `/api/health` | 公开 | 健康检查 |
| POST | `/api/auth/login` | 公开 | 账号密码登录 |
| POST | `/api/auth/logout` | 登录 | 注销当前 token |
| GET | `/api/me` | 登录 | 当前用户 |
| PATCH | `/api/me` | 登录 | 修改昵称 / 头像颜色 |
| GET | `/api/users?query=` | 登录 | 用户目录（发起会话用） |
| GET | `/api/chats` | 登录 | 会话列表（含未读、最后一条） |
| POST | `/api/chats` | 登录 | 创建/复用会话 |
| GET | `/api/chats/:id/messages` | 成员 | 历史消息（分页） |
| POST | `/api/chats/:id/messages` | 成员 | 发送消息 |
| POST | `/api/chats/:id/read` | 成员 | 上报已读游标 |
| GET | `/api/chats/:id/members` | 成员 | 会话成员 |
| GET | `/api/ws?chat=&token=` | 成员 | 单会话 WebSocket 实时通道 |
| GET | `/api/ws?user=1&token=` | 登录 | 用户级 WebSocket：一个连接收所有会话（后台服务用） |
| GET | `/api/admin/users` | 管理员 | 账号列表 |
| POST | `/api/admin/users` | 管理员 | 创建账号 |
| POST | `/api/admin/users/:id/reset-password` | 管理员 | 重置密码 |

> 没有注册接口：账号只能由管理员创建，或通过 `backend/scripts/create-user.mjs` 写入。

---

## 认证

### POST /api/auth/login

```json
{ "username": "admin", "password": "secret123" }
```

`200`

```json
{
  "token": "64 位十六进制字符串",
  "user": { "...User..." }
}
```

`401` `{"error":"用户名或密码错误","code":"bad_credentials"}`

token 有效期由 `SESSION_TTL_DAYS` 控制（默认 30 天）；服务端只保存 token 的 SHA-256。

### POST /api/auth/logout

删除当前 token 对应的会话。返回 `{"ok":true}`。

### GET /api/me

```json
{ "user": { "...User..." } }
```

### PATCH /api/me

```json
{ "displayName": "新昵称", "avatarColor": "#E17076" }
```

两个字段都可选；`avatarColor` 必须是 `#RRGGBB`。

## 用户

### GET /api/users?query=bob

按用户名或昵称模糊搜索，最多 100 条，不含自己。

```json
{ "users": [ { "...User..." } ] }
```

## 会话

### GET /api/chats

```json
{ "chats": [ { "...Chat..." } ] }
```

按最后消息时间倒序。`unread` 是「别人发的、序号大于我的已读游标」的消息数。

### POST /api/chats

```json
{ "memberIds": ["uuid-of-bob"], "title": "可选，群聊标题" }
```

- `memberIds` 只有 1 个时创建（或复用已存在的）单聊
- 多个时创建群聊，`title` 默认「群聊」
- 返回 `{"chat": {...Chat...}, "created": true|false}`

### GET /api/chats/:id/messages?before=0&limit=50

- `before`：取序号小于该值的消息，`0` 表示最新
- `limit`：1–100，默认 50

```json
{ "messages": [ { "...Message..." } ], "hasMore": true }
```

`messages` 按 `seq` 升序返回，便于直接追加到列表。

### POST /api/chats/:id/messages

```json
{ "text": "hello", "clientId": "可选，客户端生成的幂等 id" }
```

`201`

```json
{ "message": { "...Message..." }, "duplicate": false }
```

- 同一 `clientId` 重复提交会返回已存在的消息（`duplicate: true`），用于网络重试去重
- 文本长度 1–4096
- 发送成功后服务端会把发送者的已读游标推进到该消息

### POST /api/chats/:id/read

```json
{ "seq": 42 }
```

游标只增不减。返回 `{"ok":true,"seq":42}`。

## 实时通道

### GET /api/ws?user=1&token=<token>（用户级 WebSocket）

一个连接即可收到该用户所有会话的新消息，用于安卓后台常驻服务 / 未来的推送兜底。
事件格式与下面相同；消息体额外带 `chatId`（本来就有）。每个用户一个 `UserHub` Durable Object。

### GET /api/ws?chat=<chatId>&token=<token>（WebSocket）

握手时校验 token 与会话成员身份，失败返回 401/403。

服务端推送事件（文本帧，JSON）：

```jsonc
// 新消息
{ "type": "message", "chatId": "...", "message": { "...Message..." } }

// 对方正在输入（只转发给其他成员）
{ "type": "typing", "userId": "...", "name": "Alice" }

// 对方已读到某个序号
{ "type": "read", "chatId": "...", "userId": "...", "seq": 42 }

// 心跳回复
{ "type": "pong", "t": 1712345678901 }
```

客户端可发送：

```json
{ "type": "typing" }
{ "type": "ping" }
```

实现：每个会话一个 Durable Object（`ChatHub`），使用 WebSocket Hibernation API，空闲时不计费。客户端在断线后自动重连；`AppViewModel` 另外保留了 4 秒轮询作为兜底。

## 管理接口（`role = admin`）

### GET /api/admin/users

```json
{ "users": [ { "...User..." } ] }
```

### POST /api/admin/users

```json
{
  "username": "alice",
  "password": "alice12345",
  "displayName": "Alice",     // 可选
  "role": "user",             // "user" | "admin"
  "withAdminChat": true       // 可选，默认 true：建号时顺带创建与管理员的一对一
}
```

`201` `{"user": {...}, "chatId": "uuid|null"}`

`409` 用户名已存在；`400` 用户名/密码格式不合法。

### POST /api/admin/users/:id/reset-password

```json
{ "password": "newpass123" }
```

会同时删除该用户的全部登录态。返回 `{"ok":true}`。

## 限流说明

当前版本**没有**内置登录限流/防爆破。建议在 Cloudflare 控制台给 `/api/auth/login` 配置 Rate Limiting 规则（例如 10 次/分钟/IP），或后续在 Worker 里加 D1 计数。
