-- =============================================================================
-- queries_and_transactions.sql
-- AI Investor Fraud & Impersonation Detection Platform
-- SIH Hackathon | PS13 Fintech / Smart Education
--
-- Useful named queries for the backend API and dashboard.
-- Copy individual blocks into your FastAPI/SQLAlchemy code or run directly
-- in the Supabase SQL Editor for ad-hoc analysis.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- Q1. Get all recent detection cases (most recent first)
--     Used by: GET /cases
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.id,
    dc.created_at,
    dc.source_type,
    dc.prediction,
    dc.confidence_score,
    dc.risk_score,
    dc.risk_level,
    dc.status,
    dc.summary,
    u.name  AS user_name,
    u.email AS user_email
FROM  detection_cases dc
LEFT JOIN users u ON u.id = dc.user_id
ORDER BY dc.created_at DESC
LIMIT 50;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q2. Get all HIGH risk / flagged fraud cases
--     Used by: Dashboard "Fraud Alerts" panel, GET /cases?risk=HIGH
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.id,
    dc.created_at,
    dc.source_type,
    dc.prediction,
    dc.confidence_score,
    dc.risk_score,
    dc.risk_level,
    dc.status,
    dc.summary,
    u.name  AS user_name,
    u.email AS user_email
FROM  detection_cases dc
LEFT JOIN users u ON u.id = dc.user_id
WHERE dc.risk_level = 'HIGH'
  AND dc.status     = 'flagged'
ORDER BY dc.risk_score DESC, dc.created_at DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q3. Dashboard statistics — summary counts
--     Used by: GET /dashboard/stats
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    COUNT(*)                                                          AS total_cases,
    COUNT(*) FILTER (WHERE risk_level = 'HIGH')                      AS high_risk_count,
    COUNT(*) FILTER (WHERE risk_level = 'MEDIUM')                    AS medium_risk_count,
    COUNT(*) FILTER (WHERE risk_level = 'LOW')                       AS low_risk_count,
    COUNT(*) FILTER (WHERE status = 'flagged')                       AS flagged_count,
    COUNT(*) FILTER (WHERE status = 'cleared')                       AS cleared_count,
    COUNT(*) FILTER (WHERE status = 'pending')                       AS pending_count,
    ROUND(AVG(risk_score), 2)                                        AS avg_risk_score,
    COUNT(*) FILTER (WHERE prediction = 'DEEPFAKE')                  AS deepfake_count,
    COUNT(*) FILTER (WHERE prediction IN ('SUSPICIOUS','IMPERSONATION')) AS suspicious_count,
    COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS cases_last_24h
FROM detection_cases;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q4. Count cases grouped by risk level
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    risk_level,
    COUNT(*) AS case_count
FROM  detection_cases
GROUP BY risk_level
ORDER BY
    CASE risk_level
        WHEN 'HIGH'    THEN 1
        WHEN 'MEDIUM'  THEN 2
        WHEN 'LOW'     THEN 3
        ELSE 4
    END;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q5. Count cases grouped by prediction type
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    prediction,
    COUNT(*) AS case_count,
    ROUND(AVG(confidence_score) * 100, 1) AS avg_confidence_pct
FROM  detection_cases
GROUP BY prediction
ORDER BY case_count DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q6. Get a single detection case with all its evidence
--     Used by: GET /cases/:id
--     Replace :case_id with the actual UUID.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.*,
    u.name          AS user_name,
    u.email         AS user_email,
    json_agg(
        json_build_object(
            'id',                   e.id,
            'evidence_type',        e.evidence_type,
            'file_path_or_content', e.file_path_or_content,
            'filename',             e.filename,
            'uploaded_at',          e.uploaded_at
        ) ORDER BY e.uploaded_at
    ) FILTER (WHERE e.id IS NOT NULL) AS evidence_list
FROM  detection_cases dc
LEFT JOIN users    u ON u.id = dc.user_id
LEFT JOIN evidence e ON e.detection_case_id = dc.id
WHERE dc.id = 'bbbbbbbb-0000-0000-0000-000000000001'  -- replace with :case_id
GROUP BY dc.id, u.name, u.email;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q7. Get a detection case with its alerts
--     Used by: GET /cases/:id/alerts
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.id            AS case_id,
    dc.prediction,
    dc.risk_level,
    a.id             AS alert_id,
    a.alert_type,
    a.severity,
    a.message,
    a.is_read,
    a.created_at     AS alert_created_at
FROM  detection_cases dc
JOIN  alerts a ON a.detection_case_id = dc.id
WHERE dc.id = 'bbbbbbbb-0000-0000-0000-000000000001'  -- replace with :case_id
ORDER BY a.created_at DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q8. Get all UNREAD alerts (newest first)
--     Used by: GET /alerts?unread=true  (notification badge count)
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    a.id,
    a.alert_type,
    a.severity,
    a.message,
    a.created_at,
    dc.source_type,
    dc.prediction,
    dc.risk_score,
    u.name  AS user_name,
    u.email AS user_email
FROM  alerts a
JOIN  detection_cases dc ON dc.id = a.detection_case_id
LEFT JOIN users u ON u.id = dc.user_id
WHERE a.is_read = FALSE
ORDER BY
    CASE a.severity
        WHEN 'CRITICAL' THEN 1
        WHEN 'HIGH'     THEN 2
        WHEN 'MEDIUM'   THEN 3
        ELSE 4
    END,
    a.created_at DESC;


-- ─────────────────────────────────────────────────────────────────────────────
-- Q9. Get a specific user's detection history
--     Used by: GET /users/:user_id/cases
-- ─────────────────────────────────────────────────────────────────────────────
SELECT
    dc.id,
    dc.created_at,
    dc.source_type,
    dc.prediction,
    dc.risk_level,
    dc.risk_score,
    dc.status,
    dc.summary,
    (SELECT COUNT(*) FROM alerts a WHERE a.detection_case_id = dc.id)          AS alert_count,
    (SELECT COUNT(*) FROM evidence e WHERE e.detection_case_id = dc.id)        AS evidence_count
FROM  detection_cases dc
WHERE dc.user_id = 'aaaaaaaa-0000-0000-0000-000000000001'  -- replace with :user_id
ORDER BY dc.created_at DESC;


-- =============================================================================
-- TRANSACTION: Safe end-to-end case creation with alert generation
-- Used by: POST /detect  (backend calls this after ML engines return scores)
-- Parameters to substitute:
--   :user_id, :source_type, :prediction, :confidence_score,
--   :risk_score, :risk_level, :summary,
--   :evidence_type, :file_path_or_content, :filename
-- =============================================================================

BEGIN;

    -- Step 1: Insert the detection case
    WITH new_case AS (
        INSERT INTO detection_cases (
            user_id,
            source_type,
            prediction,
            confidence_score,
            risk_score,
            risk_level,
            status,
            summary
        ) VALUES (
            'aaaaaaaa-0000-0000-0000-000000000001',  -- :user_id
            'video',                                  -- :source_type
            'DEEPFAKE',                               -- :prediction
            0.8800,                                   -- :confidence_score  (0.0–1.0)
            82.50,                                    -- :risk_score        (0–100)
            'HIGH',                                   -- :risk_level
            'processing',
            'Deepfake face-swap detected with 88% confidence in submitted video.'  -- :summary
        )
        RETURNING id, risk_level
    ),

    -- Step 2: Attach evidence metadata
    new_evidence AS (
        INSERT INTO evidence (detection_case_id, evidence_type, file_path_or_content, filename)
        SELECT
            id,
            'video_file',                                        -- :evidence_type
            'evidence/' || id || '/sample.mp4',                  -- :file_path_or_content
            'sample.mp4'                                         -- :filename
        FROM new_case
        RETURNING detection_case_id
    ),

    -- Step 3: Update status to 'processed' after evidence is stored
    updated_case AS (
        UPDATE detection_cases
        SET status = 'flagged'
        WHERE id = (SELECT detection_case_id FROM new_evidence)
          AND risk_level = 'HIGH'
        RETURNING id, risk_level
    )

    -- Step 4: Generate alert if HIGH risk
    INSERT INTO alerts (detection_case_id, alert_type, severity, message)
    SELECT
        id,
        'DEEPFAKE_DETECTED',
        'HIGH',
        'A submitted video was flagged as a deepfake (88% confidence). Risk score: 82.5. Immediate review required.'
    FROM updated_case
    WHERE risk_level = 'HIGH';

COMMIT;

-- If any step fails, the entire transaction rolls back automatically.
-- In Python (supabase-py), use an RPC function or psycopg2 for raw transactions.


-- =============================================================================
-- UTILITY: Mark an alert as read
-- Used by: PATCH /alerts/:alert_id/read
-- =============================================================================
UPDATE alerts
SET    is_read = TRUE
WHERE  id = 'replace-with-alert-uuid';


-- =============================================================================
-- UTILITY: Dashboard 7-day trend (cases per day)
-- =============================================================================
SELECT
    DATE(created_at AT TIME ZONE 'Asia/Kolkata') AS day,
    COUNT(*)                                      AS total,
    COUNT(*) FILTER (WHERE risk_level = 'HIGH')  AS high_risk,
    COUNT(*) FILTER (WHERE prediction = 'DEEPFAKE') AS deepfakes
FROM  detection_cases
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY day
ORDER BY day;


-- =============================================================================
-- UTILITY: Impersonation stats for text/chat cases
-- =============================================================================
SELECT
    ic.prediction,
    COUNT(*)                           AS count,
    ROUND(AVG(ic.impersonation_score), 3) AS avg_impersonation_score,
    ROUND(AVG(ic.urgency_score), 3)       AS avg_urgency_score
FROM  impersonation_checks ic
GROUP BY ic.prediction
ORDER BY count DESC;


-- =============================================================================
-- End of queries_and_transactions.sql
-- =============================================================================
