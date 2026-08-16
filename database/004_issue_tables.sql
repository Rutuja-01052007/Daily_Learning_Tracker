-- Migration: 004_issue_tables
-- Description: Creates schemas for issues, reports, image metadata, and issue relationships.

-- 1. Issues Table (Canonical operational record)
CREATE TABLE IF NOT EXISTS issues (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(150) NOT NULL,
    description TEXT,
    approved_category_id UUID,
    approved_severity VARCHAR(50),
    approved_priority VARCHAR(50),
    current_status VARCHAR(50) DEFAULT 'REPORTED' NOT NULL,
    department_id UUID,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    address_line VARCHAR(255),
    area VARCHAR(100),
    city VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(20),
    landmark VARCHAR(255),
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_issues_category FOREIGN KEY (approved_category_id) REFERENCES issue_categories(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_severity FOREIGN KEY (approved_severity) REFERENCES severity_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_priority FOREIGN KEY (approved_priority) REFERENCES priority_levels(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_status FOREIGN KEY (current_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_issues_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT
);

-- 2. Reports Table (Citizen submissions)
CREATE TABLE IF NOT EXISTS reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL,
    issue_id UUID,
    description TEXT NOT NULL,
    location GEOGRAPHY(Point, 4326) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_reports_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT
);

-- 3. Central Image Metadata Table
CREATE TABLE IF NOT EXISTS image_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    storage_provider VARCHAR(50) NOT NULL,
    object_key VARCHAR(512) UNIQUE NOT NULL,
    public_url TEXT NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    width INTEGER,
    height INTEGER,
    uploaded_by UUID,
    moderation_status VARCHAR(50) DEFAULT 'PENDING' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_file_size_positive CHECK (file_size_bytes > 0),
    CONSTRAINT check_width_positive CHECK (width > 0),
    CONSTRAINT check_height_positive CHECK (height > 0),
    CONSTRAINT fk_image_metadata_uploader FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE SET NULL
);

-- 4. Report Images Junction Table
CREATE TABLE IF NOT EXISTS report_images (
    report_id UUID NOT NULL,
    image_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_report_images PRIMARY KEY (report_id, image_id),
    CONSTRAINT fk_report_images_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE CASCADE,
    CONSTRAINT fk_report_images_image FOREIGN KEY (image_id) REFERENCES image_metadata(id) ON DELETE CASCADE
);

-- 5. Issue Images Junction Table
CREATE TABLE IF NOT EXISTS issue_images (
    issue_id UUID NOT NULL,
    image_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_issue_images PRIMARY KEY (issue_id, image_id),
    CONSTRAINT fk_issue_images_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
    CONSTRAINT fk_issue_images_image FOREIGN KEY (image_id) REFERENCES image_metadata(id) ON DELETE CASCADE
);

-- 6. Issue Relationships Table (Duplicate and merge tracking)
CREATE TABLE IF NOT EXISTS issue_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_issue_id UUID NOT NULL,
    target_issue_id UUID NOT NULL,
    relationship_type VARCHAR(50) NOT NULL,
    confidence_score NUMERIC(4, 3) NOT NULL,
    detection_source VARCHAR(50) DEFAULT 'AI' NOT NULL,
    review_status VARCHAR(50) DEFAULT 'PENDING' NOT NULL,
    reviewed_by UUID,
    reviewed_at TIMESTAMPTZ,
    review_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_no_self_relationship CHECK (source_issue_id != target_issue_id),
    CONSTRAINT check_confidence_bounds CHECK (confidence_score >= 0.000 AND confidence_score <= 1.000),
    CONSTRAINT fk_relationships_source FOREIGN KEY (source_issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_target FOREIGN KEY (target_issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_type FOREIGN KEY (relationship_type) REFERENCES relationship_types(id) ON DELETE RESTRICT,
    CONSTRAINT fk_relationships_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL
);
