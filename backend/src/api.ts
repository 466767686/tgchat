import {
  DEFAULT_ITERATIONS,
  hashPassword,
  randomHex,
  sha256Hex,
  verifyPassword,
} from "./crypto";
import { broadcast } from "./hub";
import type { Env, PublicUser, UserRow } from "./types";
import { publicUser } from "./types";

const AVATAR_COLORS = ["#3390EC", "#E17076", "#7BC862", "#E5CA77", "#A695E7", "#EE7AAE", "#6EC9CB", "#FAA774"];

class ApiError extends Error {
  constructor(public status: number, message: string, public code = "error") {
    super(message);
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function ok(data: unknown = { ok: true }): Response {
  return json(data);
}

async function readBody(request: Request): Promise<Record<string, any>> {
  try {
    const body = await request.json();
    return body && typeof body === "object" ? (body as Record<string, any>) : {};
  } catch {
    return {};
  }
}

function text(value: unknown, field: string, min = 1, max = 4096): string {
  if (typeof value !== "string") throw new ApiError(400, `${field} is required`, "invalid_input");
  const trimmed = value.trim();
  if (trimmed.length < min) throw new ApiError(400, `${field} is too short`, "invalid_input");
  if (trimmed.length > max) throw new ApiError(400, `${field} is too long`, "invalid_input");
  return trimmed;
}

function username(value: unknown): string {
  const v = typeof value === "string" ? value.trim() : "";
  if (!/^[a-zA-Z0-9_.]{3,32}$/.test(v)) {
    throw new ApiError(400, "用户名需为 3-32 位字母、数字、下划线或点", "invalid_username");
  }
  return v;
}

function password(value: unknown): string {
  if (typeof value !== "string" || value.length < 6 || value.length > 128) {
    throw new ApiError(400, "密码长度需为 6-128 位", "invalid_password");
  }
  return value;
}

async function authenticate(request: Request, env: Env): Promise<UserRow> {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match) throw new ApiError(401, "缺少登录凭证", "unauthorized");
  const tokenHash = await sha256Hex(match[1]);
  const row = await env.DB.prepare(
    "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?",
  )
    .bind(tokenHash, Date.now())
    .first<UserRow>();
  if (!row) throw new ApiError(401, "登录已过期，请重新登录", "unauthorized");
  return row;
}

function requireAdmin(user: UserRow): void {
  if (user.role !== "admin") throw new ApiError(403, "需要管理员权限", "forbidden");
}

async function isMember(env: Env, chatId: string, userId: string): Promise<boolean> {
  const row = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
    .bind(chatId, userId)
    .first();
  return !!row;
}

async function assertMember(env: Env, chatId: string, userId: string): Promise<void> {
  if (!(await isMember(env, chatId, userId))) throw new ApiError(403, "你不是该会话的成员", "forbidden");
}

async function withPolls(env: Env, rows: any[], mapped: any[], viewerId: string) {
  const pollIds = rows.filter((row: any) => row.poll_id).map((row: any) => row.poll_id);
  if (!pollIds.length) return mapped;
  const placeholders = pollIds.map(() => "?").join(",");
  const polls = await env.DB.prepare(`SELECT * FROM polls WHERE id IN (${placeholders})`).bind(...pollIds).all<any>();
  const votes = await env.DB.prepare(
    `SELECT poll_id, option_index, COUNT(*) AS n, MAX(CASE WHEN user_id = ? THEN 1 ELSE 0 END) AS mine
     FROM poll_votes WHERE poll_id IN (${placeholders})
     GROUP BY poll_id, option_index`,
  )
    .bind(viewerId, ...pollIds)
    .all<any>();

  const byId = new Map<string, any>();
  for (const poll of polls.results) {
    let options: string[] = [];
    try {
      options = JSON.parse(poll.options);
    } catch {
      options = [];
    }
    byId.set(poll.id, {
      id: poll.id,
      question: poll.question,
      options: options.map((text: string, index: number) => ({ index, text, votes: 0 })),
      multiple: !!poll.multiple,
      anonymous: !!poll.anonymous,
      closed: !!poll.closed,
      totalVotes: 0,
      myVotes: [] as number[],
    });
  }
  for (const vote of votes.results) {
    const poll = byId.get(vote.poll_id);
    if (!poll) continue;
    if (poll.options[vote.option_index]) poll.options[vote.option_index].votes = vote.n;
    poll.totalVotes += vote.n;
    if (vote.mine) poll.myVotes.push(vote.option_index);
  }
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].poll_id) mapped[i].poll = byId.get(rows[i].poll_id) ?? null;
  }
  return mapped;
}

async function withViews(env: Env, rows: any[], mapped: any[]) {
  if (!rows.length) return mapped;
  const ids = rows.map((row: any) => row.id);
  const placeholders = ids.map(() => "?").join(",");
  const result = await env.DB.prepare(
    `SELECT message_id, COUNT(*) AS n FROM message_views WHERE message_id IN (${placeholders}) GROUP BY message_id`,
  )
    .bind(...ids)
    .all<any>();
  const counts: Record<string, number> = {};
  for (const row of result.results) counts[row.message_id] = row.n;
  for (let i = 0; i < rows.length; i++) mapped[i].views = counts[rows[i].id] ?? 0;
  return mapped;
}

async function recordViews(env: Env, rows: any[], userId: string) {
  if (!rows.length) return;
  const statement = env.DB.prepare(
    "INSERT OR IGNORE INTO message_views (message_id, user_id, viewed_at) VALUES (?, ?, ?)",
  );
  await env.DB.batch(rows.slice(0, 100).map((row: any) => statement.bind(row.id, userId, Date.now())));
}

async function decorate(env: Env, rows: any[], mapped: any[], viewerId: string) {
  await withReactions(env, rows, mapped, viewerId);
  await withPolls(env, rows, mapped, viewerId);
  await withViews(env, rows, mapped);
  return mapped;
}

function mapMessage(row: any) {
  const deleted = !!row.deleted_at;
  return {
    seq: row.seq,
    id: row.id,
    chatId: row.chat_id,
    senderId: row.sender_id,
    senderName: row.sender_name,
    senderColor: row.sender_color,
    text: deleted ? "" : row.text,
    createdAt: row.created_at,
    clientId: row.client_id ?? null,
    deleted,
    editedAt: row.edited_at ?? null,
    forwardedFrom: row.forwarded_from ?? null,
    pinned: !!row.pinned,
    topicId: row.topic_id ?? null,
    poll: null as any,
    views: null as number | null,
    replyTo: row.reply_to_seq
      ? {
          seq: row.reply_to_seq,
          senderName: row.reply_sender_name ?? "",
          text: row.reply_deleted_at ? "消息已删除" : (row.reply_text ?? ""),
        }
      : null,
    media: !deleted && row.media_id
      ? {
          id: row.media_id,
          kind: row.media_kind,
          mime: row.media_mime,
          size: row.media_size,
          name: row.media_name ?? null,
          width: row.media_width ?? null,
          height: row.media_height ?? null,
          durationMs: row.media_duration ?? null,
          url: `/api/media/${row.media_id}`,
        }
      : null,
    reactions: [] as any[],
  };
}

const MESSAGE_SELECT = `
  SELECT m.seq, m.id, m.chat_id, m.sender_id, m.text, m.created_at, m.client_id, m.media_id,
         m.reply_to_seq, m.edited_at, m.deleted_at, m.forwarded_from, m.topic_id, m.poll_id,
         u.display_name AS sender_name, u.avatar_color AS sender_color,
         md.kind AS media_kind, md.mime AS media_mime, md.size AS media_size,
         md.file_name AS media_name, md.width AS media_width, md.height AS media_height,
         md.duration_ms AS media_duration,
         r.sender_id AS reply_sender_id, ru.display_name AS reply_sender_name,
         r.text AS reply_text, r.deleted_at AS reply_deleted_at,
         (SELECT 1 FROM pinned_messages p WHERE p.chat_id = m.chat_id AND p.message_seq = m.seq LIMIT 1) AS pinned
  FROM messages m
  JOIN users u ON u.id = m.sender_id
  LEFT JOIN media md ON md.id = m.media_id
  LEFT JOIN messages r ON r.chat_id = m.chat_id AND r.seq = m.reply_to_seq
  LEFT JOIN users ru ON ru.id = r.sender_id`;

async function withReactions(env: Env, rows: any[], mapped: any[], viewerId: string) {
  if (!rows.length) return mapped;
  const ids = rows.map((row: any) => row.id);
  const placeholders = ids.map(() => "?").join(",");
  const result = await env.DB.prepare(
    `SELECT message_id, emoji, COUNT(*) AS count, MAX(CASE WHEN user_id = ? THEN 1 ELSE 0 END) AS mine
     FROM message_reactions WHERE message_id IN (${placeholders})
     GROUP BY message_id, emoji ORDER BY MIN(created_at)`,
  )
    .bind(viewerId, ...ids)
    .all<any>();

  const grouped: Record<string, any[]> = {};
  for (const row of result.results) {
    (grouped[row.message_id] ??= []).push({
      emoji: row.emoji,
      count: row.count,
      me: !!row.mine,
    });
  }
  for (const message of mapped) message.reactions = grouped[message.id] ?? [];
  return mapped;
}

function mapMedia(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    kind: row.kind,
    mime: row.mime,
    size: row.size,
    name: row.file_name ?? null,
    width: row.width ?? null,
    height: row.height ?? null,
    durationMs: row.duration_ms ?? null,
    url: `/api/media/${row.id}`,
  };
}

function randomInviteCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes).map((b) => alphabet[b % alphabet.length]).join("");
}

function intField(value: unknown): number | null {
  const parsed = parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

async function loadChat(env: Env, chatId: string, viewerId: string) {
  const chat = await env.DB.prepare("SELECT * FROM chats WHERE id = ?").bind(chatId).first<any>();
  if (!chat) throw new ApiError(404, "会话不存在", "chat_not_found");
  const members = await env.DB.prepare(
    `SELECT u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at,
            m.role AS member_role, m.muted_until
     FROM chat_members m JOIN users u ON u.id = m.user_id WHERE m.chat_id = ? ORDER BY u.display_name`,
  )
    .bind(chatId)
    .all<any>();
  const last = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.chat_id = ? ORDER BY m.seq DESC LIMIT 1`)
    .bind(chatId)
    .first<any>();
  const me = await env.DB.prepare(
    "SELECT last_read_seq, role, pinned, archived, folder_id, wallpaper FROM chat_members WHERE chat_id = ? AND user_id = ?",
  )
    .bind(chatId, viewerId)
    .first<any>();
  const unread = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM messages WHERE chat_id = ? AND seq > ? AND sender_id != ?",
  )
    .bind(chatId, me?.last_read_seq ?? 0, viewerId)
    .first<any>();
  const otherRead = await env.DB.prepare(
    "SELECT MAX(last_read_seq) AS n FROM chat_members WHERE chat_id = ? AND user_id != ?",
  )
    .bind(chatId, viewerId)
    .first<any>();

  return {
    id: chat.id,
    type: chat.type,
    title: chat.title,
    description: chat.description ?? null,
    announcement: chat.announcement ?? null,
    photoUrl: chat.photo_url ?? null,
    joinMode: chat.join_mode ?? "invite",
    slowMode: chat.slow_mode ?? 0,
    historyVisible: (chat.history_visible ?? 1) === 1,
    topicsEnabled: (chat.topics_enabled ?? 0) === 1,
    username: chat.username ?? null,
    isPublic: (chat.is_public ?? 0) === 1,
    discussionChatId: chat.discussion_chat_id ?? null,
    subscriberCount: members.results.length,
    autoDeleteSeconds: chat.auto_delete_seconds ?? 0,
    createdAt: chat.created_at,
    lastReadSeq: me?.last_read_seq ?? 0,
    otherReadSeq: otherRead?.n ?? 0,
    unread: unread?.n ?? 0,
    myRole: me?.role ?? "member",
    pinned: (me?.pinned ?? 0) === 1,
    archived: (me?.archived ?? 0) === 1,
    folderId: me?.folder_id ?? null,
    wallpaper: me?.wallpaper ?? null,
    lastMessage: last ? mapMessage(last) : null,
    members: members.results.map((m: any) => ({
      id: m.id,
      username: m.username,
      displayName: m.display_name,
      avatarColor: m.avatar_color,
      role: m.role,
      chatRole: m.member_role ?? "member",
      mutedUntil: m.muted_until ?? null,
      lastSeenAt: m.last_seen_at,
    })),
  };
}

async function chatRole(env: Env, chatId: string, userId: string): Promise<string | null> {
  const row = await env.DB.prepare("SELECT role FROM chat_members WHERE chat_id = ? AND user_id = ?")
    .bind(chatId, userId)
    .first<any>();
  return row?.role ?? null;
}

async function requireManager(env: Env, chatId: string, userId: string): Promise<string> {
  const role = await chatRole(env, chatId, userId);
  if (!role) throw new ApiError(403, "你不是该会话的成员", "forbidden");
  if (role !== "owner" && role !== "admin") throw new ApiError(403, "需要管理员权限", "forbidden");
  return role;
}

async function getChatRow(env: Env, chatId: string): Promise<any> {
  const chat = await env.DB.prepare("SELECT * FROM chats WHERE id = ?").bind(chatId).first<any>();
  if (!chat) throw new ApiError(404, "会话不存在", "chat_not_found");
  return chat;
}

async function createChat(
  env: Env,
  creatorId: string,
  memberIds: string[],
  type: "direct" | "group" | "saved" | "channel",
  title: string | null,
): Promise<string> {
  const id = crypto.randomUUID();
  const now = Date.now();
  const unique = [...new Set([creatorId, ...memberIds])];
  const stmts = [
    env.DB.prepare("INSERT INTO chats (id, type, title, created_at, created_by) VALUES (?, ?, ?, ?, ?)").bind(
      id,
      type,
      title,
      now,
      creatorId,
    ),
    ...unique.map((uid) =>
      env.DB.prepare(
        "INSERT INTO chat_members (chat_id, user_id, joined_at, last_read_seq, role) VALUES (?, ?, ?, 0, ?)",
      ).bind(id, uid, now, uid === creatorId ? "owner" : "member"),
    ),
  ];
  await env.DB.batch(stmts);
  return id;
}

export async function handleRequest(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  path: string,
): Promise<Response> {
  const method = request.method.toUpperCase();
  const seg = path.split("/").filter(Boolean); // ["api", ...]

  // ---------------- health ----------------
  if (method === "GET" && path === "/api/health") {
    return json({ ok: true, service: "tgchat", time: new Date().toISOString() });
  }

  // ---------------- media ----------------
  if (seg[0] === "api" && seg[1] === "media" && seg.length === 3 && method === "GET") {
    const url = new URL(request.url);
    const tokenParam = url.searchParams.get("token");
    let viewer: UserRow | null = null;
    if (tokenParam) {
      const tokenHash = await sha256Hex(tokenParam);
      viewer = await env.DB.prepare(
        "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? AND s.expires_at > ?",
      )
        .bind(tokenHash, Date.now())
        .first<UserRow>();
    } else {
      viewer = await authenticate(request, env);
    }
    if (!viewer) throw new ApiError(401, "登录已过期，请重新登录", "unauthorized");

    const row = await env.DB.prepare("SELECT * FROM media WHERE id = ?").bind(seg[2]).first<any>();
    if (!row) throw new ApiError(404, "文件不存在", "not_found");
    await assertMember(env, row.chat_id, viewer.id);

    const hasRange = request.headers.has("range");
    const object = hasRange
      ? await env.MEDIA.get(row.object_key, { range: request.headers })
      : await env.MEDIA.get(row.object_key);
    if (!object) throw new ApiError(404, "文件不存在", "not_found");

    const headers = new Headers();
    headers.set("content-type", row.mime || "application/octet-stream");
    headers.set("accept-ranges", "bytes");
    headers.set("cache-control", "private, max-age=604800");
    const disposition = row.kind === "file" ? "attachment" : "inline";
    const safeName = String(row.file_name || row.id).replace(/["\\r\n]/g, "");
    headers.set("content-disposition", `${disposition}; filename="${safeName}"`);

    let status = 200;
    const range = (object as any).range as { offset?: number; length?: number } | undefined;
    if (hasRange && range && typeof range.offset === "number") {
      const start = range.offset;
      const length = range.length ?? object.size - start;
      const end = start + length - 1;
      headers.set("content-range", `bytes ${start}-${end}/${object.size}`);
      headers.set("content-length", String(length));
      status = 206;
    } else {
      headers.set("content-length", String(object.size));
    }

    return new Response(object.body, { status, headers });
  }

  // ---------------- auth ----------------
  if (method === "POST" && path === "/api/auth/login") {
    const body = await readBody(request);
    const name = typeof body.username === "string" ? body.username.trim() : "";
    const pass = typeof body.password === "string" ? body.password : "";
    if (!name || !pass) throw new ApiError(400, "请输入用户名和密码", "invalid_input");

    const user = await env.DB.prepare("SELECT * FROM users WHERE username = ?").bind(name).first<UserRow>();
    if (!user || !(await verifyPassword(pass, user.password_hash))) {
      throw new ApiError(401, "用户名或密码错误", "bad_credentials");
    }

    const token = randomHex(32);
    const days = parseInt(env.SESSION_TTL_DAYS ?? "30", 10) || 30;
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?").bind(now),
      env.DB.prepare(
        "INSERT INTO sessions (token_hash, user_id, created_at, expires_at, device_name, platform, last_active_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ).bind(
        await sha256Hex(token),
        user.id,
        now,
        now + days * 24 * 60 * 60 * 1000,
        (request.headers.get("x-device-name") ?? "iOS").slice(0, 64),
        (request.headers.get("x-platform") ?? "ios").slice(0, 32),
        now,
      ),
      env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(now, user.id),
    ]);

    return json({ token, user: publicUser(user) });
  }

  if (method === "POST" && path === "/api/auth/logout") {
    const me = await authenticate(request, env);
    const header = request.headers.get("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header.trim());
    if (match) {
      await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256Hex(match[1])).run();
    }
    return ok({ ok: true, userId: me.id });
  }

  if (method === "GET" && path === "/api/sessions") {
    const me = await authenticate(request, env);
    const header = request.headers.get("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header.trim());
    const currentHash = match ? await sha256Hex(match[1]) : "";
    const rows = await env.DB.prepare(
      "SELECT token_hash, created_at, expires_at, device_name, platform, last_active_at FROM sessions WHERE user_id = ? AND expires_at > ? ORDER BY created_at DESC",
    )
      .bind(me.id, Date.now())
      .all<any>();
    return json({
      sessions: rows.results.map((s: any) => ({
        id: s.token_hash,
        device: s.device_name ?? "未知设备",
        platform: s.platform ?? "",
        createdAt: s.created_at,
        lastActiveAt: s.last_active_at ?? s.created_at,
        current: s.token_hash === currentHash,
      })),
    });
  }

  if (method === "DELETE" && path === "/api/sessions") {
    const me = await authenticate(request, env);
    const header = request.headers.get("authorization") ?? "";
    const match = /^Bearer\s+(.+)$/i.exec(header.trim());
    const currentHash = match ? await sha256Hex(match[1]) : "";
    await env.DB.prepare("DELETE FROM sessions WHERE user_id = ? AND token_hash != ?").bind(me.id, currentHash).run();
    return ok({ ok: true });
  }

  if (method === "DELETE" && seg.length === 3 && seg[0] === "api" && seg[1] === "sessions") {
    const me = await authenticate(request, env);
    await env.DB.prepare("DELETE FROM sessions WHERE user_id = ? AND token_hash = ?")
      .bind(me.id, seg[2])
      .run();
    return ok({ ok: true });
  }

  if (method === "GET" && path === "/api/blocks") {
    const me = await authenticate(request, env);
    const rows = await env.DB.prepare(
      `SELECT u.* FROM blocks b JOIN users u ON u.id = b.blocked_id WHERE b.blocker_id = ? ORDER BY b.created_at DESC`,
    )
      .bind(me.id)
      .all<any>();
    return json({ users: rows.results.map(publicUser) });
  }

  if (seg.length === 4 && seg[0] === "api" && seg[1] === "users" && seg[3] === "block" && (method === "POST" || method === "DELETE")) {
    const me = await authenticate(request, env);
    const targetId = seg[2];
    if (targetId === me.id) throw new ApiError(400, "不能屏蔽自己", "invalid_input");
    const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(targetId).first();
    if (!target) throw new ApiError(404, "用户不存在", "not_found");
    if (method === "POST") {
      await env.DB.prepare("INSERT OR IGNORE INTO blocks (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)")
        .bind(me.id, targetId, Date.now())
        .run();
    } else {
      await env.DB.prepare("DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?").bind(me.id, targetId).run();
    }
    return ok({ ok: true });
  }

  // ---------------- me ----------------
  if (method === "GET" && path === "/api/me") {
    return json({ user: publicUser(await authenticate(request, env)) });
  }

  if (method === "PATCH" && path === "/api/me") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const displayName =
      typeof body.displayName === "string" && body.displayName.trim()
        ? text(body.displayName, "displayName", 1, 64)
        : me.display_name;
    const avatarColor =
      typeof body.avatarColor === "string" && /^#[0-9a-fA-F]{6}$/.test(body.avatarColor)
        ? body.avatarColor
        : me.avatar_color;
    const bio = typeof body.bio === "string" ? body.bio.slice(0, 256) : (me.bio ?? null);
    const visibility =
      typeof body.lastSeenVisibility === "string" && ["everyone", "contacts", "nobody"].includes(body.lastSeenVisibility)
        ? body.lastSeenVisibility
        : (me.last_seen_visibility ?? "everyone");
    const receipts =
      body.readReceipts === undefined ? (me.read_receipts ?? 1) : body.readReceipts ? 1 : 0;

    await env.DB.prepare(
      "UPDATE users SET display_name = ?, avatar_color = ?, bio = ?, last_seen_visibility = ?, read_receipts = ? WHERE id = ?",
    )
      .bind(displayName, avatarColor, bio, visibility, receipts, me.id)
      .run();

    return json({
      user: {
        ...publicUser(me),
        displayName,
        avatarColor,
        bio,
        lastSeenVisibility: visibility,
        readReceipts: receipts === 1,
      },
    });
  }

  // ---------------- users directory ----------------
  if (method === "GET" && path === "/api/users") {
    const me = await authenticate(request, env);
    const q = new URL(request.url).searchParams.get("query")?.trim() ?? "";
    const like = `%${q}%`;
    const rows = await env.DB.prepare(
      `SELECT * FROM users WHERE id != ? AND (username LIKE ? OR display_name LIKE ?)
       ORDER BY display_name COLLATE NOCASE LIMIT 100`,
    )
      .bind(me.id, like, like)
      .all<UserRow>();
    return json({ users: rows.results.map(publicUser) });
  }

  // ---------------- chats ----------------
  if (method === "GET" && path === "/api/chats") {
    const me = await authenticate(request, env);
    ctx.waitUntil(env.DB.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").bind(Date.now(), me.id).run());

    const rows = await env.DB.prepare(
      `SELECT c.id, c.type, c.title, c.description, c.announcement, c.photo_url, c.join_mode,
              c.slow_mode, c.history_visible, c.topics_enabled,
              c.username, c.is_public, c.discussion_chat_id, c.auto_delete_seconds,
              (SELECT COUNT(*) FROM chat_members cmc WHERE cmc.chat_id = c.id) AS subscriber_count,
              c.created_at, cm.last_read_seq, cm.role AS my_role,
              cm.pinned AS my_pinned, cm.archived AS my_archived,
              cm.folder_id AS my_folder, cm.wallpaper AS my_wallpaper,
              (SELECT MAX(cm2.last_read_seq) FROM chat_members cm2 WHERE cm2.chat_id = c.id AND cm2.user_id != ?) AS other_read_seq,
              (SELECT COUNT(*) FROM messages m WHERE m.chat_id = c.id AND m.seq > cm.last_read_seq AND m.sender_id != ?) AS unread
       FROM chats c JOIN chat_members cm ON cm.chat_id = c.id
       WHERE cm.user_id = ?
       ORDER BY cm.pinned DESC, COALESCE((SELECT MAX(seq) FROM messages m WHERE m.chat_id = c.id), 0) DESC, c.created_at DESC`,
    )
      .bind(me.id, me.id, me.id)
      .all<any>();

    const ids = rows.results.map((r: any) => r.id);
    let membersByChat: Record<string, any[]> = {};
    if (ids.length > 0) {
      const placeholders = ids.map(() => "?").join(",");
      const members = await env.DB.prepare(
        `SELECT m.chat_id, u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at,
                m.role AS member_role, m.muted_until
         FROM chat_members m JOIN users u ON u.id = m.user_id
         WHERE m.chat_id IN (${placeholders}) ORDER BY u.display_name`,
      )
        .bind(...ids)
        .all<any>();
      for (const m of members.results) {
        (membersByChat[m.chat_id] ??= []).push({
          id: m.id,
          username: m.username,
          displayName: m.display_name,
          avatarColor: m.avatar_color,
          role: m.role,
          chatRole: m.member_role ?? "member",
          mutedUntil: m.muted_until ?? null,
          lastSeenAt: m.last_seen_at,
        });
      }
    }

    const lastMessages = await env.DB.prepare(
      `SELECT m.seq, m.id, m.chat_id, m.sender_id, m.text, m.created_at, m.client_id,
              u.display_name AS sender_name, u.avatar_color AS sender_color
       FROM messages m JOIN users u ON u.id = m.sender_id
       WHERE m.seq IN (SELECT MAX(seq) FROM messages WHERE chat_id IN (${
         ids.length ? ids.map(() => "?").join(",") : "''"
       }) GROUP BY chat_id)`,
    )
      .bind(...ids)
      .all<any>();

    const lastByChat: Record<string, any> = {};
    for (const m of lastMessages.results) lastByChat[m.chat_id] = mapMessage(m);

    const chats = rows.results.map((c: any) => ({
      id: c.id,
      type: c.type,
      title: c.title,
      description: c.description ?? null,
      announcement: c.announcement ?? null,
      photoUrl: c.photo_url ?? null,
      joinMode: c.join_mode ?? "invite",
      slowMode: c.slow_mode ?? 0,
      historyVisible: (c.history_visible ?? 1) === 1,
      topicsEnabled: (c.topics_enabled ?? 0) === 1,
      username: c.username ?? null,
      isPublic: (c.is_public ?? 0) === 1,
      discussionChatId: c.discussion_chat_id ?? null,
      subscriberCount: c.subscriber_count ?? 0,
      autoDeleteSeconds: c.auto_delete_seconds ?? 0,
      createdAt: c.created_at,
      myRole: c.my_role ?? "member",
      pinned: (c.my_pinned ?? 0) === 1,
      archived: (c.my_archived ?? 0) === 1,
      folderId: c.my_folder ?? null,
      wallpaper: c.my_wallpaper ?? null,
      lastReadSeq: c.last_read_seq,
      otherReadSeq: c.other_read_seq ?? 0,
      unread: c.unread,
      lastMessage: lastByChat[c.id] ?? null,
      members: membersByChat[c.id] ?? [],
    }));

    return json({ chats });
  }

  if (method === "POST" && path === "/api/chats/batch") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const action = typeof body.action === "string" ? body.action : "";
    const chatIds = Array.isArray(body.chatIds) ? body.chatIds.filter((id: unknown) => typeof id === "string") : [];
    if (!chatIds.length) throw new ApiError(400, "缺少 chatIds", "invalid_input");
    const placeholders = chatIds.map(() => "?").join(",");

    if (action === "pin" || action === "unpin") {
      await env.DB.prepare(
        `UPDATE chat_members SET pinned = ? WHERE user_id = ? AND chat_id IN (${placeholders})`,
      )
        .bind(action === "pin" ? 1 : 0, me.id, ...chatIds)
        .run();
    } else if (action === "archive" || action === "unarchive") {
      await env.DB.prepare(
        `UPDATE chat_members SET archived = ? WHERE user_id = ? AND chat_id IN (${placeholders})`,
      )
        .bind(action === "archive" ? 1 : 0, me.id, ...chatIds)
        .run();
    } else if (action === "read") {
      for (const chatId of chatIds) {
        const max = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS s FROM messages WHERE chat_id = ?")
          .bind(chatId)
          .first<any>();
        await env.DB.prepare("UPDATE chat_members SET last_read_seq = ? WHERE user_id = ? AND chat_id = ?")
          .bind(max?.s ?? 0, me.id, chatId)
          .run();
      }
    } else if (action === "delete") {
      await env.DB.prepare(
        `DELETE FROM chat_members WHERE user_id = ? AND chat_id IN (${placeholders})`,
      )
        .bind(me.id, ...chatIds)
        .run();
      await env.DB.prepare(
        `DELETE FROM chats WHERE id IN (${placeholders}) AND id NOT IN (SELECT chat_id FROM chat_members)`,
      )
        .bind(...chatIds)
        .run();
    } else {
      throw new ApiError(400, "未知操作", "invalid_input");
    }
    return json({ ok: true, action, count: chatIds.length });
  }

  if (method === "POST" && path === "/api/saved") {
    const me = await authenticate(request, env);
    const existing = await env.DB.prepare(
      `SELECT c.id FROM chats c JOIN chat_members cm ON cm.chat_id = c.id
       WHERE c.type = 'saved' AND cm.user_id = ? LIMIT 1`,
    )
      .bind(me.id)
      .first<any>();
    if (existing) return json({ chat: await loadChat(env, existing.id, me.id) });
    const id = await createChat(env, me.id, [], "saved", "收藏夹");
    return json({ chat: await loadChat(env, id, me.id) }, 201);
  }

  if (method === "GET" && path === "/api/search") {
    const me = await authenticate(request, env);
    const params = new URL(request.url).searchParams;
    const query = (params.get("q") ?? "").trim();
    const kind = params.get("kind") ?? "";
    const chatFilter = params.get("chatId") ?? "";
    if (!query && !chatFilter) return json({ messages: [] });

    const escaped = query.replace(/[\\%_]/g, (ch) => `\\${ch}`);
    const conditions: string[] = ["m.deleted_at IS NULL", "cm.user_id = ?"];
    const bindings: unknown[] = [me.id];
    if (query) {
      conditions.push("m.text LIKE ? ESCAPE '\\'");
      bindings.push(`%${escaped}%`);
    }
    if (chatFilter) {
      conditions.push("m.chat_id = ?");
      bindings.push(chatFilter);
    }
    if (kind === "media") {
      conditions.push("m.media_id IS NOT NULL");
    } else if (kind === "text") {
      conditions.push("m.media_id IS NULL");
    } else if (kind === "links") {
      conditions.push("m.text LIKE '%http%'");
    }

    const rows = await env.DB.prepare(
      `${MESSAGE_SELECT} JOIN chat_members cm ON cm.chat_id = m.chat_id
       WHERE ${conditions.join(" AND ")} ORDER BY m.seq DESC LIMIT 60`,
    )
      .bind(...bindings)
      .all<any>();
    const mapped = rows.results.map(mapMessage);
    await decorate(env, rows.results, mapped, me.id);
    return json({ messages: mapped });
  }

  if (seg.length === 2 && seg[0] === "api" && seg[1] === "folders") {
    const me = await authenticate(request, env);
    if (method === "GET") {
      const rows = await env.DB.prepare("SELECT * FROM folders WHERE user_id = ? ORDER BY position, created_at")
        .bind(me.id)
        .all<any>();
      return json({
        folders: rows.results.map((f: any) => ({ id: f.id, name: f.name, position: f.position })),
      });
    }
    if (method === "POST") {
      const body = await readBody(request);
      const name = text(body.name, "文件夹名称", 1, 32);
      const id = crypto.randomUUID();
      await env.DB.prepare("INSERT INTO folders (id, user_id, name, position, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(id, me.id, name, Date.now(), Date.now())
        .run();
      return json({ folder: { id, name, position: 0 } }, 201);
    }
  }

  if (seg.length === 3 && seg[0] === "api" && seg[1] === "folders" && (method === "PATCH" || method === "DELETE")) {
    const me = await authenticate(request, env);
    const folderId = seg[2];
    if (method === "DELETE") {
      await env.DB.prepare("DELETE FROM folders WHERE id = ? AND user_id = ?").bind(folderId, me.id).run();
      await env.DB.prepare("UPDATE chat_members SET folder_id = NULL WHERE user_id = ? AND folder_id = ?")
        .bind(me.id, folderId)
        .run();
      return ok({ ok: true });
    }
    const body = await readBody(request);
    const name = text(body.name, "文件夹名称", 1, 32);
    await env.DB.prepare("UPDATE folders SET name = ? WHERE id = ? AND user_id = ?")
      .bind(name, folderId, me.id)
      .run();
    return ok({ ok: true });
  }

  if (method === "PATCH" && seg.length === 4 && seg[0] === "api" && seg[1] === "chats" && seg[3] === "folder") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const folderId = typeof body.folderId === "string" && body.folderId ? body.folderId : null;
    await env.DB.prepare("UPDATE chat_members SET folder_id = ? WHERE chat_id = ? AND user_id = ?")
      .bind(folderId, seg[2], me.id)
      .run();
    return ok({ ok: true });
  }

  if (method === "POST" && path === "/api/channels") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const title = text(body.title, "频道名称", 1, 64);
    const usernameRaw = typeof body.username === "string" ? body.username.trim().toLowerCase() : "";
    if (usernameRaw && !/^[a-z0-9_]{4,32}$/.test(usernameRaw)) {
      throw new ApiError(400, "用户名需为 4-32 位小写字母、数字或下划线", "invalid_username");
    }
    if (usernameRaw) {
      const taken = await env.DB.prepare("SELECT 1 AS x FROM chats WHERE username = ?").bind(usernameRaw).first();
      if (taken) throw new ApiError(409, "用户名已被占用", "username_taken");
    }

    const id = await createChat(env, me.id, [], "channel", title);
    if (usernameRaw) {
      await env.DB.prepare("UPDATE chats SET username = ?, is_public = 1 WHERE id = ?").bind(usernameRaw, id).run();
    }
    if (typeof body.description === "string" && body.description.trim()) {
      await env.DB.prepare("UPDATE chats SET description = ? WHERE id = ?")
        .bind(body.description.trim().slice(0, 512), id)
        .run();
    }
    return json({ chat: await loadChat(env, id, me.id) }, 201);
  }

  if (method === "GET" && path === "/api/channels/discover") {
    const me = await authenticate(request, env);
    const query = (new URL(request.url).searchParams.get("q") ?? "").trim();
    const like = `%${query}%`;
    const rows = await env.DB.prepare(
      `SELECT c.id, c.title, c.username, c.description, c.created_at,
              (SELECT COUNT(*) FROM chat_members cm WHERE cm.chat_id = c.id) AS subs,
              (SELECT 1 FROM chat_members cm WHERE cm.chat_id = c.id AND cm.user_id = ? LIMIT 1) AS joined
       FROM chats c
       WHERE c.type = 'channel' AND c.is_public = 1
         AND (c.username LIKE ? OR c.title LIKE ?)
       ORDER BY subs DESC LIMIT 50`,
    )
      .bind(me.id, like, like)
      .all<any>();
    return json({
      channels: rows.results.map((c: any) => ({
        id: c.id,
        title: c.title,
        username: c.username,
        description: c.description ?? null,
        subscriberCount: c.subs ?? 0,
        joined: !!c.joined,
      })),
    });
  }

  if (method === "POST" && path === "/api/chats") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const memberIds: string[] = Array.isArray(body.memberIds)
      ? body.memberIds.filter((x: unknown) => typeof x === "string" && x)
      : [];
    if (memberIds.length === 0) throw new ApiError(400, "请选择至少一位联系人", "invalid_input");

    const ids = [...new Set(memberIds.filter((id) => id !== me.id))];
    if (ids.length === 0) throw new ApiError(400, "不能与自己创建会话", "invalid_input");
    const found = await env.DB.prepare(
      `SELECT id FROM users WHERE id IN (${ids.map(() => "?").join(",")})`,
    )
      .bind(...ids)
      .all<any>();
    if (found.results.length !== ids.length) throw new ApiError(400, "存在无效用户", "invalid_input");

    const wantsGroup = ids.length > 1 || body.type === "group";

    if (!wantsGroup) {
      const existing = await env.DB.prepare(
        `SELECT c.id FROM chats c
         JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
         JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
         WHERE c.type = 'direct' LIMIT 1`,
      )
        .bind(me.id, ids[0])
        .first<any>();
      if (existing) return json({ chat: await loadChat(env, existing.id, me.id), created: false });
      const chatId = await createChat(env, me.id, ids, "direct", null);
      return json({ chat: await loadChat(env, chatId, me.id), created: true }, 201);
    }

    const title = typeof body.title === "string" && body.title.trim() ? text(body.title, "title", 1, 64) : "群聊";
    const chatId = await createChat(env, me.id, ids, "group", title);
    if (typeof body.description === "string" && body.description.trim()) {
      await env.DB.prepare("UPDATE chats SET description = ? WHERE id = ?")
        .bind(body.description.trim().slice(0, 512), chatId)
        .run();
    }
    return json({ chat: await loadChat(env, chatId, me.id), created: true }, 201);
  }

  if (method === "POST" && seg.length === 3 && seg[0] === "api" && seg[1] === "chats" && seg[2] === "join") {
    const me = await authenticate(request, env);
    const body = await readBody(request);
    const code = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
    if (!code) throw new ApiError(400, "缺少邀请码", "invalid_input");

    const invite = await env.DB.prepare("SELECT * FROM chat_invites WHERE code = ?").bind(code).first<any>();
    if (!invite || invite.revoked) throw new ApiError(404, "邀请链接无效", "invalid_invite");
    if (invite.expires_at && invite.expires_at < Date.now()) {
      throw new ApiError(410, "邀请链接已过期", "expired_invite");
    }

    const exists = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
      .bind(invite.chat_id, me.id)
      .first();
    if (!exists) {
      const maxSeq = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS s FROM messages WHERE chat_id = ?")
        .bind(invite.chat_id)
        .first<any>();
      await env.DB.prepare(
        "INSERT INTO chat_members (chat_id, user_id, joined_at, last_read_seq, role, joined_seq) VALUES (?, ?, ?, 0, 'member', ?)",
      )
        .bind(invite.chat_id, me.id, Date.now(), maxSeq?.s ?? 0)
        .run();
    }
    return json({ chat: await loadChat(env, invite.chat_id, me.id) });
  }

  if (method === "PATCH" && seg.length === 3 && seg[0] === "api" && seg[1] === "chats") {
    const me = await authenticate(request, env);
    const chatId = seg[2];
    await requireManager(env, chatId, me.id);
    const body = await readBody(request);

    const fields: string[] = [];
    const values: unknown[] = [];
    if (typeof body.title === "string" && body.title.trim()) {
      fields.push("title = ?");
      values.push(text(body.title, "群名称", 1, 64));
    }
    if (typeof body.description === "string") {
      fields.push("description = ?");
      values.push(body.description.slice(0, 512));
    }
    if (typeof body.announcement === "string") {
      fields.push("announcement = ?");
      values.push(body.announcement.slice(0, 1024));
    }
    if (typeof body.photoUrl === "string") {
      fields.push("photo_url = ?");
      values.push(body.photoUrl.slice(0, 512));
    }
    if (typeof body.joinMode === "string" && ["invite", "open", "approval"].includes(body.joinMode)) {
      fields.push("join_mode = ?");
      values.push(body.joinMode);
    }
    if (typeof body.slowMode === "number") {
      fields.push("slow_mode = ?");
      values.push(Math.max(0, Math.min(3600, Math.floor(body.slowMode))));
    }
    if (typeof body.historyVisible === "boolean") {
      fields.push("history_visible = ?");
      values.push(body.historyVisible ? 1 : 0);
    }
    if (typeof body.topicsEnabled === "boolean") {
      fields.push("topics_enabled = ?");
      values.push(body.topicsEnabled ? 1 : 0);
    }
    if (typeof body.autoDeleteSeconds === "number") {
      fields.push("auto_delete_seconds = ?");
      values.push(Math.max(0, Math.min(604800, Math.floor(body.autoDeleteSeconds))));
    }
    if (typeof body.username === "string") {
      const username = body.username.trim().toLowerCase();
      if (username && !/^[a-z0-9_]{4,32}$/.test(username)) {
        throw new ApiError(400, "用户名需为 4-32 位小写字母、数字或下划线", "invalid_username");
      }
      if (username) {
        const taken = await env.DB.prepare("SELECT id FROM chats WHERE username = ? AND id != ?")
          .bind(username, chatId)
          .first();
        if (taken) throw new ApiError(409, "用户名已被占用", "username_taken");
        fields.push("username = ?", "is_public = 1");
        values.push(username);
      } else {
        fields.push("username = NULL", "is_public = 0");
      }
    }
    if (typeof body.discussionChatId === "string") {
      const discussion = body.discussionChatId;
      if (discussion) {
        const target = await env.DB.prepare("SELECT type FROM chats WHERE id = ?").bind(discussion).first<any>();
        if (!target || target.type !== "group") {
          throw new ApiError(400, "讨论组必须是群组", "invalid_input");
        }
      }
      fields.push("discussion_chat_id = ?");
      values.push(discussion || null);
    }
    if (!fields.length) throw new ApiError(400, "没有可更新的字段", "invalid_input");

    values.push(chatId);
    await env.DB.prepare(`UPDATE chats SET ${fields.join(", ")} WHERE id = ?`).bind(...values).run();
    return json({ chat: await loadChat(env, chatId, me.id) });
  }

  if (method === "DELETE" && seg.length === 3 && seg[0] === "api" && seg[1] === "chats") {
    const me = await authenticate(request, env);
    const chatId = seg[2];
    const chat = await getChatRow(env, chatId);
    const role = await chatRole(env, chatId, me.id);
    if (chat.type !== "group") throw new ApiError(400, "一对一聊天不能解散", "invalid_input");
    if (role !== "owner") throw new ApiError(403, "只有群主可以解散群组", "forbidden");

    await env.DB.batch([
      env.DB.prepare("DELETE FROM messages WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM media WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM chat_members WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM chat_invites WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM pinned_messages WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM message_reactions WHERE chat_id = ?").bind(chatId),
      env.DB.prepare("DELETE FROM chats WHERE id = ?").bind(chatId),
    ]);
    return ok({ ok: true });
  }

  // ---------------- single chat ----------------
  if (seg.length >= 4 && seg[0] === "api" && seg[1] === "chats") {
    const chatId = seg[2];

    if (method === "POST" && seg.length === 4 && seg[3] === "members") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      const chat = await getChatRow(env, chatId);
      if (chat.type !== "group") throw new ApiError(400, "只有群组可以添加成员", "invalid_input");

      const body = await readBody(request);
      const userId = typeof body.userId === "string" ? body.userId : "";
      if (!userId) throw new ApiError(400, "缺少 userId", "invalid_input");
      const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userId).first();
      if (!target) throw new ApiError(404, "用户不存在", "not_found");

      const exists = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
        .bind(chatId, userId)
        .first();
      if (!exists) {
        const maxSeq = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS s FROM messages WHERE chat_id = ?")
          .bind(chatId)
          .first<any>();
        await env.DB.prepare(
          "INSERT INTO chat_members (chat_id, user_id, joined_at, last_read_seq, role, joined_seq) VALUES (?, ?, ?, 0, 'member', ?)",
        )
          .bind(chatId, userId, Date.now(), maxSeq?.s ?? 0)
          .run();
      }
      return json({ chat: await loadChat(env, chatId, me.id) });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "leave") {
      const me = await authenticate(request, env);
      const role = await chatRole(env, chatId, me.id);
      if (!role) throw new ApiError(403, "你不是该会话的成员", "forbidden");
      if (role === "owner") {
        const next = await env.DB.prepare(
          "SELECT user_id FROM chat_members WHERE chat_id = ? AND user_id != ? ORDER BY joined_at LIMIT 1",
        )
          .bind(chatId, me.id)
          .first<any>();
        if (next) {
          await env.DB.prepare("UPDATE chat_members SET role = 'owner' WHERE chat_id = ? AND user_id = ?")
            .bind(chatId, next.user_id)
            .run();
        }
      }
      await env.DB.prepare("DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?").bind(chatId, me.id).run();
      return ok({ ok: true });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "invite") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      const chat = await getChatRow(env, chatId);
      if (chat.type !== "group") throw new ApiError(400, "只有群组可以创建邀请链接", "invalid_input");

      const body = await readBody(request);
      const expiresInDays = Number(body.expiresInDays ?? 0);
      const code = randomInviteCode();
      await env.DB.prepare(
        "INSERT INTO chat_invites (code, chat_id, created_by, created_at, expires_at, revoked) VALUES (?, ?, ?, ?, ?, 0)",
      )
        .bind(code, chatId, me.id, Date.now(), expiresInDays > 0 ? Date.now() + expiresInDays * 86_400_000 : null)
        .run();
      return json({ code, link: `tgchat://join/${code}` });
    }

    if (method === "DELETE" && seg.length === 5 && seg[3] === "invite") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      await env.DB.prepare("UPDATE chat_invites SET revoked = 1 WHERE chat_id = ? AND code = ?")
        .bind(chatId, seg[4])
        .run();
      return ok({ ok: true });
    }

    if ((method === "PATCH" || method === "DELETE") && seg.length === 5 && seg[3] === "members") {
      const me = await authenticate(request, env);
      const targetId = seg[4];
      const myRole = await chatRole(env, chatId, me.id);
      if (!myRole) throw new ApiError(403, "你不是该会话的成员", "forbidden");

      if (method === "DELETE") {
        if (targetId !== me.id) {
          await requireManager(env, chatId, me.id);
          const targetRole = await chatRole(env, chatId, targetId);
          if (targetRole === "owner") throw new ApiError(403, "不能移除群主", "forbidden");
        }
        await env.DB.prepare("DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?")
          .bind(chatId, targetId)
          .run();
        return ok({ ok: true });
      }

      const body = await readBody(request);
      if (typeof body.role === "string") {
        if (myRole !== "owner") throw new ApiError(403, "只有群主可以设置管理员", "forbidden");
        const role = body.role === "admin" ? "admin" : "member";
        const targetRole = await chatRole(env, chatId, targetId);
        if (targetRole === "owner") throw new ApiError(403, "不能修改群主角色", "forbidden");
        await env.DB.prepare("UPDATE chat_members SET role = ? WHERE chat_id = ? AND user_id = ?")
          .bind(role, chatId, targetId)
          .run();
      }
      if (body.mutedUntil !== undefined) {
        await requireManager(env, chatId, me.id);
        const targetRole = await chatRole(env, chatId, targetId);
        if (targetRole === "owner") throw new ApiError(403, "不能禁言群主", "forbidden");
        const until = Number(body.mutedUntil) || 0;
        await env.DB.prepare("UPDATE chat_members SET muted_until = ? WHERE chat_id = ? AND user_id = ?")
          .bind(until, chatId, targetId)
          .run();
      }
      return json({ chat: await loadChat(env, chatId, me.id) });
    }

    if ((method === "POST" || method === "DELETE") && seg.length === 4 && seg[3] === "subscribe") {
      const me = await authenticate(request, env);
      const chat = await getChatRow(env, chatId);
      if (chat.type !== "channel") throw new ApiError(400, "不是频道", "invalid_input");

      if (method === "POST") {
        if (chat.is_public !== 1) {
          const invite = await env.DB.prepare("SELECT 1 AS x FROM chat_invites WHERE chat_id = ? AND revoked = 0")
            .bind(chatId)
            .first();
          if (!invite) throw new ApiError(403, "私有频道需要邀请链接", "forbidden");
        }
        const exists = await env.DB.prepare("SELECT 1 AS x FROM chat_members WHERE chat_id = ? AND user_id = ?")
          .bind(chatId, me.id)
          .first();
        if (!exists) {
          const maxSeq = await env.DB.prepare("SELECT COALESCE(MAX(seq), 0) AS s FROM messages WHERE chat_id = ?")
            .bind(chatId)
            .first<any>();
          await env.DB.prepare(
            "INSERT INTO chat_members (chat_id, user_id, joined_at, last_read_seq, role, joined_seq) VALUES (?, ?, ?, 0, 'member', ?)",
          )
            .bind(chatId, me.id, Date.now(), maxSeq?.s ?? 0)
            .run();
        }
        return json({ chat: await loadChat(env, chatId, me.id) });
      }

      const role = await chatRole(env, chatId, me.id);
      if (role === "owner") throw new ApiError(400, "频道主不能退订自己的频道", "invalid_input");
      await env.DB.prepare("DELETE FROM chat_members WHERE chat_id = ? AND user_id = ?").bind(chatId, me.id).run();
      return ok({ ok: true });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "wallpaper") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const wallpaper = typeof body.wallpaper === "string" ? body.wallpaper.slice(0, 64) : null;
      await env.DB.prepare("UPDATE chat_members SET wallpaper = ? WHERE chat_id = ? AND user_id = ?")
        .bind(wallpaper, chatId, me.id)
        .run();
      return json({ wallpaper });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "media") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);

      const contentType = (request.headers.get("content-type") ?? "").toLowerCase();
      if (!contentType.includes("multipart/form-data")) {
        throw new ApiError(400, "请使用 multipart/form-data 上传", "invalid_input");
      }

      const form = await request.formData();
      const file = form.get("file");
      if (!(file instanceof File)) throw new ApiError(400, "缺少文件", "invalid_input");

      const size = file.size;
      if (size <= 0) throw new ApiError(400, "文件为空", "invalid_input");
      if (size > 50 * 1024 * 1024) throw new ApiError(413, "文件不能超过 50MB", "too_large");

      const kindRaw = String(form.get("kind") ?? "file");
      const kind = ["image", "video", "file", "voice", "sticker", "gif", "video_note"].includes(kindRaw) ? kindRaw : "file";
      const mime = file.type || "application/octet-stream";
      const name = typeof form.get("name") === "string" ? String(form.get("name")) : (file.name || null);
      const width = intField(form.get("width"));
      const height = intField(form.get("height"));
      const durationMs = intField(form.get("durationMs"));

      const mediaId = crypto.randomUUID();
      const objectKey = `media/${chatId}/${mediaId}`;
      await env.MEDIA.put(objectKey, file.stream(), { httpMetadata: { contentType: mime } });

      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO media (id, chat_id, uploader_id, kind, mime, size, file_name, width, height, duration_ms, object_key, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      )
        .bind(mediaId, chatId, me.id, kind, mime, size, name, width, height, durationMs, objectKey, now)
        .run();

      const row = await env.DB.prepare("SELECT * FROM media WHERE id = ?").bind(mediaId).first<any>();
      return json({ media: mapMedia(row) }, 201);
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "messages") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const params = new URL(request.url).searchParams;
      const before = parseInt(params.get("before") ?? "0", 10) || 0;
      const limit = Math.min(Math.max(parseInt(params.get("limit") ?? "50", 10) || 50, 1), 100);
      const topicParam = params.get("topic");

      const chat = await getChatRow(env, chatId);
      if ((chat.auto_delete_seconds ?? 0) > 0) {
        const cutoff = Date.now() - chat.auto_delete_seconds * 1000;
        await env.DB.prepare(
          "UPDATE messages SET deleted_at = ?, text = '' WHERE chat_id = ? AND created_at < ? AND deleted_at IS NULL",
        )
          .bind(Date.now(), chatId, cutoff)
          .run();
      }
      const member = await env.DB.prepare("SELECT role, joined_seq FROM chat_members WHERE chat_id = ? AND user_id = ?")
        .bind(chatId, me.id)
        .first<any>();
      const minSeq = (chat.history_visible ?? 1) === 0 && member?.role === "member" ? (member.joined_seq ?? 0) : 0;

      let sql = `${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.seq < ? AND m.seq > ?`;
      const bindings: unknown[] = [chatId, before > 0 ? before : Number.MAX_SAFE_INTEGER, minSeq];
      if ((chat.topics_enabled ?? 0) === 1) {
        if (topicParam) {
          sql += " AND m.topic_id = ?";
          bindings.push(topicParam);
        } else {
          sql += " AND m.topic_id IS NULL";
        }
      }
      sql += " ORDER BY m.seq DESC LIMIT ?";
      bindings.push(limit);

      const rows = await env.DB.prepare(sql).bind(...bindings).all<any>();
      const mapped = rows.results.map(mapMessage);
      await decorate(env, rows.results, mapped, me.id);
      if (chat.type === "channel") {
        await recordViews(env, rows.results, me.id);
      }
      const messages = mapped.reverse();
      return json({ messages, hasMore: rows.results.length === limit });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "messages") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const memberState = await env.DB.prepare(
        "SELECT muted_until FROM chat_members WHERE chat_id = ? AND user_id = ?",
      )
        .bind(chatId, me.id)
        .first<any>();
      if (memberState?.muted_until && memberState.muted_until > Date.now()) {
        throw new ApiError(403, "你已被禁言", "muted");
      }

      const chatForBlock = await getChatRow(env, chatId);
      if (chatForBlock.type === "direct") {
        const other = await env.DB.prepare("SELECT user_id FROM chat_members WHERE chat_id = ? AND user_id != ?")
          .bind(chatId, me.id)
          .first<any>();
        if (other) {
          const blocked = await env.DB.prepare(
            "SELECT 1 AS x FROM blocks WHERE (blocker_id = ? AND blocked_id = ?) OR (blocker_id = ? AND blocked_id = ?)",
          )
            .bind(me.id, other.user_id, other.user_id, me.id)
            .first();
          if (blocked) throw new ApiError(403, "你们之间存在屏蔽关系，无法发送消息", "blocked");
        }
      }
      const chatRow = await getChatRow(env, chatId);
      const myRole = await chatRole(env, chatId, me.id);
      if ((chatRow.slow_mode ?? 0) > 0 && myRole === "member") {
        const last = await env.DB.prepare(
          "SELECT created_at FROM messages WHERE chat_id = ? AND sender_id = ? ORDER BY seq DESC LIMIT 1",
        )
          .bind(chatId, me.id)
          .first<any>();
        if (last) {
          const waitMs = chatRow.slow_mode * 1000 - (Date.now() - last.created_at);
          if (waitMs > 0) {
            throw new ApiError(429, `慢速模式：请等待 ${Math.ceil(waitMs / 1000)} 秒`, "slow_mode");
          }
        }
      }

      const chatMeta = await getChatRow(env, chatId);
      if (chatMeta.type === "channel") {
        const roleNow = await chatRole(env, chatId, me.id);
        if (roleNow !== "owner" && roleNow !== "admin") {
          throw new ApiError(403, "只有频道管理员可以发布", "forbidden");
        }
      }

      const body = await readBody(request);
      const mediaId = typeof body.mediaId === "string" && body.mediaId ? body.mediaId : null;
      let topicId = typeof body.topicId === "string" && body.topicId ? body.topicId : null;
      if (topicId) {
        const topic = await env.DB.prepare("SELECT 1 AS x FROM topics WHERE id = ? AND chat_id = ?")
          .bind(topicId, chatId)
          .first();
        if (!topic) topicId = null;
      }
      const rawText = typeof body.text === "string" ? body.text.trim() : "";
      if (!rawText && !mediaId) throw new ApiError(400, "消息内容不能为空", "invalid_input");
      if (rawText.length > 4096) throw new ApiError(400, "消息内容过长", "invalid_input");
      const content = rawText;
      const clientId = typeof body.clientId === "string" ? body.clientId.slice(0, 64) : null;
      const replyRaw = parseInt(String(body.replyTo ?? ""), 10);
      const replyTo = Number.isFinite(replyRaw) && replyRaw > 0 ? replyRaw : null;
      const forwardedFrom = typeof body.forwardedFrom === "string" ? body.forwardedFrom.slice(0, 200) : null;

      if (replyTo) {
        const target = await env.DB.prepare("SELECT 1 AS x FROM messages WHERE chat_id = ? AND seq = ?")
          .bind(chatId, replyTo)
          .first();
        if (!target) throw new ApiError(400, "被回复的消息不存在", "invalid_input");
      }

      if (mediaId) {
        const media = await env.DB.prepare("SELECT * FROM media WHERE id = ?").bind(mediaId).first<any>();
        if (!media || media.chat_id !== chatId) throw new ApiError(400, "媒体不存在", "invalid_media");
        if (media.uploader_id !== me.id) throw new ApiError(403, "不能使用他人上传的媒体", "forbidden");
      }

      if (clientId) {
        const dup = await env.DB.prepare(
          `${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.sender_id = ? AND m.client_id = ? LIMIT 1`,
        )
          .bind(chatId, me.id, clientId)
          .first<any>();
        if (dup) return json({ message: mapMessage(dup), duplicate: true });
      }

      const id = crypto.randomUUID();
      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO messages (id, chat_id, sender_id, text, created_at, client_id, media_id, reply_to_seq, forwarded_from, topic_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      )
        .bind(id, chatId, me.id, content, now, clientId, mediaId, replyTo, forwardedFrom, topicId)
        .run();
      const row = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.id = ?`).bind(id).first<any>();
      const message = mapMessage(row);
      await decorate(env, [row], [message], me.id);
      await env.DB.prepare("UPDATE chat_members SET last_read_seq = MAX(last_read_seq, ?) WHERE chat_id = ? AND user_id = ?")
        .bind(message.seq, chatId, me.id)
        .run();

      await broadcast(env, ctx, chatId, { type: "message", chatId, message });

      // Fan out to every other member's personal channel (background service /
      // push notifications). Each recipient has a single UserHub instance.
      const recipients = await env.DB.prepare(
        "SELECT user_id FROM chat_members WHERE chat_id = ? AND user_id != ?",
      )
        .bind(chatId, me.id)
        .all<{ user_id: string }>();
      const payload = JSON.stringify({ type: "message", chatId, message });
      for (const row of recipients.results) {
        const stub = env.USER_HUB.get(env.USER_HUB.idFromName(row.user_id));
        ctx.waitUntil(
          stub
            .fetch("https://hub/broadcast", {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: payload,
            })
            .catch(() => undefined),
        );
      }

      return json({ message }, 201);
    }

    if ((method === "PATCH" || method === "DELETE") && seg.length === 5 && seg[3] === "messages") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const seq = parseInt(seg[4], 10);
      if (!Number.isFinite(seq)) throw new ApiError(400, "无效的消息序号", "invalid_input");

      const row = await env.DB.prepare("SELECT * FROM messages WHERE chat_id = ? AND seq = ?")
        .bind(chatId, seq)
        .first<any>();
      if (!row) throw new ApiError(404, "消息不存在", "not_found");
      const actorRole = await chatRole(env, chatId, me.id);
      const canModerate = actorRole === "owner" || actorRole === "admin";
      if (row.sender_id !== me.id && !canModerate) {
        throw new ApiError(403, "只能操作自己的消息", "forbidden");
      }
      if (row.deleted_at) throw new ApiError(400, "消息已删除", "invalid_input");

      if (method === "PATCH") {
        const body = await readBody(request);
        const content = text(body.text, "消息内容", 1, 4096);
        await env.DB.prepare("UPDATE messages SET text = ?, edited_at = ? WHERE chat_id = ? AND seq = ?")
          .bind(content, Date.now(), chatId, seq)
          .run();
        const updated = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.seq = ?`)
          .bind(chatId, seq)
          .first<any>();
        const message = mapMessage(updated);
        await decorate(env, [updated], [message], me.id);
        await broadcast(env, ctx, chatId, { type: "edit", chatId, message });
        return json({ message });
      }

      await env.DB.prepare("UPDATE messages SET deleted_at = ?, text = '' WHERE chat_id = ? AND seq = ?")
        .bind(Date.now(), chatId, seq)
        .run();
      await env.DB.batch([
        env.DB.prepare("DELETE FROM message_reactions WHERE message_id = ?").bind(row.id),
        env.DB.prepare("DELETE FROM pinned_messages WHERE chat_id = ? AND message_seq = ?").bind(chatId, seq),
      ]);
      await broadcast(env, ctx, chatId, { type: "delete", chatId, seq });
      return ok({ ok: true, seq });
    }

    if (method === "POST" && seg.length === 6 && seg[3] === "messages" && seg[5] === "reactions") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const seq = parseInt(seg[4], 10);
      const target = await env.DB.prepare("SELECT * FROM messages WHERE chat_id = ? AND seq = ?")
        .bind(chatId, seq)
        .first<any>();
      if (!target || target.deleted_at) throw new ApiError(404, "消息不存在", "not_found");

      const body = await readBody(request);
      const emoji = typeof body.emoji === "string" ? body.emoji.trim().slice(0, 16) : "";
      if (!emoji) throw new ApiError(400, "缺少 emoji", "invalid_input");

      const existing = await env.DB.prepare(
        "SELECT 1 AS x FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?",
      )
        .bind(target.id, me.id, emoji)
        .first();

      if (existing) {
        await env.DB.prepare("DELETE FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?")
          .bind(target.id, me.id, emoji)
          .run();
      } else {
        await env.DB.prepare(
          "INSERT INTO message_reactions (message_id, chat_id, user_id, emoji, created_at) VALUES (?, ?, ?, ?, ?)",
        )
          .bind(target.id, chatId, me.id, emoji, Date.now())
          .run();
      }

      const result = await env.DB.prepare(
        "SELECT emoji, COUNT(*) AS count, MAX(CASE WHEN user_id = ? THEN 1 ELSE 0 END) AS mine FROM message_reactions WHERE message_id = ? GROUP BY emoji",
      )
        .bind(me.id, target.id)
        .all<any>();
      const reactions = result.results.map((item: any) => ({ emoji: item.emoji, count: item.count, me: !!item.mine }));

      await broadcast(env, ctx, chatId, { type: "reaction", chatId, seq, messageId: target.id, reactions });
      return json({ reactions });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "pin") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const seq = parseInt(String(body.seq ?? ""), 10);
      if (!Number.isFinite(seq)) throw new ApiError(400, "缺少 seq", "invalid_input");
      if (body.pinned) {
        await env.DB.prepare(
          "INSERT OR IGNORE INTO pinned_messages (chat_id, message_seq, pinned_by, pinned_at) VALUES (?, ?, ?, ?)",
        )
          .bind(chatId, seq, me.id, Date.now())
          .run();
      } else {
        await env.DB.prepare("DELETE FROM pinned_messages WHERE chat_id = ? AND message_seq = ?")
          .bind(chatId, seq)
          .run();
      }
      await broadcast(env, ctx, chatId, { type: "pin", chatId, seq, pinned: !!body.pinned });
      return json({ pinned: !!body.pinned });
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "search") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const query = (new URL(request.url).searchParams.get("q") ?? "").trim();
      if (!query) return json({ messages: [] });
      const escaped = query.replace(/[\\%_]/g, (ch) => `\\${ch}`);
      const rows = await env.DB.prepare(
        `${MESSAGE_SELECT} WHERE m.chat_id = ? AND m.deleted_at IS NULL AND m.text LIKE ? ESCAPE '\\' ORDER BY m.seq DESC LIMIT 50`,
      )
        .bind(chatId, `%${escaped}%`)
        .all<any>();
      const mapped = rows.results.map(mapMessage);
      await decorate(env, rows.results, mapped, me.id);
      return json({ messages: mapped });
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "topics") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const rows = await env.DB.prepare(
        "SELECT * FROM topics WHERE chat_id = ? ORDER BY pinned DESC, created_at",
      )
        .bind(chatId)
        .all<any>();
      return json({
        topics: rows.results.map((t: any) => ({
          id: t.id,
          chatId: t.chat_id,
          title: t.title,
          emoji: t.emoji ?? null,
          closed: !!t.closed,
          pinned: !!t.pinned,
          createdBy: t.created_by,
          createdAt: t.created_at,
        })),
      });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "topics") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      const body = await readBody(request);
      const topicTitle = text(body.title, "话题名称", 1, 64);
      const emoji = typeof body.emoji === "string" ? body.emoji.slice(0, 8) : null;
      const id = crypto.randomUUID();
      await env.DB.prepare(
        "INSERT INTO topics (id, chat_id, title, emoji, created_by, created_at, closed, pinned) VALUES (?, ?, ?, ?, ?, ?, 0, 0)",
      )
        .bind(id, chatId, topicTitle, emoji, me.id, Date.now())
        .run();
      return json({ topic: { id, chatId, title: topicTitle, emoji, closed: false, pinned: false } }, 201);
    }

    if (method === "PATCH" && seg.length === 5 && seg[3] === "topics") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      const body = await readBody(request);
      const fields: string[] = [];
      const values: unknown[] = [];
      if (typeof body.title === "string" && body.title.trim()) {
        fields.push("title = ?");
        values.push(body.title.trim().slice(0, 64));
      }
      if (body.closed !== undefined) {
        fields.push("closed = ?");
        values.push(body.closed ? 1 : 0);
      }
      if (body.pinned !== undefined) {
        fields.push("pinned = ?");
        values.push(body.pinned ? 1 : 0);
      }
      if (!fields.length) throw new ApiError(400, "没有可更新的字段", "invalid_input");
      values.push(seg[4], chatId);
      await env.DB.prepare(`UPDATE topics SET ${fields.join(", ")} WHERE id = ? AND chat_id = ?`).bind(...values).run();
      return ok({ ok: true });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "polls") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const question = text(body.question, "投票问题", 1, 300);
      const rawOptions = Array.isArray(body.options) ? body.options : [];
      const options = rawOptions
        .map((item: unknown) => (typeof item === "string" ? item.trim().slice(0, 100) : ""))
        .filter((item: string) => item.length > 0);
      if (options.length < 2 || options.length > 10) {
        throw new ApiError(400, "投票需要 2-10 个选项", "invalid_input");
      }

      const pollId = crypto.randomUUID();
      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO polls (id, chat_id, question, options, multiple, anonymous, closed, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)",
      )
        .bind(pollId, chatId, question, JSON.stringify(options), body.multiple ? 1 : 0, body.anonymous ? 1 : 0, me.id, now)
        .run();

      const id = crypto.randomUUID();
      const topicId = typeof body.topicId === "string" && body.topicId ? body.topicId : null;
      await env.DB.prepare(
        "INSERT INTO messages (id, chat_id, sender_id, text, created_at, client_id, poll_id, topic_id) VALUES (?, ?, ?, '', ?, ?, ?, ?)",
      )
        .bind(id, chatId, me.id, now, `poll-${pollId}`, pollId, topicId)
        .run();

      const row = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.id = ?`).bind(id).first<any>();
      const message = mapMessage(row);
      await decorate(env, [row], [message], me.id);
      await broadcast(env, ctx, chatId, { type: "message", chatId, message });
      return json({ message }, 201);
    }

    if (method === "POST" && seg.length === 6 && seg[3] === "polls" && seg[5] === "vote") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const pollId = seg[4];
      const body = await readBody(request);
      const optionIndex = parseInt(String(body.optionIndex ?? ""), 10);
      const poll = await env.DB.prepare("SELECT * FROM polls WHERE id = ? AND chat_id = ?").bind(pollId, chatId).first<any>();
      if (!poll) throw new ApiError(404, "投票不存在", "not_found");
      if (poll.closed) throw new ApiError(400, "投票已结束", "invalid_input");
      const options: string[] = JSON.parse(poll.options);
      if (!Number.isFinite(optionIndex) || optionIndex < 0 || optionIndex >= options.length) {
        throw new ApiError(400, "无效的选项", "invalid_input");
      }

      const existing = await env.DB.prepare(
        "SELECT 1 AS x FROM poll_votes WHERE poll_id = ? AND user_id = ? AND option_index = ?",
      )
        .bind(pollId, me.id, optionIndex)
        .first();
      if (existing) {
        await env.DB.prepare("DELETE FROM poll_votes WHERE poll_id = ? AND user_id = ? AND option_index = ?")
          .bind(pollId, me.id, optionIndex)
          .run();
      } else {
        if (!poll.multiple) {
          await env.DB.prepare("DELETE FROM poll_votes WHERE poll_id = ? AND user_id = ?").bind(pollId, me.id).run();
        }
        await env.DB.prepare(
          "INSERT INTO poll_votes (poll_id, user_id, option_index, created_at) VALUES (?, ?, ?, ?)",
        )
          .bind(pollId, me.id, optionIndex, Date.now())
          .run();
      }

      const messageRow = await env.DB.prepare(`${MESSAGE_SELECT} WHERE m.poll_id = ? LIMIT 1`).bind(pollId).first<any>();
      const mappedRow = mapMessage(messageRow);
      await decorate(env, [messageRow], [mappedRow], me.id);
      await broadcast(env, ctx, chatId, {
        type: "poll",
        chatId,
        seq: messageRow.seq,
        poll: mappedRow.poll,
      });
      return json({ poll: mappedRow.poll });
    }

    if (method === "POST" && seg.length === 6 && seg[3] === "polls" && seg[5] === "close") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      await env.DB.prepare("UPDATE polls SET closed = 1 WHERE id = ? AND chat_id = ?").bind(seg[4], chatId).run();
      return ok({ ok: true });
    }

    if (method === "POST" && seg.length === 6 && seg[3] === "messages" && seg[5] === "report") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const seq = parseInt(seg[4], 10);
      const target = await env.DB.prepare("SELECT id FROM messages WHERE chat_id = ? AND seq = ?").bind(chatId, seq).first<any>();
      if (!target) throw new ApiError(404, "消息不存在", "not_found");
      const body = await readBody(request);
      const reason = typeof body.reason === "string" ? body.reason.slice(0, 500) : "";
      await env.DB.prepare(
        "INSERT INTO reports (id, chat_id, message_id, message_seq, reporter_id, reason, created_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'open')",
      )
        .bind(crypto.randomUUID(), chatId, target.id, seq, me.id, reason, Date.now())
        .run();
      return ok({ ok: true });
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "reports") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      const rows = await env.DB.prepare(
        `SELECT r.*, u.display_name AS reporter_name, m.text AS message_text
         FROM reports r
         LEFT JOIN users u ON u.id = r.reporter_id
         LEFT JOIN messages m ON m.id = r.message_id
         WHERE r.chat_id = ? ORDER BY r.created_at DESC LIMIT 100`,
      )
        .bind(chatId)
        .all<any>();
      return json({
        reports: rows.results.map((r: any) => ({
          id: r.id,
          seq: r.message_seq,
          reporter: r.reporter_name ?? "",
          reason: r.reason ?? "",
          text: r.message_text ?? "",
          status: r.status,
          createdAt: r.created_at,
        })),
      });
    }

    if (method === "POST" && seg.length === 5 && seg[3] === "reports") {
      const me = await authenticate(request, env);
      await requireManager(env, chatId, me.id);
      await env.DB.prepare("UPDATE reports SET status = 'resolved' WHERE id = ? AND chat_id = ?")
        .bind(seg[4], chatId)
        .run();
      return ok({ ok: true });
    }

    if (method === "POST" && seg.length === 5 && seg[3] === "messages" && seg[4] === "batch-delete") {
      const me = await authenticate(request, env);
      const role = await chatRole(env, chatId, me.id);
      if (!role) throw new ApiError(403, "你不是该会话的成员", "forbidden");
      const isManager = role === "owner" || role === "admin";
      const body = await readBody(request);
      const seqs = Array.isArray(body.seqs) ? body.seqs.map((n: unknown) => Number(n)).filter(Number.isFinite) : [];
      let deleted = 0;
      for (const seq of seqs.slice(0, 200)) {
        const target = await env.DB.prepare("SELECT * FROM messages WHERE chat_id = ? AND seq = ?")
          .bind(chatId, seq)
          .first<any>();
        if (!target || target.deleted_at) continue;
        if (target.sender_id !== me.id && !isManager) continue;
        await env.DB.prepare("UPDATE messages SET deleted_at = ?, text = '' WHERE chat_id = ? AND seq = ?")
          .bind(Date.now(), chatId, seq)
          .run();
        await broadcast(env, ctx, chatId, { type: "delete", chatId, seq });
        deleted += 1;
      }
      return json({ deleted });
    }

    if (method === "POST" && seg.length === 4 && seg[3] === "read") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const body = await readBody(request);
      const seq = Math.max(0, parseInt(String(body.seq ?? "0"), 10) || 0);
      await env.DB.prepare("UPDATE chat_members SET last_read_seq = MAX(last_read_seq, ?) WHERE chat_id = ? AND user_id = ?")
        .bind(seq, chatId, me.id)
        .run();
      await broadcast(env, ctx, chatId, { type: "read", chatId, userId: me.id, seq }, me.id);
      return ok({ ok: true, seq });
    }

    if (method === "GET" && seg.length === 4 && seg[3] === "members") {
      const me = await authenticate(request, env);
      await assertMember(env, chatId, me.id);
      const members = await env.DB.prepare(
        `SELECT u.id, u.username, u.display_name, u.avatar_color, u.role, u.last_seen_at,
                m.role AS member_role, m.muted_until
         FROM chat_members m JOIN users u ON u.id = m.user_id WHERE m.chat_id = ?`,
      )
        .bind(chatId)
        .all<any>();
      return json({
        members: members.results.map((m: any) => ({
          id: m.id,
          username: m.username,
          displayName: m.display_name,
          avatarColor: m.avatar_color,
          role: m.role,
          chatRole: m.member_role ?? "member",
          mutedUntil: m.muted_until ?? null,
          lastSeenAt: m.last_seen_at,
        })),
      });
    }
  }

  // ---------------- admin ----------------
  if (seg[0] === "api" && seg[1] === "admin" && seg[2] === "users") {
    const me = await authenticate(request, env);
    requireAdmin(me);

    if (method === "GET" && seg.length === 3) {
      const rows = await env.DB.prepare("SELECT * FROM users ORDER BY created_at").all<UserRow>();
      return json({ users: rows.results.map(publicUser) });
    }

    if (method === "POST" && seg.length === 3) {
      const body = await readBody(request);
      const uname = username(body.username);
      const pass = password(body.password);
      const displayName =
        typeof body.displayName === "string" && body.displayName.trim()
          ? text(body.displayName, "displayName", 1, 64)
          : uname;
      const role = body.role === "admin" ? "admin" : "user";
      const color = AVATAR_COLORS[Math.floor(Math.random() * AVATAR_COLORS.length)];
      const iterations = parseInt(env.PBKDF2_ITERATIONS ?? "0", 10) || DEFAULT_ITERATIONS;

      const exists = await env.DB.prepare("SELECT 1 AS x FROM users WHERE username = ?").bind(uname).first();
      if (exists) throw new ApiError(409, "用户名已存在", "username_taken");

      const id = crypto.randomUUID();
      const now = Date.now();
      await env.DB.prepare(
        "INSERT INTO users (id, username, password_hash, display_name, avatar_color, role, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)",
      )
        .bind(id, uname, await hashPassword(pass, iterations), displayName, color, role, now)
        .run();

      const created = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();

      // Give the new account a direct chat with the admin who created it,
      // so both sides see something useful right after first login.
      let chatId: string | null = null;
      if (body.withAdminChat !== false && id !== me.id) {
        const existing = await env.DB.prepare(
          `SELECT c.id FROM chats c
           JOIN chat_members a ON a.chat_id = c.id AND a.user_id = ?
           JOIN chat_members b ON b.chat_id = c.id AND b.user_id = ?
           WHERE c.type = 'direct' LIMIT 1`,
        )
          .bind(me.id, id)
          .first<any>();
        chatId = existing?.id ?? (await createChat(env, me.id, [id], "direct", null));
      }

      return json({ user: publicUser(created!), chatId }, 201);
    }

    if (method === "POST" && seg.length === 5 && seg[4] === "reset-password") {
      const body = await readBody(request);
      const targetId = seg[3];
      const pass = password(body.password);
      const target = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(targetId).first<UserRow>();
      if (!target) throw new ApiError(404, "用户不存在", "not_found");
      const iterations = parseInt(env.PBKDF2_ITERATIONS ?? "0", 10) || DEFAULT_ITERATIONS;
      await env.DB.batch([
        env.DB.prepare("UPDATE users SET password_hash = ? WHERE id = ?").bind(await hashPassword(pass, iterations), targetId),
        env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(targetId),
      ]);
      return ok({ ok: true });
    }
  }

  throw new ApiError(404, `No route for ${method} ${path}`, "not_found");
}

export { ApiError };
