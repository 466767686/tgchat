-- Run ONCE on an existing database.
ALTER TABLE chat_members ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chat_members ADD COLUMN archived INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chat_members ADD COLUMN folder_id TEXT;
ALTER TABLE chat_members ADD COLUMN wallpaper TEXT;

CREATE TABLE IF NOT EXISTS folders (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  name       TEXT NOT NULL,
  position   INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_folders_user ON folders(user_id);
