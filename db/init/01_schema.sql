-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Table: nodes
CREATE TABLE IF NOT EXISTS nodes (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  labels JSONB,
  last_seen TIMESTAMPTZ DEFAULT now()
);

-- Table: metrics (time-series)
CREATE TABLE IF NOT EXISTS metrics (
  time TIMESTAMPTZ NOT NULL,
  node_id TEXT NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  metric_name TEXT NOT NULL,
  value DOUBLE PRECISION NOT NULL,
  unit TEXT
);

-- Convert metrics to hypertable
SELECT create_hypertable('metrics', 'time', if_not_exists => TRUE);

-- Index for fast queries by node and time
CREATE INDEX IF NOT EXISTS idx_metrics_node_time
ON metrics (node_id, time DESC);

