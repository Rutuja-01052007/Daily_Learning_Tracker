-- Migration: 004_issue_tables
-- Description: Creates canonical issues, citizen reports, image metadata tables, and duplicate issue relationships.

-- 1. Issues Table (Canonical physical civic problem)
CREATE TABLE IF NOT EXISTS issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(150) NOT NULL,
    canonical_description TEXT,
    category_id UUID,
    severity VARCHAR(50),
    priority VARCHAR(50),
    current_status VARCHAR(50) DEFAULT 'REPORTED' NOT NULL,
    department_id UUID,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    address_line VARCHAR(255),
    area VARCHAR(100),
    city VARCHAR(100),
    postal_code VARCHAR(20),
    verified_by UUID,
    verified_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_issues_category FOREIGN KEY (category_id) REFERENCES issue_categories(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_severity FOREIGN KEY (severity) REFERENCES severity_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_priority FOREIGN KEY (priority) REFERENCES priority_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_status FOREIGN KEY (current_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_verified_by FOREIGN KEY (verified_by) REFERENCES users(id) ON DELETE SET NULL
);

-- 2. Reports Table (Individual citizen submissions)
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL,
    issue_id UUID, -- Nullable during intake until triaged/linked
    title VARCHAR(150),
    description TEXT NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_reports_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT
);

-- 3. Report Images Metadata Table
CREATE TABLE IF NOT EXISTS report_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL,
    storage_provider VARCHAR(50) NOT NULL,
    object_key VARCHAR(512) UNIQUE NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    width INTEGER,
    height INTEGER,
    uploaded_by_user_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_report_img_file_size CHECK (file_size_bytes > 0),
    CONSTRAINT fk_report_images_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT fk_report_images_uploader FOREIGN KEY (uploaded_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- 4. Issue Images Metadata Table
CREATE TABLE IF NOT EXISTS issue_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    storage_provider VARCHAR(50) NOT NULL,
    object_key VARCHAR(512) UNIQUE NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_issue_img_file_size CHECK (file_size_bytes > 0),
    CONSTRAINT fk_issue_images_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE
);

-- 5. Issue Relationships Table (Duplicate and merge tracking)
CREATE TABLE IF NOT EXISTS issue_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_issue_id UUID NOT NULL,
    target_issue_id UUID NOT NULL,
    relationship_type VARCHAR(50) NOT NULL,
    review_status VARCHAR(50) DEFAULT 'PENDING' NOT NULL,
    confidence_score NUMERIC(4, 3),
    detection_source VARCHAR(50) DEFAULT 'AI' NOT NULL,
    model_prediction_run_id UUID,
    reviewed_by_user_id UUID,
    reviewed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_no_self_relationship CHECK (source_issue_id <> target_issue_id),
    CONSTRAINT check_rel_confidence_bounds CHECK (confidence_score IS NULL OR (confidence_score >= 0.000 AND confidence_score <= 1.000)),
    CONSTRAINT fk_relationships_source FOREIGN KEY (source_issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_target FOREIGN KEY (target_issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_type FOREIGN KEY (relationship_type) REFERENCES relationship_types(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_reviewer FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id) ON DELETE SET NULL
);
