-- Run ONCE on an existing database.
ALTER TABLE chats ADD COLUMN slow_mode INTEGER NOT NULL DEFAULT 0;
ALTER TABLE chats ADD COLUMN history_visible INTEGER NOT NULL DEFAULT 1;
ALTER TABLE chats ADD COLUMN topics_enabled INTEGER NOT NULL DEFAULT 0;
ALTER TABLE messages ADD COLUMN topic_id TEXT;
ALTER TABLE messages ADD COLUMN poll_id TEXT;
ALTER TABLE chat_members ADD COLUMN joined_seq INTEGER NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS topics (
  id         TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL,
  title      TEXT NOT NULL,
  emoji      TEXT,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  closed     INTEGER NOT NULL DEFAULT 0,
  pinned     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_topics_chat ON topics(chat_id);

CREATE TABLE IF NOT EXISTS polls (
  id         TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL,
  question   TEXT NOT NULL,
  options    TEXT NOT NULL,
  multiple   INTEGER NOT NULL DEFAULT 0,
  anonymous  INTEGER NOT NULL DEFAULT 0,
  closed     INTEGER NOT NULL DEFAULT 0,
  created_by TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id      TEXT NOT NULL,
  user_id      TEXT NOT NULL,
  option_index INTEGER NOT NULL,
  created_at   INTEGER NOT NULL,
  PRIMARY KEY (poll_id, user_id, option_index)
);

CREATE TABLE IF NOT EXISTS reports (
  id         TEXT PRIMARY KEY,
  chat_id    TEXT NOT NULL,
  message_id TEXT,
  message_seq INTEGER,
  reporter_id TEXT NOT NULL,
  reason     TEXT,
  created_at INTEGER NOT NULL,
  status     TEXT NOT NULL DEFAULT 'open'
);
CREATE INDEX IF NOT EXISTS idx_reports_chat ON reports(chat_id);
