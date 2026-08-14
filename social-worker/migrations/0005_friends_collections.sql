ALTER TABLE users ADD COLUMN collection_visibility TEXT NOT NULL DEFAULT 'friends';

CREATE TABLE IF NOT EXISTS friendships (
  requester_id TEXT NOT NULL,
  addressee_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(requester_id, addressee_id),
  FOREIGN KEY(requester_id) REFERENCES users(id),
  FOREIGN KEY(addressee_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_friendships_addressee
  ON friendships(addressee_id);

CREATE INDEX IF NOT EXISTS idx_friendships_status_updated
  ON friendships(status, updated_at);

CREATE TABLE IF NOT EXISTS collection_snapshots (
  user_id TEXT PRIMARY KEY,
  visibility TEXT NOT NULL DEFAULT 'friends',
  stats_json TEXT NOT NULL DEFAULT '{}',
  models_json TEXT NOT NULL DEFAULT '[]',
  model_count INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_collection_snapshots_updated
  ON collection_snapshots(updated_at);
