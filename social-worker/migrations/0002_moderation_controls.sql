ALTER TABLE users ADD COLUMN rules_accepted_at TEXT;

CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_id TEXT NOT NULL,
  blocked_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(blocker_id, blocked_id),
  FOREIGN KEY(blocker_id) REFERENCES users(id),
  FOREIGN KEY(blocked_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker
  ON user_blocks(blocker_id);

CREATE INDEX IF NOT EXISTS idx_reports_post_created
  ON reports(post_id, created_at);
