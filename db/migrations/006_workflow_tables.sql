-- Migration: 006_workflow_tables
-- Description: Creates workflow tables (assignments, events, status history, resolution proofs, proof images, notifications, feedback, audit logs).

-- 1. Assignments Table
CREATE TABLE IF NOT EXISTS assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    worker_id UUID NOT NULL,
    department_id UUID,
    assigned_by UUID NOT NULL,
    assignment_status VARCHAR(50) DEFAULT 'ASSIGNED' NOT NULL,
    assigned_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    accepted_at TIMESTAMPTZ,
    rejected_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    reassignment_reason TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_assignments_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assignments_worker FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assignments_department FOREIGN KEY (department_id) REFERENCES departments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assignments_by FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assignments_status FOREIGN KEY (assignment_status) REFERENCES assignment_statuses(id) ON DELETE RESTRICT
);

-- 2. Assignment Events Table (Auditable event history)
CREATE TABLE IF NOT EXISTS assignment_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    actor_user_id UUID NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_assign_events_id FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE CASCADE,
    CONSTRAINT fk_assign_events_actor FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- 3. Issue Status History Table
CREATE TABLE IF NOT EXISTS issue_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    previous_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    changed_by_user_id UUID,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_status_history_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
    CONSTRAINT fk_status_history_prev FOREIGN KEY (previous_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_status_history_new FOREIGN KEY (new_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_status_history_by FOREIGN KEY (changed_by_user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- 4. Resolution Proofs Table
CREATE TABLE IF NOT EXISTS resolution_proofs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    assignment_id UUID NOT NULL,
    submitted_by_worker_id UUID NOT NULL,
    status VARCHAR(50) DEFAULT 'SUBMITTED' NOT NULL,
    description TEXT,
    submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reviewed_by_user_id UUID,
    reviewed_at TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_proofs_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_assignment FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_worker FOREIGN KEY (submitted_by_worker_id) REFERENCES workers(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_status FOREIGN KEY (status) REFERENCES resolution_proof_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_reviewer FOREIGN KEY (reviewed_by_user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- 5. Resolution Proof Images Metadata Table (Separated worker evidence photos)
CREATE TABLE IF NOT EXISTS resolution_proof_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resolution_proof_id UUID NOT NULL,
    storage_provider VARCHAR(50) NOT NULL,
    object_key VARCHAR(512) UNIQUE NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    checksum VARCHAR(64) NOT NULL,
    image_type VARCHAR(50) NOT NULL, -- e.g. BEFORE, AFTER, COMPLETION, OTHER
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_proof_img_type CHECK (image_type IN ('BEFORE', 'AFTER', 'COMPLETION', 'OTHER')),
    CONSTRAINT check_proof_img_size CHECK (file_size_bytes > 0),
    CONSTRAINT fk_proof_images_proof FOREIGN KEY (resolution_proof_id) REFERENCES resolution_proofs(id) ON DELETE CASCADE
);

-- 6. Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id UUID NOT NULL,
    notification_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    issue_id UUID,
    report_id UUID,
    assignment_id UUID,
    is_read BOOLEAN DEFAULT FALSE NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_notifications_recipient FOREIGN KEY (recipient_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE SET NULL,
    CONSTRAINT fk_notifications_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL,
    CONSTRAINT fk_notifications_assignment FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE SET NULL
);

-- 7. Feedback Table (One feedback per user per issue after resolution)
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    report_id UUID,
    submitted_by_user_id UUID NOT NULL,
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_rating_range CHECK (rating >= 1 AND rating <= 5),
    CONSTRAINT unique_user_issue_feedback UNIQUE (submitted_by_user_id, issue_id),
    CONSTRAINT fk_feedback_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_feedback_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL,
    CONSTRAINT fk_feedback_user FOREIGN KEY (submitted_by_user_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- 8. Audit Logs Table (Append-only)
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(50) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_audit_actor FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE RESTRICT
);
