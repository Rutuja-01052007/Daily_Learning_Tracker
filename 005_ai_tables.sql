-- Migration: 005_ai_tables
-- Description: Creates schemas for AI prediction runs, individual predictions, dataset registry, and training samples.

-- 1. AI Prediction Runs Table
CREATE TABLE IF NOT EXISTS ai_prediction_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID,
    report_id UUID,
    model_name VARCHAR(100) NOT NULL,
    model_version VARCHAR(50) NOT NULL,
    pipeline_version VARCHAR(50) NOT NULL,
    input_hash VARCHAR(64),
    status VARCHAR(50) DEFAULT 'PENDING' NOT NULL,
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_ai_status CHECK (status IN ('PENDING', 'RUNNING', 'COMPLETED', 'FAILED')),
    CONSTRAINT fk_ai_runs_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
    CONSTRAINT fk_ai_runs_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE
);

-- 2. AI Predictions Table
CREATE TABLE IF NOT EXISTS ai_predictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction_run_id UUID NOT NULL,
    prediction_type VARCHAR(50) NOT NULL,
    predicted_category_id UUID,
    predicted_severity VARCHAR(50),
    predicted_priority VARCHAR(50),
    confidence_score NUMERIC(4, 3),
    duplicate_score NUMERIC(4, 3),
    target_issue_id UUID,
    raw_output JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_pred_confidence CHECK (confidence_score >= 0.000 AND confidence_score <= 1.000),
    CONSTRAINT check_pred_duplicate CHECK (duplicate_score >= 0.000 AND duplicate_score <= 1.000),
    CONSTRAINT check_prediction_type CHECK (prediction_type IN ('CLASSIFICATION', 'SEVERITY', 'PRIORITY', 'DUPLICATE')),
    CONSTRAINT fk_ai_predictions_run FOREIGN KEY (prediction_run_id) REFERENCES ai_prediction_runs(id) ON DELETE CASCADE,
    CONSTRAINT fk_ai_predictions_category FOREIGN KEY (predicted_category_id) REFERENCES issue_categories(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ai_predictions_severity FOREIGN KEY (predicted_severity) REFERENCES severity_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ai_predictions_priority FOREIGN KEY (predicted_priority) REFERENCES priority_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_ai_predictions_target FOREIGN KEY (target_issue_id) REFERENCES issues(id) ON DELETE RESTRICT
);

-- 3. Dataset Registry Table (ML models pipeline metadata)
CREATE TABLE IF NOT EXISTS dataset_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(150) UNIQUE NOT NULL,
    source_url TEXT NOT NULL,
    download_url TEXT,
    license VARCHAR(100) NOT NULL,
    version VARCHAR(50) NOT NULL,
    download_date TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    sample_count INTEGER DEFAULT 0 NOT NULL,
    label_set JSONB NOT NULL,
    preprocessing_version VARCHAR(50) NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    usage_restrictions TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_sample_count_positive CHECK (sample_count >= 0)
);

-- 4. Dataset Samples Table (Record of images and formats used in model pipeline training splits)
CREATE TABLE IF NOT EXISTS dataset_samples (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    dataset_id UUID NOT NULL,
    original_file_path TEXT NOT NULL,
    split VARCHAR(20) NOT NULL,
    normalized_label VARCHAR(100) NOT NULL,
    file_checksum VARCHAR(64) NOT NULL,
    is_corrupted BOOLEAN DEFAULT FALSE NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_dataset_split CHECK (split IN ('TRAIN', 'VALIDATION', 'TEST')),
    CONSTRAINT fk_dataset_samples_registry FOREIGN KEY (dataset_id) REFERENCES dataset_registry(id) ON DELETE RESTRICT
);
