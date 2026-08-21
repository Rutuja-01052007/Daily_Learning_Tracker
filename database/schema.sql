-- =============================================================================
-- AI Investor Fraud & Impersonation Detection Platform
-- SIH Hackathon | PS13 Fintech / Smart Education
-- schema.sql — Run this ONCE on a fresh Supabase/PostgreSQL database
--              via the Supabase SQL Editor or psql.
-- =============================================================================

-- Enable uuid generation (safe no-op if already enabled on Supabase)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- TABLE: users
-- System users — investors and internal analysts who submit cases.
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL,
    email      TEXT        NOT NULL UNIQUE,
    role       TEXT        NOT NULL DEFAULT 'investor'
                   CHECK (role IN ('investor', 'analyst', 'admin')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  users       IS 'Platform users: investors who submit cases and analysts who review them.';
COMMENT ON COLUMN users.role  IS 'investor | analyst | admin';

-- =============================================================================
-- TABLE: detection_cases
-- Core table — one row per fraud-analysis request through the pipeline.
-- Replaces / unifies the old "cases" table with richer ML-output fields.
-- The old "cases" table is kept below for backwards compatibility.
-- =============================================================================
CREATE TABLE IF NOT EXISTS detection_cases (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID         REFERENCES users(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    -- What was submitted
    source_type      TEXT         NOT NULL
                         CHECK (source_type IN ('video', 'audio', 'text', 'chat', 'app', 'url')),

    -- ML engine output
    prediction       TEXT         NOT NULL DEFAULT 'PENDING'
                         CHECK (prediction IN (
                             'PENDING', 'DEEPFAKE', 'AUTHENTIC',
                             'IMPERSONATION', 'SUSPICIOUS', 'SAFE'
                         )),
    confidence_score NUMERIC(5,4) NOT NULL DEFAULT 0
                         CHECK (confidence_score >= 0 AND confidence_score <= 1),   -- 0.0 – 1.0
    risk_score       NUMERIC(5,2) NOT NULL DEFAULT 0
                         CHECK (risk_score >= 0 AND risk_score <= 100),             -- 0 – 100
    risk_level       TEXT         NOT NULL DEFAULT 'UNKNOWN'
                         CHECK (risk_level IN ('LOW', 'MEDIUM', 'HIGH', 'UNKNOWN')),

    -- Lifecycle
    status           TEXT         NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'processing', 'processed', 'flagged', 'cleared')),

    -- Human-readable summary from the Explanation Engine
    summary          TEXT
);

COMMENT ON TABLE  detection_cases                  IS 'Central fraud-analysis case. One row per user submission through the detection pipeline.';
COMMENT ON COLUMN detection_cases.confidence_score IS 'ML model confidence, 0.0 to 1.0 (multiply by 100 for percentage display).';
COMMENT ON COLUMN detection_cases.risk_score       IS 'Weighted composite risk score, 0 to 100.';
COMMENT ON COLUMN detection_cases.prediction       IS 'Final ML verdict: DEEPFAKE | AUTHENTIC | IMPERSONATION | SUSPICIOUS | SAFE | PENDING.';
COMMENT ON COLUMN detection_cases.risk_level       IS 'Derived tier: LOW (<40) | MEDIUM (40-70) | HIGH (>70).';

-- =============================================================================
-- TABLE: cases  (LEGACY — kept for backwards compatibility with existing db.py)
-- New code should write to detection_cases; this table stays untouched.
-- =============================================================================
CREATE TABLE IF NOT EXISTS cases (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at   TIMESTAMPTZ NOT NULL    DEFAULT NOW(),
    submitted_by TEXT        NOT NULL,
    source_type  TEXT        NOT NULL
                     CHECK (source_type IN ('video', 'audio', 'chat_text', 'url')),
    status       TEXT        NOT NULL    DEFAULT 'pending'
                     CHECK (status IN ('pending', 'processed', 'flagged', 'cleared'))
);

COMMENT ON TABLE cases IS 'Legacy cases table — retained for backward compatibility with existing db.py helpers.';

-- =============================================================================
-- TABLE: evidence
-- Metadata about every piece of submitted evidence (files, text, URLs).
-- Compatible with both detection_cases and the legacy cases table.
-- =============================================================================
CREATE TABLE IF NOT EXISTS evidence (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Link to new table (preferred) OR legacy table — one must be set
    detection_case_id    UUID        REFERENCES detection_cases(id) ON DELETE CASCADE,
    case_id              UUID        REFERENCES cases(id)           ON DELETE CASCADE,  -- legacy

    evidence_type        TEXT        NOT NULL
                             CHECK (evidence_type IN (
                                 'video_file', 'audio_file', 'image_file',
                                 'chat_message', 'text_document', 'url', 'app_url'
                             )),

    -- For binary files: Supabase Storage path (e.g. "evidence/case-abc/clip.mp4")
    -- For text/chat/url: the raw content itself
    file_path_or_content TEXT        NOT NULL,

    -- Friendly name shown in the UI (original filename or a label)
    filename             TEXT,

    uploaded_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  evidence                       IS 'Evidence items attached to a detection case. Stores Storage paths for files, raw text for messages/URLs.';
COMMENT ON COLUMN evidence.file_path_or_content  IS 'Supabase Storage object path for binary files; raw content for chat/URL evidence.';
COMMENT ON COLUMN evidence.filename              IS 'Original filename or a human-readable label for display.';

-- =============================================================================
-- TABLE: signals  (LEGACY — retained as-is)
-- Per-engine raw detection output. New code may also use this.
-- =============================================================================
CREATE TABLE IF NOT EXISTS signals (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id      UUID         NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
    signal_type  TEXT         NOT NULL
                     CHECK (signal_type IN ('deepfake', 'impersonation', 'scam_nlp', 'platform_url')),
    signal_score NUMERIC(5,2) NOT NULL
                     CHECK (signal_score >= 0 AND signal_score <= 100),
    raw_output   JSONB        NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE signals IS 'Per-engine detection signals (legacy). Used by existing db.py add_signal().';

-- =============================================================================
-- TABLE: results  (LEGACY — retained as-is)
-- Aggregated verdict per legacy case. Exactly one per case.
-- =============================================================================
CREATE TABLE IF NOT EXISTS results (
    id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id          UUID         NOT NULL UNIQUE REFERENCES cases(id) ON DELETE CASCADE,
    fraud_risk_score NUMERIC(5,2) NOT NULL CHECK (fraud_risk_score >= 0 AND fraud_risk_score <= 100),
    verdict          TEXT         NOT NULL CHECK (verdict IN ('low_risk', 'suspicious', 'high_risk')),
    explanation      JSONB        NOT NULL DEFAULT '{}',
        -- { "why_flagged": "...", "what_evidence": [...], "what_action": "..." }
    computed_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE results IS 'Final Risk+Explanation Engine verdict for legacy cases. One row per case.';

-- =============================================================================
-- TABLE: alerts
-- Auto-generated alerts for suspicious or high-risk detection cases.
-- =============================================================================
CREATE TABLE IF NOT EXISTS alerts (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    detection_case_id  UUID        NOT NULL REFERENCES detection_cases(id) ON DELETE CASCADE,
    alert_type         TEXT        NOT NULL
                           CHECK (alert_type IN (
                               'DEEPFAKE_DETECTED',
                               'IMPERSONATION_DETECTED',
                               'HIGH_RISK_CONTENT',
                               'SUSPICIOUS_ACTIVITY',
                               'PLATFORM_URL_FLAGGED',
                               'SCAM_NLP_DETECTED'
                           )),
    severity           TEXT        NOT NULL
                           CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
    message            TEXT        NOT NULL,
    is_read            BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  alerts           IS 'Alerts auto-generated when a detection case is flagged as suspicious or high-risk.';
COMMENT ON COLUMN alerts.is_read   IS 'Set to TRUE when a user/analyst has viewed the alert in the dashboard.';
COMMENT ON COLUMN alerts.alert_type IS 'Machine-readable alert category for dashboard filtering.';

-- =============================================================================
-- TABLE: impersonation_checks
-- Detailed impersonation-analysis record produced by the NLP/text engine.
-- One check per detection_case (or per text submission round).
-- =============================================================================
CREATE TABLE IF NOT EXISTS impersonation_checks (
    id                           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    detection_case_id            UUID         NOT NULL REFERENCES detection_cases(id) ON DELETE CASCADE,

    -- What the suspect claimed
    claimed_name                 TEXT,           -- e.g. "Rakesh Sharma, Motilal Oswal"
    claimed_registration_number  TEXT,           -- e.g. "INH000001234" (SEBI reg no.)

    -- NLP scores  (0.0 – 1.0)
    urgency_score                NUMERIC(4,3) NOT NULL DEFAULT 0
                                     CHECK (urgency_score >= 0 AND urgency_score <= 1),
    impersonation_score          NUMERIC(4,3) NOT NULL DEFAULT 0
                                     CHECK (impersonation_score >= 0 AND impersonation_score <= 1),

    -- Final verdict from the text/NLP engine
    prediction                   TEXT         NOT NULL DEFAULT 'PENDING'
                                     CHECK (prediction IN ('PENDING', 'IMPERSONATION', 'SUSPICIOUS', 'LEGITIMATE')),

    -- Structured flags (stored as JSONB for flexibility)
    flags                        JSONB        NOT NULL DEFAULT '{}',
        -- Example: {
        --   "guaranteed_returns": true,
        --   "urgency_language": true,
        --   "unverified_sebi_claim": true,
        --   "direct_payment_request": false
        -- }

    created_at                   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  impersonation_checks                    IS 'NLP-engine output for text/chat submissions analysed for impersonation patterns.';
COMMENT ON COLUMN impersonation_checks.urgency_score      IS 'Probability that the message uses urgency manipulation language (0-1).';
COMMENT ON COLUMN impersonation_checks.impersonation_score IS 'Probability that the sender is impersonating a registered advisor (0-1).';
COMMENT ON COLUMN impersonation_checks.flags              IS 'Detected scam indicators as a JSON object of boolean flags.';

-- =============================================================================
-- TABLE: logs  (LEGACY — retained, extended with detection_case_id link)
-- =============================================================================
CREATE TABLE IF NOT EXISTS logs (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    case_id            UUID        REFERENCES cases(id)           ON DELETE SET NULL,  -- legacy
    detection_case_id  UUID        REFERENCES detection_cases(id) ON DELETE SET NULL,  -- new
    event_type         TEXT        NOT NULL,
    message            TEXT        NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  logs                    IS 'Audit and debug log for all pipeline events. Accepts both legacy case_id and new detection_case_id.';
COMMENT ON COLUMN logs.event_type         IS 'Category: engine_called | error | alert_sent | status_change | ...';

-- =============================================================================
-- INDEXES
-- =============================================================================

-- users
CREATE INDEX IF NOT EXISTS idx_users_email             ON users(email);

-- detection_cases — most queried fields
CREATE INDEX IF NOT EXISTS idx_dc_user_id              ON detection_cases(user_id);
CREATE INDEX IF NOT EXISTS idx_dc_created_at           ON detection_cases(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_dc_status               ON detection_cases(status);
CREATE INDEX IF NOT EXISTS idx_dc_risk_level           ON detection_cases(risk_level);
CREATE INDEX IF NOT EXISTS idx_dc_prediction           ON detection_cases(prediction);

-- alerts
CREATE INDEX IF NOT EXISTS idx_alerts_case_id          ON alerts(detection_case_id);
CREATE INDEX IF NOT EXISTS idx_alerts_is_read          ON alerts(is_read);
CREATE INDEX IF NOT EXISTS idx_alerts_severity         ON alerts(severity);

-- evidence
CREATE INDEX IF NOT EXISTS idx_evidence_dc_id          ON evidence(detection_case_id);
CREATE INDEX IF NOT EXISTS idx_evidence_case_id        ON evidence(case_id);  -- legacy

-- impersonation_checks
CREATE INDEX IF NOT EXISTS idx_imp_dc_id               ON impersonation_checks(detection_case_id);

-- legacy tables
CREATE INDEX IF NOT EXISTS idx_cases_status            ON cases(status);
CREATE INDEX IF NOT EXISTS idx_signals_case_id         ON signals(case_id);
CREATE INDEX IF NOT EXISTS idx_results_case_id         ON results(case_id);
CREATE INDEX IF NOT EXISTS idx_logs_case_id            ON logs(case_id);
CREATE INDEX IF NOT EXISTS idx_logs_dc_id              ON logs(detection_case_id);
CREATE INDEX IF NOT EXISTS idx_logs_created_at         ON logs(created_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS)
-- DISABLED for the hackathon demo.
-- Uncomment the block below to enable before any production deployment.
-- =============================================================================

/*
ALTER TABLE users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE detection_cases     ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidence            ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE impersonation_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE cases               ENABLE ROW LEVEL SECURITY;
ALTER TABLE signals             ENABLE ROW LEVEL SECURITY;
ALTER TABLE results             ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs                ENABLE ROW LEVEL SECURITY;

-- Permissive policies: authenticated users can read/write everything.
-- Tighten these before production (e.g. user_id = auth.uid()).

CREATE POLICY "auth_read_detection_cases"
    ON detection_cases FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert_detection_cases"
    ON detection_cases FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "auth_update_detection_cases"
    ON detection_cases FOR UPDATE USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_alerts"
    ON alerts FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert_alerts"
    ON alerts FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "auth_update_alerts"
    ON alerts FOR UPDATE USING (auth.role() = 'authenticated');

CREATE POLICY "auth_read_evidence"
    ON evidence FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert_evidence"
    ON evidence FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "auth_read_imp_checks"
    ON impersonation_checks FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "auth_insert_imp_checks"
    ON impersonation_checks FOR INSERT WITH CHECK (auth.role() = 'authenticated');
*/

-- =============================================================================
-- End of schema.sql
-- =============================================================================
