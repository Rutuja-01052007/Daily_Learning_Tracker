-- Migration: 005_ai_tables
-- Description: Creates ai_models, ai_prediction_runs, ai_predictions, and model_training_runs tables
--              for AI/ML inference, recommendations, and dataset provenance.
--
-- Schema design notes:
--   ai_predictions stores BOTH raw segmentation detections (per-object bbox + polygon)
--   AND recommendation rows (category, severity, priority). The prediction_type column
--   discriminates between row kinds.
--
--   Column naming follows architecture_spec.md §18 exactly so that
--   queries_and_transactions.sql and 010_test_data.sql work without modification.

-- ============================================================================
-- 1. AI Models Registry Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_models (
    id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    model_name                TEXT        NOT NULL,
    model_version             TEXT        NOT NULL,
    -- model_type: e.g. 'SEGMENTATION', 'CLASSIFICATION_AND_PRIORITY'
    model_type                TEXT        NOT NULL,
    -- task_type: fine-grained task label, e.g. 'image_segmentation'
    task_type                 TEXT        NOT NULL,
    framework                 TEXT        NOT NULL,
    -- class_mapping: JSON object mapping class_id (str) -> class_name
    class_mapping             JSONB,
    -- Artifact storage references (never store the binary here)
    artifact_storage_provider TEXT,
    artifact_object_key       TEXT,
    artifact_checksum         TEXT,
    -- Training dataset provenance
    training_dataset_name     TEXT,
    training_dataset_url      TEXT,
    training_dataset_license  TEXT,
    trained_at                TIMESTAMPTZ,
    -- Evaluation metrics snapshot
    metrics                   JSONB,
    is_active                 BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT unique_model_name_version
        UNIQUE (model_name, model_version),
    -- An active model must have metrics and a stored artifact key
    CONSTRAINT check_active_model_requirements
        CHECK (is_active = FALSE OR (metrics IS NOT NULL AND artifact_object_key IS NOT NULL))
);

-- Only one active version per model_name at a time
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_model
    ON ai_models (model_name)
    WHERE is_active = TRUE;

-- ============================================================================
-- 2. AI Prediction Runs Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_prediction_runs (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Either issue_id or report_id must be present (or both)
    issue_id        UUID        REFERENCES issues(id)        ON DELETE CASCADE,
    report_id       UUID        REFERENCES reports(id)       ON DELETE CASCADE,
    -- Optional: the specific image that triggered this run
    source_image_id UUID        REFERENCES report_images(id) ON DELETE SET NULL,
    model_id        UUID        NOT NULL REFERENCES ai_models(id) ON DELETE RESTRICT,
    run_status      TEXT        NOT NULL DEFAULT 'PENDING',
    -- SHA-256 of the input image bytes (not stored here, just the hash for idempotency)
    input_checksum  TEXT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT check_ai_run_status
        CHECK (run_status IN ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED', 'SKIPPED')),
    -- At least one target entity must be set
    CONSTRAINT check_target_entity_present
        CHECK (issue_id IS NOT NULL OR report_id IS NOT NULL)
);

-- ============================================================================
-- 3. AI Predictions Table
-- ============================================================================
-- Each row is one inference output.  Depending on prediction_type:
--
--   IMAGE_SEGMENTATION      → class_id/class_name/confidence/bounding_box/segmentation_polygon
--   CATEGORY_RECOMMENDATION → predicted_category_id, confidence_score
--   SEVERITY_RECOMMENDATION → predicted_severity, confidence_score
--   PRIORITY_RECOMMENDATION → predicted_priority, confidence_score
--   DUPLICATE_SCORE         → duplicate_score
--   CLASSIFICATION          → predicted_category_id, predicted_severity, predicted_priority (legacy support)
--
-- Columns that are not applicable to a given type are left NULL.
-- ============================================================================
CREATE TABLE IF NOT EXISTS ai_predictions (
    id                    UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_run_id     UUID          NOT NULL REFERENCES ai_prediction_runs(id) ON DELETE CASCADE,

    -- Discriminator: what kind of output is this row?
    prediction_type       TEXT          NOT NULL,

    -- ── Image-segmentation detection fields ──────────────────────────────────
    class_name            TEXT,           -- 'pothole', 'road_crack', 'manhole'
    class_id              INTEGER,        -- 0, 1, 2 (matches training class map)
    confidence_score      NUMERIC(5, 4),  -- [0.0000, 1.0000]
    bounding_box          JSONB,          -- {x1,y1,x2,y2} pixel coords
    segmentation_polygon  JSONB,          -- [[x,y], ...] pixel coords list
    -- Optional: object-storage key for the saved overlay/mask image
    mask_storage_key      TEXT,

    -- ── Recommendation / classification fields ────────────────────────────────
    -- Foreign key to issue_categories (used by CATEGORY_RECOMMENDATION and CLASSIFICATION)
    predicted_category_id UUID          REFERENCES issue_categories(id) ON DELETE RESTRICT,
    -- FK strings into severity_levels / priority_levels lookup tables
    predicted_severity    TEXT          REFERENCES severity_levels(id)  ON DELETE RESTRICT,
    predicted_priority    TEXT          REFERENCES priority_levels(id)  ON DELETE RESTRICT,
    -- Duplicate-detection score
    duplicate_score       NUMERIC(4, 3),

    -- ── Raw output ────────────────────────────────────────────────────────────
    raw_output            JSONB,          -- Full model logits / metadata for audit

    created_at            TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT check_pred_confidence
        CHECK (confidence_score IS NULL OR (confidence_score >= 0.0000 AND confidence_score <= 1.0000)),
    CONSTRAINT check_duplicate_score_bounds
        CHECK (duplicate_score IS NULL OR (duplicate_score >= 0.000 AND duplicate_score <= 1.000)),
    CONSTRAINT check_prediction_type
        CHECK (prediction_type IN (
            'IMAGE_SEGMENTATION',
            'CATEGORY_RECOMMENDATION',
            'SEVERITY_RECOMMENDATION',
            'PRIORITY_RECOMMENDATION',
            'DUPLICATE_SCORE',
            'CLASSIFICATION'   -- legacy / combined classification rows
        ))
);

-- ============================================================================
-- 4. Model Training Runs Table  (Reproducibility & training metric history)
-- ============================================================================
CREATE TABLE IF NOT EXISTS model_training_runs (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id          UUID        NOT NULL REFERENCES ai_models(id) ON DELETE CASCADE,
    training_run_name TEXT        NOT NULL,
    -- Full hyperparameter dict (epochs, batch, imgsz, seed, patience, …)
    hyperparameters   JSONB       NOT NULL,
    -- Aggregate loss values
    train_loss        NUMERIC(8, 6),
    val_loss          NUMERIC(8, 6),
    -- Held-out test metrics (filled after evaluate_model.py runs)
    test_precision    NUMERIC(5, 4),
    test_recall       NUMERIC(5, 4),
    test_map50        NUMERIC(5, 4),
    test_map50_95     NUMERIC(5, 4),
    -- Training device and environment
    training_device   TEXT,          -- e.g. 'cuda:0 (Tesla T4)', 'cpu'
    framework_version TEXT,          -- e.g. 'ultralytics==8.2.0'
    total_duration_s  INTEGER,       -- Training wall-clock seconds
    started_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at      TIMESTAMPTZ,
    status            TEXT        NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT check_training_status
        CHECK (status IN ('RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'))
);
