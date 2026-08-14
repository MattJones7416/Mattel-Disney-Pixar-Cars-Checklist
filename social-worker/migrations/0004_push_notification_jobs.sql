CREATE TABLE IF NOT EXISTS push_notification_jobs (
  id TEXT PRIMARY KEY,
  audience TEXT NOT NULL,
  post_id TEXT,
  author_id TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data_json TEXT NOT NULL,
  cursor_token TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_push_notification_jobs_status_created
  ON push_notification_jobs(status, created_at);
