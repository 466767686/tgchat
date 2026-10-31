# 后端（Cloudflare Workers + D1 + Durable Objects）

## 结构

```
src/index.ts   Worker 入口：CORS、路由分发、GET /api/ws 升级到 Durable Object
src/api.ts     REST 接口（登录、会话、消息、管理）
src/hub.ts     ChatHub Durable Object：每个会话一个实例，WebSocket Hibernation
src/crypto.ts  PBKDF2-SHA256 口令散列、SHA-256 token
schema.sql     D1 表结构（可重复执行）
scripts/       bootstrap / create-user / local-dev / smoke-test
```

## 常用命令

```bash
npm install
npx wrangler login

npm run dev            # wrangler dev（本地 D1）
npm run db:init:local  # 本地建表
npm run bootstrap      # 线上：建库 + 回填 database_id + 建表 + 建管理员
npm run deploy         # 发布
npm run typecheck      # tsc --noEmit
```

## 在 workerd 无法启动的环境里开发

某些沙箱 / Android 环境没有 48 位虚拟地址空间，workerd 会以
`MmapAligned() failed ... TCMalloc` 退出。此时用等价的 Node 方案：

```bash
node scripts/local-dev.mjs --port 8787
```

- 用 esbuild 打包同一份 `src/`，跑在 Node.js 上
- D1 用 `node:sqlite` 实现同样的 `prepare/bind/first/all/run/batch` 子集，数据在 `.local/tgchat.db`
- Durable Object 用内存桩替代（记录广播事件，`GET /__events` 可查看）
- 首次启动会自动创建管理员 `admin / admin12345`（可用 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 覆盖）

## 数据模型

```
users(id, username UNIQUE NOCASE, password_hash, display_name, avatar_color, role, created_at, last_seen_at)
sessions(token_hash PK, user_id, created_at, expires_at)
chats(id, type, title, created_at, created_by)
chat_members(chat_id, user_id, joined_at, last_read_seq)      PK(chat_id, user_id)
messages(seq INTEGER PK AUTOINCREMENT, id UNIQUE, chat_id, sender_id, text, created_at, client_id)
```

`messages.seq` 是全局自增，会话内的消息按它排序 / 分页 / 作为已读游标，比时间戳稳定。
