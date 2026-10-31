-- Run ONCE on an existing database.
ALTER TABLE users ADD COLUMN bio TEXT;
ALTER TABLE users ADD COLUMN last_seen_visibility TEXT NOT NULL DEFAULT 'everyone';
ALTER TABLE users ADD COLUMN read_receipts INTEGER NOT NULL DEFAULT 1;
ALTER TABLE sessions ADD COLUMN device_name TEXT;
ALTER TABLE sessions ADD COLUMN platform TEXT;
ALTER TABLE sessions ADD COLUMN last_active_at INTEGER;
ALTER TABLE chats ADD COLUMN auto_delete_seconds INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS blocks (
  blocker_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (blocker_id, blocked_id)
);
