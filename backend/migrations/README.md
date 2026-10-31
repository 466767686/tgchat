# 迁移

- `schema.sql` 永远保持"全量 + 幂等"：新库直接执行它即可。
- 对已存在的库，按编号执行本目录下的增量脚本（每个只执行一次）。

| 编号 | 作用 | 说明 |
| --- | --- | --- |
| 002 | `messages.media_id` | 执行后即可使用媒体消息；`media` 表由 schema.sql 的 `CREATE TABLE IF NOT EXISTS` 补上 |

```bash
cd backend
npx wrangler d1 execute tgchat --remote --file=./migrations/002_message_media.sql
npx wrangler d1 execute tgchat --remote --file=./schema.sql   # 幂等，补 media 表
```
