-- Run ONCE on an existing database.
ALTER TABLE chats ADD COLUMN username TEXT;
ALTER TABLE chats ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chats ADD COLUMN discussion_chat_id TEXT;

CREATE TABLE IF NOT EXISTS message_views (
  message_id TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  viewed_at  INTEGER NOT NULL,
  PRIMARY KEY (message_id, user_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chats_username ON chats(username);
