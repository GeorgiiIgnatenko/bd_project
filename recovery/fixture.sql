\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA IF NOT EXISTS recovery_lab AUTHORIZATION news_admin;
CREATE TABLE IF NOT EXISTS recovery_lab.probe (
    label text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    actor name NOT NULL DEFAULT current_user
);
GRANT USAGE ON SCHEMA recovery_lab TO news_app;
GRANT SELECT, INSERT ON recovery_lab.probe TO news_app;
COMMIT;
