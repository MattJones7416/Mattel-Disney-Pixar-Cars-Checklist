CREATE TABLE IF NOT EXISTS push_tokens (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'ios',
  environment TEXT NOT NULL DEFAULT 'production',
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_success_at TEXT,
  last_failure_at TEXT,
  failure_reason TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user
  ON push_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_push_tokens_enabled_environment
  ON push_tokens(enabled, environment);
