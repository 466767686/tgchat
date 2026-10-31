-- Run ONCE on an existing database (fresh installs already include these
-- columns/tables in schema.sql).
ALTER TABLE messages ADD COLUMN reply_to_seq INTEGER;
ALTER TABLE messages ADD COLUMN edited_at INTEGER;
ALTER TABLE messages ADD COLUMN deleted_at INTEGER;
ALTER TABLE messages ADD COLUMN forwarded_from TEXT;

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
