-- Run ONCE on an existing database.
ALTER TABLE chats ADD COLUMN description TEXT;
ALTER TABLE chats ADD COLUMN announcement TEXT;
ALTER TABLE chats ADD COLUMN photo_url TEXT;
ALTER TABLE chats ADD COLUMN join_mode TEXT NOT NULL DEFAULT 'invite';
ALTER TABLE chat_members ADD COLUMN role TEXT NOT NULL DEFAULT 'member';
ALTER TABLE chat_members ADD COLUMN muted_until INTEGER;

CREATE TABLE IF NOT EXISTS chat_invites (
  code       TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,
  revoked    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_invites_chat ON chat_invites(chat_id);

CREATE TABLE IF NOT EXISTS chat_join_requests (
  id         TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  status     TEXT NOT NULL DEFAULT 'pending'
);
