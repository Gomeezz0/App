CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text NOT NULL,
  password_hash text NOT NULL,
  display_name  text NOT NULL,
  reputation    integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_key ON users (lower(email));

CREATE TABLE refresh_tokens (
  token_hash text PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx ON refresh_tokens (user_id);

CREATE TABLE alerts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type            text NOT NULL,
  lat             double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lon             double precision NOT NULL CHECK (lon BETWEEN -180 AND 180),
  heading         real,
  country         text,
  source          text NOT NULL DEFAULT 'community' CHECK (source IN ('community', 'official')),
  reporter_id     uuid REFERENCES users(id) ON DELETE SET NULL,
  reporter_weight real NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz,
  removed_at      timestamptz,
  removed_reason  text
);
CREATE INDEX alerts_active_geo_idx ON alerts (lat, lon) WHERE removed_at IS NULL;
CREATE INDEX alerts_reporter_idx ON alerts (reporter_id, created_at);

CREATE TABLE alert_votes (
  alert_id   uuid NOT NULL REFERENCES alerts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  vote       text NOT NULL CHECK (vote IN ('confirm', 'deny')),
  weight     real NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (alert_id, user_id)
);
