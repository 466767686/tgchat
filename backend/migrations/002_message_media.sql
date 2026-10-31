-- Run ONCE on an existing database (fresh installs already include this column
-- in schema.sql). Adds the media reference to messages.
ALTER TABLE messages ADD COLUMN media_id TEXT;
