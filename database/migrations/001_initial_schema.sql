-- =============================================================================
-- migrations/001_initial_schema.sql
-- AI Investor Fraud & Impersonation Detection Platform
-- SIH Hackathon | PS13 Fintech / Smart Education
--
-- Migration 001 — Initial schema (equivalent to schema.sql but formatted as
-- an idempotent migration that can be applied incrementally in future sprints).
--
-- How to apply:
--   • Supabase SQL Editor: paste and run
--   • psql: psql $DATABASE_URL -f migrations/001_initial_schema.sql
-- =============================================================================

-- Track applied migrations (safe to run multiple times)
CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Guard: skip this migration if it has already been applied
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM schema_migrations WHERE version = '001_initial_schema'
    ) THEN
        RAISE NOTICE 'Migration 001_initial_schema already applied — skipping.';
        RETURN;
    END IF;

    -- ── Extensions ────────────────────────────────────────────────────────────
    CREATE EXTENSION IF NOT EXISTS pgcrypto;

    -- ── users ─────────────────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS users (
        id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        name       TEXT        NOT NULL,
        email      TEXT        NOT NULL UNIQUE,
        role       TEXT        NOT NULL DEFAULT 'investor'
                       CHECK (role IN ('investor', 'analyst', 'admin')),
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── detection_cases ───────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS detection_cases (
        id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id          UUID         REFERENCES users(id) ON DELETE SET NULL,
        created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
        source_type      TEXT         NOT NULL
                             CHECK (source_type IN ('video','audio','text','chat','app','url')),
        prediction       TEXT         NOT NULL DEFAULT 'PENDING'
                             CHECK (prediction IN ('PENDING','DEEPFAKE','AUTHENTIC','IMPERSONATION','SUSPICIOUS','SAFE')),
        confidence_score NUMERIC(5,4) NOT NULL DEFAULT 0
                             CHECK (confidence_score >= 0 AND confidence_score <= 1),
        risk_score       NUMERIC(5,2) NOT NULL DEFAULT 0
                             CHECK (risk_score >= 0 AND risk_score <= 100),
        risk_level       TEXT         NOT NULL DEFAULT 'UNKNOWN'
                             CHECK (risk_level IN ('LOW','MEDIUM','HIGH','UNKNOWN')),
        status           TEXT         NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','processing','processed','flagged','cleared')),
        summary          TEXT
    );

    -- ── legacy cases ──────────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS cases (
        id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        submitted_by TEXT        NOT NULL,
        source_type  TEXT        NOT NULL
                         CHECK (source_type IN ('video','audio','chat_text','url')),
        status       TEXT        NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','processed','flagged','cleared'))
    );

    -- ── evidence ──────────────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS evidence (
        id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        detection_case_id    UUID        REFERENCES detection_cases(id) ON DELETE CASCADE,
        case_id              UUID        REFERENCES cases(id)           ON DELETE CASCADE,
        evidence_type        TEXT        NOT NULL
                                 CHECK (evidence_type IN (
                                     'video_file','audio_file','image_file',
                                     'chat_message','text_document','url','app_url'
                                 )),
        file_path_or_content TEXT        NOT NULL,
        filename             TEXT,
        uploaded_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── signals (legacy) ──────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS signals (
        id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id      UUID         NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
        signal_type  TEXT         NOT NULL
                         CHECK (signal_type IN ('deepfake','impersonation','scam_nlp','platform_url')),
        signal_score NUMERIC(5,2) NOT NULL CHECK (signal_score >= 0 AND signal_score <= 100),
        raw_output   JSONB        NOT NULL DEFAULT '{}',
        created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );

    -- ── results (legacy) ──────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS results (
        id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id          UUID         NOT NULL UNIQUE REFERENCES cases(id) ON DELETE CASCADE,
        fraud_risk_score NUMERIC(5,2) NOT NULL CHECK (fraud_risk_score >= 0 AND fraud_risk_score <= 100),
        verdict          TEXT         NOT NULL CHECK (verdict IN ('low_risk','suspicious','high_risk')),
        explanation      JSONB        NOT NULL DEFAULT '{}',
        computed_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );

    -- ── alerts ────────────────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS alerts (
        id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        detection_case_id  UUID        NOT NULL REFERENCES detection_cases(id) ON DELETE CASCADE,
        alert_type         TEXT        NOT NULL
                               CHECK (alert_type IN (
                                   'DEEPFAKE_DETECTED','IMPERSONATION_DETECTED',
                                   'HIGH_RISK_CONTENT','SUSPICIOUS_ACTIVITY',
                                   'PLATFORM_URL_FLAGGED','SCAM_NLP_DETECTED'
                               )),
        severity           TEXT        NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
        message            TEXT        NOT NULL,
        is_read            BOOLEAN     NOT NULL DEFAULT FALSE,
        created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── impersonation_checks ──────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS impersonation_checks (
        id                           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
        detection_case_id            UUID         NOT NULL REFERENCES detection_cases(id) ON DELETE CASCADE,
        claimed_name                 TEXT,
        claimed_registration_number  TEXT,
        urgency_score                NUMERIC(4,3) NOT NULL DEFAULT 0
                                         CHECK (urgency_score >= 0 AND urgency_score <= 1),
        impersonation_score          NUMERIC(4,3) NOT NULL DEFAULT 0
                                         CHECK (impersonation_score >= 0 AND impersonation_score <= 1),
        prediction                   TEXT         NOT NULL DEFAULT 'PENDING'
                                         CHECK (prediction IN ('PENDING','IMPERSONATION','SUSPICIOUS','LEGITIMATE')),
        flags                        JSONB        NOT NULL DEFAULT '{}',
        created_at                   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
    );

    -- ── logs ──────────────────────────────────────────────────────────────────
    CREATE TABLE IF NOT EXISTS logs (
        id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id            UUID        REFERENCES cases(id)           ON DELETE SET NULL,
        detection_case_id  UUID        REFERENCES detection_cases(id) ON DELETE SET NULL,
        event_type         TEXT        NOT NULL,
        message            TEXT        NOT NULL,
        created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- ── Indexes ───────────────────────────────────────────────────────────────
    CREATE INDEX IF NOT EXISTS idx_users_email          ON users(email);
    CREATE INDEX IF NOT EXISTS idx_dc_user_id           ON detection_cases(user_id);
    CREATE INDEX IF NOT EXISTS idx_dc_created_at        ON detection_cases(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_dc_status            ON detection_cases(status);
    CREATE INDEX IF NOT EXISTS idx_dc_risk_level        ON detection_cases(risk_level);
    CREATE INDEX IF NOT EXISTS idx_dc_prediction        ON detection_cases(prediction);
    CREATE INDEX IF NOT EXISTS idx_alerts_case_id       ON alerts(detection_case_id);
    CREATE INDEX IF NOT EXISTS idx_alerts_is_read       ON alerts(is_read);
    CREATE INDEX IF NOT EXISTS idx_alerts_severity      ON alerts(severity);
    CREATE INDEX IF NOT EXISTS idx_evidence_dc_id       ON evidence(detection_case_id);
    CREATE INDEX IF NOT EXISTS idx_evidence_case_id     ON evidence(case_id);
    CREATE INDEX IF NOT EXISTS idx_imp_dc_id            ON impersonation_checks(detection_case_id);
    CREATE INDEX IF NOT EXISTS idx_cases_status         ON cases(status);
    CREATE INDEX IF NOT EXISTS idx_signals_case_id      ON signals(case_id);
    CREATE INDEX IF NOT EXISTS idx_results_case_id      ON results(case_id);
    CREATE INDEX IF NOT EXISTS idx_logs_case_id         ON logs(case_id);
    CREATE INDEX IF NOT EXISTS idx_logs_dc_id           ON logs(detection_case_id);
    CREATE INDEX IF NOT EXISTS idx_logs_created_at      ON logs(created_at DESC);

    -- ── Record migration ──────────────────────────────────────────────────────
    INSERT INTO schema_migrations (version) VALUES ('001_initial_schema');
    RAISE NOTICE 'Migration 001_initial_schema applied successfully.';
END;
$$;

-- =============================================================================
-- End of 001_initial_schema.sql
-- =============================================================================
