-- Migration: 008_constraints_and_triggers
-- Description: Creates trigger functions for timestamps, status logging, audit mutation logging, and append-only enforcement.

-- 1. Function and Triggers for automatically updating `updated_at` timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_issue_categories_updated_at BEFORE UPDATE ON issue_categories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON departments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_workers_updated_at BEFORE UPDATE ON workers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_issues_updated_at BEFORE UPDATE ON issues FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_reports_updated_at BEFORE UPDATE ON reports FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_assignments_updated_at BEFORE UPDATE ON assignments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_resolution_proofs_updated_at BEFORE UPDATE ON resolution_proofs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_feedback_updated_at BEFORE UPDATE ON feedback FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 2. Status History Auto-logger trigger
CREATE OR REPLACE FUNCTION log_issue_status_history()
RETURNS TRIGGER AS $$
DECLARE
    v_changed_by UUID;
    v_remarks TEXT;
BEGIN
    BEGIN
        v_changed_by := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_changed_by := NULL;
    END;

    IF (TG_OP = 'INSERT') THEN
        v_remarks := 'Issue reported and recorded in database.';
        INSERT INTO issue_status_history (
            issue_id,
            previous_status,
            new_status,
            changed_by_user_id,
            remarks
        ) VALUES (
            NEW.id,
            NULL,
            NEW.current_status,
            v_changed_by,
            v_remarks
        );
    ELSIF (TG_OP = 'UPDATE' AND OLD.current_status IS DISTINCT FROM NEW.current_status) THEN
        v_remarks := 'Status changed from ' || OLD.current_status || ' to ' || NEW.current_status || '.';
        INSERT INTO issue_status_history (
            issue_id,
            previous_status,
            new_status,
            changed_by_user_id,
            remarks
        ) VALUES (
            NEW.id,
            OLD.current_status,
            NEW.current_status,
            v_changed_by,
            v_remarks
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_issues_status_history
AFTER INSERT OR UPDATE OF current_status ON issues
FOR EACH ROW EXECUTE FUNCTION log_issue_status_history();

-- 3. Trigger to prevent updates or deletes on audit logs (Append-only)
CREATE OR REPLACE FUNCTION prevent_audit_log_mutation()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit logs are append-only. Mutations are prohibited.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_audit_log_mutation
BEFORE UPDATE OR DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_audit_log_mutation();

-- 4. Automatic Issue Audit Logger trigger
CREATE OR REPLACE FUNCTION audit_issues_mutation()
RETURNS TRIGGER AS $$
DECLARE
    v_actor_id UUID;
    v_old_json JSONB := NULL;
    v_new_json JSONB := NULL;
    v_action VARCHAR(50);
BEGIN
    BEGIN
        v_actor_id := NULLIF(current_setting('app.current_user_id', true), '')::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_actor_id := NULL;
    END;

    IF (TG_OP = 'INSERT') THEN
        v_action := 'INSERT';
        v_new_json := to_jsonb(NEW);
    ELSIF (TG_OP = 'UPDATE') THEN
        v_action := 'UPDATE';
        v_old_json := to_jsonb(OLD);
        v_new_json := to_jsonb(NEW);
    ELSIF (TG_OP = 'DELETE') THEN
        v_action := 'DELETE';
        v_old_json := to_jsonb(OLD);
    END IF;

    INSERT INTO audit_logs (
        actor_user_id,
        entity_type,
        entity_id,
        action,
        old_values,
        new_values
    ) VALUES (
        v_actor_id,
        'issues',
        COALESCE(NEW.id, OLD.id),
        v_action,
        v_old_json,
        v_new_json
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_issues_mutation
AFTER INSERT OR UPDATE OR DELETE ON issues
FOR EACH ROW EXECUTE FUNCTION audit_issues_mutation();
