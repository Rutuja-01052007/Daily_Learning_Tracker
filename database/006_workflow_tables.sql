-- Migration: 006_workflow_tables
-- Description: Creates schemas for assignments, assignment events, status history, resolution proofs, notifications, citizen feedback, and audit logs.

-- 1. Assignments Table
CREATE TABLE IF NOT EXISTS assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    worker_id UUID NOT NULL,
    assigned_by UUID NOT NULL,
    status VARCHAR(50) DEFAULT 'ASSIGNED' NOT NULL,
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
    CONSTRAINT fk_assignments_by FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assignments_status FOREIGN KEY (status) REFERENCES assignment_statuses(id) ON DELETE RESTRICT
);

-- 2. Assignment Events Table (History log of assignment events)
CREATE TABLE IF NOT EXISTS assignment_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,
    changed_by UUID NOT NULL,
    reason TEXT,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_assign_events_id FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE CASCADE,
    CONSTRAINT fk_assign_events_status FOREIGN KEY (status) REFERENCES assignment_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_assign_events_by FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE RESTRICT
);

-- 3. Issue Status History Table
CREATE TABLE IF NOT EXISTS issue_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue_id UUID NOT NULL,
    previous_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    changed_by UUID,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_status_history_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE CASCADE,
    CONSTRAINT fk_status_history_prev FOREIGN KEY (previous_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_status_history_new FOREIGN KEY (new_status) REFERENCES issue_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_status_history_by FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL
);

-- 4. Resolution Proofs Table
CREATE TABLE IF NOT EXISTS resolution_proofs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL,
    worker_id UUID NOT NULL,
    description TEXT NOT NULL,
    before_image_id UUID,
    after_image_id UUID NOT NULL,
    status VARCHAR(50) DEFAULT 'SUBMITTED' NOT NULL,
    submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reviewed_by UUID,
    rejection_reason TEXT,
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_proofs_assignment FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_worker FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_before FOREIGN KEY (before_image_id) REFERENCES image_metadata(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_after FOREIGN KEY (after_image_id) REFERENCES image_metadata(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_status FOREIGN KEY (status) REFERENCES resolution_proof_statuses(id) ON DELETE RESTRICT,
    CONSTRAINT fk_proofs_reviewer FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE RESTRICT
);

-- 5. Notifications Table
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_id UUID NOT NULL,
    notification_type VARCHAR(100) NOT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    related_issue_id UUID,
    related_report_id UUID,
    is_read BOOLEAN DEFAULT FALSE NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT fk_notifications_recipient FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_notifications_issue FOREIGN KEY (related_issue_id) REFERENCES issues(id) ON DELETE SET NULL,
    CONSTRAINT fk_notifications_report FOREIGN KEY (related_report_id) REFERENCES reports(id) ON DELETE SET NULL
);

-- 6. Feedback Table (Submit feedback for an issue only after resolution)
CREATE TABLE IF NOT EXISTS feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    issue_id UUID NOT NULL,
    report_id UUID,
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT check_rating_range CHECK (rating >= 1 AND rating <= 5),
    CONSTRAINT unique_user_issue_feedback UNIQUE (user_id, issue_id),
    CONSTRAINT fk_feedback_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT fk_feedback_issue FOREIGN KEY (issue_id) REFERENCES issues(id) ON DELETE RESTRICT,
    CONSTRAINT fk_feedback_report FOREIGN KEY (report_id) REFERENCES reports(id) ON DELETE SET NULL
);

-- 7. Audit Logs Table (Append-only)
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
