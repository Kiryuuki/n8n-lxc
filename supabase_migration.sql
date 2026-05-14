CREATE TABLE IF NOT EXISTS n8n_execution_logs (
  id BIGSERIAL PRIMARY KEY,
  execution_id TEXT,
  workflow_id TEXT,
  workflow_name TEXT,
  status TEXT,
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  duration_ms INTEGER,
  mode TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_n8n_execution_logs_execution_id
  ON n8n_execution_logs (execution_id);

CREATE INDEX IF NOT EXISTS idx_n8n_execution_logs_workflow_id
  ON n8n_execution_logs (workflow_id);

CREATE INDEX IF NOT EXISTS idx_n8n_execution_logs_workflow_name
  ON n8n_execution_logs (workflow_name);

CREATE INDEX IF NOT EXISTS idx_n8n_execution_logs_status
  ON n8n_execution_logs (status);

CREATE INDEX IF NOT EXISTS idx_n8n_execution_logs_created_at
  ON n8n_execution_logs (created_at DESC);
