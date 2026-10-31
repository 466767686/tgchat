# 部署指南（Cloudflare Workers + D1）

## 0. 前置条件

- 一个 Cloudflare 账号（免费版即可）
- Node.js 18 以上
- 本仓库 `backend/` 目录

```bash
cd backend
npm install
npx wrangler login        # 浏览器授权一次
```

## 1. 创建 D1 数据库

```bash
npx wrangler d1 create tgchat
```

输出里会有：

```toml
[[d1_databases]]
binding = "DB"
database_name = "tgchat"
database_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

把 `database_id` 填到 `backend/wrangler.toml` 对应的位置。

> 也可以跳过手工步骤：设置好 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 后直接执行
> `npm run bootstrap`，脚本会自动创建（或复用）数据库、回填 `database_id`、建表并创建管理员。

## 2. 初始化表结构

```bash
npm run db:init
# 等价于 npx wrangler d1 execute tgchat --remote --file=./schema.sql
```

表：`users`、`sessions`、`chats`、`chat_members`、`messages`（`schema.sql` 可重复执行）。

## 3. 创建管理员账号

```bash
npm run user:create -- --username admin --password '换成你的密码' --role admin --remote
```

参数：

| 参数 | 说明 |
| --- | --- |
| `--username` | 3–32 位，字母 / 数字 / `_` / `.`，大小写不敏感 |
| `--password` | 至少 6 位 |
| `--name` | 显示名称，默认等于用户名 |
| `--role` | `admin` 或 `user`，默认 `user` |
| `--remote` | 写入线上库；不加则写入本地库 |

密码散列格式为 `pbkdf2$<轮数>$<盐>$<散列>`，轮数记录在散列里，后续调整不会导致旧密码失效。

登录后管理员可以在 App 的「设置 → 用户管理」里继续建号，也可以随时用上面的命令补建。

## 4. 部署 Worker

```bash
npx wrangler deploy
```

成功后会得到形如 `https://tgchat-api.<你的子域>.workers.dev` 的地址。用浏览器或 curl 验证：

```bash
curl https://tgchat-api.<你的子域>.workers.dev/api/health
# {"ok":true,"service":"tgchat","time":"..."}
```

Durable Object 的迁移由 `wrangler.toml` 里的 `[[migrations]]` 自动执行（`new_sqlite_classes = ["ChatHub"]`，免费版可用）。

## 5. 配置客户端

App 内置的默认地址是占位符 `https://tgchat-api.example.workers.dev`。有两种方式改成你的地址：

1. **运行时**（推荐）：登录页底部点「服务器 · …」，填入 Worker 地址后保存，登录态会自动使用新地址。
2. **编译时**：

   ```bash
   cd android
   ./gradlew assembleRelease -Ptgchat.baseUrl=https://tgchat-api.xxx.workers.dev
   ```

## 环境变量

| 名称 | 默认值 | 说明 |
| --- | --- | --- |
| `PBKDF2_ITERATIONS` | `25000` | 新密码的散列轮数。免费版 CPU 限 10ms，建议保持 25000；付费版可调到 `100000`。已存在的密码按自身记录轮数校验。 |
| `SESSION_TTL_DAYS` | `30` | 登录 token 有效期（天）。 |

绑定（`wrangler.toml`）：

| 绑定 | 类型 | 说明 |
| --- | --- | --- |
| `DB` | D1 | 数据库 |
| `CHAT_HUB` | Durable Object (`ChatHub`) | 每个会话一个实时广播实例 |

修改 `[vars]` 后重新 `npx wrangler deploy` 生效。**没有需要保密的密钥**（登录态存在 D1 里，不依赖 JWT secret）。

## 自定义域名

Cloudflare 控制台 → Workers & Pages → `tgchat-api` → Settings → Domains & Routes → Add custom domain，例如 `chat-api.example.com`。之后客户端里的服务器地址改成 `https://chat-api.example.com` 即可（WSS 自动沿用 HTTPS 域名）。

## 更新与运维

```bash
# 改完代码后重新部署
npx wrangler deploy

# 查看实时日志
npx wrangler tail

# 备份数据库
npx wrangler d1 export tgchat --remote --output backup-$(date +%F).sql
```

**重置某个用户的密码**（当前没有找回密码功能，由管理员处理）：

- App 内：暂无界面（未实现），使用命令行：

```bash
cd backend
node -e "
const {pbkdf2Sync,randomBytes}=require('node:crypto');
const salt=randomBytes(16),it=25000;
const hash=pbkdf2Sync('新密码',salt,it,32,'sha256');
console.log(\`pbkdf2\$\${it}\$\${salt.toString('hex')}\$\${hash.toString('hex')}\`);
" > /tmp/hash.txt
npx wrangler d1 execute tgchat --remote --command "UPDATE users SET password_hash = '$(cat /tmp/hash.txt)' WHERE username = '用户名';"
```

重置密码后记得清掉该用户的旧会话：

```bash
npx wrangler d1 execute tgchat --remote --command "DELETE FROM sessions WHERE user_id = (SELECT id FROM users WHERE username='用户名');"
```

## 常见问题

**登录返回 401「用户名或密码错误」**
确认账号是用 `--remote` 建在线上库的，而不是本地库；用户名大小写不敏感。

**部署后 WebSocket 连不上**
必须使用 `https://` 地址（客户端会自动换成 `wss://`）。如果是自定义域名，确认域名已在 Cloudflare 代理（橙色云朵）后。

**免费版登录偶发 1102（CPU 超限）**
把 `PBKDF2_ITERATIONS` 降到 `10000` 再部署，或升级到 Workers 付费版后调高。

**`wrangler dev` 起不来（workerd 报 tcmalloc / mmap 错误）**
部分沙箱或 Android 环境没有 48 位虚拟地址空间，workerd 无法运行。用等价的本地方案：

```bash
node scripts/local-dev.mjs --port 8787
```

它用 esbuild 打包同一份 Worker 源码，跑在 Node.js 上，D1 用 `node:sqlite` 模拟，数据落在 `backend/.local/tgchat.db`。
