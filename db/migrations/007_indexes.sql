-- Migration: 007_indexes
-- Description: Creates indexes for rapid querying, including spatial (GiST) indexes and partial/conditional indexes.

-- 1. Spatial Indexes (GiST)
CREATE INDEX IF NOT EXISTS idx_issues_location ON issues USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_reports_location ON reports USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_workers_location ON workers USING GIST (current_location);

-- 2. Identity Indexes
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON user_roles(role_id);
CREATE INDEX IF NOT EXISTS idx_workers_department ON workers(department_id);
CREATE INDEX IF NOT EXISTS idx_workers_availability ON workers(is_available);

-- 3. Issue and Report Workflow Indexes
CREATE INDEX IF NOT EXISTS idx_issues_status ON issues(current_status);
CREATE INDEX IF NOT EXISTS idx_issues_category ON issues(approved_category_id);
CREATE INDEX IF NOT EXISTS idx_issues_priority ON issues(approved_priority);
CREATE INDEX IF NOT EXISTS idx_issues_department ON issues(department_id);
CREATE INDEX IF NOT EXISTS idx_issues_created_at ON issues(created_at);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_issue ON reports(issue_id);

-- 4. Assignment Indexes & Partial Unique Index for Active Assignments
CREATE INDEX IF NOT EXISTS idx_assignments_issue ON assignments(issue_id);
CREATE INDEX IF NOT EXISTS idx_assignments_worker ON assignments(worker_id);
CREATE INDEX IF NOT EXISTS idx_assignments_status ON assignments(status);

-- Ensures that an issue can have at most one active worker assignment concurrently.
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_assignment 
ON assignments(issue_id) 
WHERE status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS');

-- 5. Status History Multi-Column Index (Ordered by creation descent for latest state)
CREATE INDEX IF NOT EXISTS idx_status_history_issue_time ON issue_status_history(issue_id, created_at DESC);

-- 6. Notification Partial Index for Unread Notifications
CREATE INDEX IF NOT EXISTS idx_notifications_recipient_unread ON notifications(recipient_id) WHERE is_read = FALSE;

-- 7. Feedback and Audit Indexes
CREATE INDEX IF NOT EXISTS idx_feedback_issue ON feedback(issue_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- 8. AI Layer Indexes
CREATE INDEX IF NOT EXISTS idx_ai_runs_issue ON ai_prediction_runs(issue_id);
CREATE INDEX IF NOT EXISTS idx_ai_runs_report ON ai_prediction_runs(report_id);
CREATE INDEX IF NOT EXISTS idx_ai_predictions_run ON ai_predictions(prediction_run_id);

-- 9. Relationship Indexes
CREATE INDEX IF NOT EXISTS idx_relationships_source ON issue_relationships(source_issue_id);
CREATE INDEX IF NOT EXISTS idx_relationships_target ON issue_relationships(target_issue_id);
