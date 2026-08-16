-- Migration: 011_dataset_registry
-- Description: Creates the dataset_registry table to record provenance, license status,
--              attribution requirements, and usage restrictions for every approved training dataset.
--
-- Business rule: A dataset MUST NOT be used for training until its license_status is
-- either 'APPROVED' or 'EDUCATIONAL_ONLY'. If license information is ambiguous or conflicts,
-- the record must be set to 'LICENSE_REVIEW_REQUIRED' and training halted.
--
-- This table is the authoritative single source of truth for ML dataset governance.

-- ============================================================================
-- 1. Dataset Registry Table
-- ============================================================================
CREATE TABLE IF NOT EXISTS dataset_registry (
    id                   UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Canonical identifier matching Kaggle dataset slug or internal name
    dataset_id           TEXT         UNIQUE NOT NULL,
    name                 TEXT         NOT NULL,
    -- Source provenance
    source_url           TEXT         NOT NULL,
    source_version       TEXT,        -- e.g. 'v1', Kaggle version number at download time
    download_date        DATE,        -- Date the dataset was downloaded / ingested
    -- License metadata
    license_name         TEXT,        -- e.g. 'MIT', 'CC BY 4.0', 'Unknown'
    license_url          TEXT,        -- Direct URL to the license text
    attribution_required BOOLEAN      NOT NULL DEFAULT TRUE,
    attribution_text     TEXT,        -- Required credit string if attribution_required = TRUE
    -- Governance status
    -- APPROVED              → Explicitly verified for the declared usage
    -- EDUCATIONAL_ONLY      → Permitted for educational/hackathon demonstration only
    -- LICENSE_REVIEW_REQUIRED → Ambiguous, conflicting, or unknown license — TRAINING BLOCKED
    -- PENDING               → Not yet reviewed
    license_status       TEXT         NOT NULL DEFAULT 'PENDING',
    usage_restriction    TEXT,        -- Free-text summary of permitted use
    -- Optional: link to the original (non-Kaggle) dataset source
    original_source_url  TEXT,
    -- Internal notes (reviewer, date reviewed, conflicts found, etc.)
    notes                TEXT,
    reviewed_by          TEXT,        -- Reviewer name or "automated"
    reviewed_at          TIMESTAMPTZ,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT check_license_status
        CHECK (license_status IN (
            'APPROVED',
            'EDUCATIONAL_ONLY',
            'LICENSE_REVIEW_REQUIRED',
            'PENDING'
        ))
);

CREATE INDEX IF NOT EXISTS idx_dataset_registry_status
    ON dataset_registry (license_status);

-- ============================================================================
-- 2. Seed: Approved Road Damage Dataset
-- ============================================================================
-- License audit performed on 2026-08-16.
-- The Kaggle page for lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes
-- shows a "MIT" license tag on the dataset card. However, the underlying images may
-- originate from the RDD2022 / RDDCF research dataset which carries an academic-use
-- restriction. Until the original source license is explicitly confirmed to allow
-- commercial use, this dataset is marked EDUCATIONAL_ONLY.
--
-- Reference: https://www.kaggle.com/datasets/lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes
-- Do NOT change license_status to APPROVED without explicit legal sign-off.

INSERT INTO dataset_registry (
    id,
    dataset_id,
    name,
    source_url,
    source_version,
    download_date,
    license_name,
    license_url,
    attribution_required,
    attribution_text,
    license_status,
    usage_restriction,
    original_source_url,
    notes,
    reviewed_by,
    reviewed_at
) VALUES (
    'a1b2c3d4-0001-0001-0001-a1b2c3d40001',
    'lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes',
    'Road Damage Dataset: Potholes, Cracks and Manholes',
    'https://www.kaggle.com/datasets/lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes',
    'v1',                    -- Kaggle version at time of download; update when re-downloaded
    '2026-08-16',
    'MIT',                   -- License shown on Kaggle dataset card
    'https://www.kaggle.com/datasets/lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes',
    TRUE,
    'Dataset by Lorenzo Arcioni on Kaggle. Original road-damage imagery sources apply.',
    'EDUCATIONAL_ONLY',      -- See note above — do NOT promote to APPROVED without legal sign-off
    'Educational and hackathon demonstration use only. Commercial use requires explicit license verification of original imagery sources.',
    'https://github.com/sekilab/RoadDamageDetector',  -- Potential original source
    'Kaggle card shows MIT. Possible underlying academic dataset (RDD/RDDCF). '
        'License_status set to EDUCATIONAL_ONLY pending verification of original imagery rights. '
        'If license information conflicts, status must be escalated to LICENSE_REVIEW_REQUIRED.',
    'automated_audit_v1',
    '2026-08-16T21:00:00+05:30'
) ON CONFLICT (dataset_id) DO UPDATE
    SET
        source_version    = EXCLUDED.source_version,
        download_date     = EXCLUDED.download_date,
        license_name      = EXCLUDED.license_name,
        notes             = EXCLUDED.notes,
        updated_at        = NOW();
