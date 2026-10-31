-- tgchat D1 schema. Safe to re-run: everything is IF NOT EXISTS.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id           TEXT PRIMARY KEY,
  username     TEXT NOT NULL UNIQUE COLLATE NOCASE,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  avatar_color TEXT NOT NULL DEFAULT '#3390EC',
  role         TEXT NOT NULL DEFAULT 'user',   -- 'admin' | 'user'
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS chats (
  id         TEXT PRIMARY KEY,
  type       TEXT NOT NULL DEFAULT 'direct',   -- 'direct' | 'group'
  title      TEXT,
  created_at INTEGER NOT NULL,
  created_by TEXT
);

CREATE TABLE IF NOT EXISTS chat_members (
  chat_id       TEXT NOT NULL,
  user_id       TEXT NOT NULL,
  joined_at     INTEGER NOT NULL,
  last_read_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (chat_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_members_user ON chat_members(user_id);

CREATE TABLE IF NOT EXISTS messages (
  seq        INTEGER PRIMARY KEY AUTOINCREMENT,
  id         TEXT NOT NULL UNIQUE,
  chat_id    TEXT NOT NULL,
  sender_id  TEXT NOT NULL,
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  client_id  TEXT,
  media_id   TEXT,
  reply_to_seq    INTEGER,
  edited_at       INTEGER,
  deleted_at      INTEGER,
  forwarded_from  TEXT
);
CREATE INDEX IF NOT EXISTS idx_messages_media ON messages(media_id);

CREATE TABLE IF NOT EXISTS media (
  id          TEXT PRIMARY KEY,
  chat_id     TEXT NOT NULL,
  uploader_id TEXT NOT NULL,
  kind        TEXT NOT NULL,            -- image | video | file | voice | sticker | gif
  mime        TEXT NOT NULL,
  size        INTEGER NOT NULL,
  file_name   TEXT,
  width       INTEGER,
  height      INTEGER,
  duration_ms INTEGER,
  object_key  TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_media_chat ON media(chat_id);

CREATE TABLE IF NOT EXISTS message_reactions (
  message_id TEXT NOT NULL,
  chat_id    TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  emoji      TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (message_id, user_id, emoji)
);
CREATE INDEX IF NOT EXISTS idx_reactions_chat ON message_reactions(chat_id);

CREATE TABLE IF NOT EXISTS pinned_messages (
  chat_id    TEXT NOT NULL,
  message_seq INTEGER NOT NULL,
  pinned_by  TEXT NOT NULL,
  pinned_at  INTEGER NOT NULL,
  PRIMARY KEY (chat_id, message_seq)
);
CREATE INDEX IF NOT EXISTS idx_messages_chat_seq ON messages(chat_id, seq);
