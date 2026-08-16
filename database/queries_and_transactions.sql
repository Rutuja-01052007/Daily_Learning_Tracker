-- SQL Script: Queries and Transactions
-- Description: Contains the 22 required operational SQL queries and the step-by-step transaction lifecycle workflow.

-- ============================================================================
-- 1. LIFE CYCLE TRANSACTION FLOW
-- ============================================================================

-- STEP 1: Citizen John Doe creates a Report.
-- Transaction boundary starts.
BEGIN;
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO reports (id, reporter_id, issue_id, description, location) VALUES
('88888888-8888-8888-8888-888888888888', 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 NULL, 
 'Pothole causing issues near Civic Center Plaza.', 
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography);
COMMIT;

-- STEP 2: Report images are stored as metadata.
BEGIN;
INSERT INTO image_metadata (id, storage_provider, object_key, public_url, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by, moderation_status) VALUES
('66666666-6666-6666-6666-666666666666', 's3', 'civicfix-reports/john-pothole-1.jpg', 'https://s3.amazonaws.com/civicfix-reports/john-pothole-1.jpg', 'pothole_far.jpg', 'image/jpeg', 245000, 'sha256:d83d8cfb3d4f828a2a11b95f190e29b19e78280f295f1e18e8d8d38bf930cd2e', 1920, 1080, 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'APPROVED');

INSERT INTO report_images (report_id, image_id) VALUES
('88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666');
COMMIT;

-- STEP 3: A new issue is created or the report is linked to an existing issue (creating the canonical issue).
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

INSERT INTO issues (id, title, description, approved_category_id, approved_severity, approved_priority, current_status, department_id, location, address_line, city, state, postal_code) VALUES
('99999999-9999-9999-9999-999999999999', 
 'Pothole on Civic Center Plaza', 
 'Canonical issue representing the deep pothole near Civic Center Plaza.', 
 '11111111-1111-1111-1111-111111111101', -- Pothole
 'HIGH', 
 'HIGH', 
 'UNDER_REVIEW', 
 '22222222-2222-2222-2222-222222222201', -- DPW
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography, 
 'Civic Center Plaza', 'San Francisco', 'California', '94102');

UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '88888888-8888-8888-8888-888888888888';
INSERT INTO issue_images (issue_id, image_id) VALUES ('99999999-9999-9999-9999-999999999999', '66666666-6666-6666-6666-666666666666');
COMMIT;

-- STEP 4: AI prediction run is recorded.
BEGIN;
INSERT INTO ai_prediction_runs (id, issue_id, report_id, model_name, model_version, pipeline_version, input_hash, status) VALUES
('33333333-1111-1111-1111-333333333333', '99999999-9999-9999-9999-999999999999', '88888888-8888-8888-8888-888888888888', 'civic_fix_multimodal', 'v2.1', 'pipe_v1.0', 'hash:9f0293029ad30283f', 'COMPLETED');
COMMIT;

-- STEP 5-8: AI predicts category, severity, priority, and duplicate score.
BEGIN;
INSERT INTO ai_predictions (id, prediction_run_id, prediction_type, predicted_category_id, predicted_severity, predicted_priority, confidence_score, duplicate_score, target_issue_id, raw_output) VALUES
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'CLASSIFICATION', '11111111-1111-1111-1111-111111111101', NULL, NULL, 0.950, NULL, NULL, '{"category": "pothole"}'),
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'SEVERITY', NULL, 'HIGH', NULL, 0.880, NULL, NULL, '{"severity": "HIGH"}'),
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'PRIORITY', NULL, NULL, 'HIGH', 0.820, NULL, NULL, '{"priority": "HIGH"}'),
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'DUPLICATE', NULL, NULL, NULL, NULL, 0.000, NULL, '{"duplicate_score": 0.0}');
COMMIT;

-- STEP 9: Another citizen Jane Smith creates a report near the same location.
BEGIN;
SELECT set_config('app.current_user_id', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

INSERT INTO reports (id, reporter_id, issue_id, description, location) VALUES
('77777777-7777-7777-7777-777777777777', 
 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 
 NULL, 
 'Crater in road, damaged my wheel!', 
 ST_SetSRID(ST_MakePoint(-122.41942, 37.77498), 4326)::geography);
COMMIT;

-- STEP 10: AI flags second report as a duplicate candidate.
BEGIN;
-- AI Prediction Run for report 2
INSERT INTO ai_prediction_runs (id, issue_id, report_id, model_name, model_version, pipeline_version, input_hash, status) VALUES
('33333333-2222-2222-2222-333333333333', NULL, '77777777-7777-7777-7777-777777777777', 'civic_fix_multimodal', 'v2.1', 'pipe_v1.0', 'hash:d3d82f93d39f38f7c', 'COMPLETED');

-- AI records prediction
INSERT INTO ai_predictions (id, prediction_run_id, prediction_type, duplicate_score, target_issue_id, raw_output) VALUES
(gen_random_uuid(), '33333333-2222-2222-2222-333333333333', 'DUPLICATE', 0.925, '99999999-9999-9999-9999-999999999999', '{"duplicate_score": 0.925}');

-- Insert relationship candidate
INSERT INTO issue_relationships (id, source_issue_id, target_issue_id, relationship_type, confidence_score, detection_source, review_status) VALUES
('55555555-1111-1111-1111-555555555555', 
 '99999999-9999-9999-9999-999999999999', -- Temp or self-issue target. Let's make it a candidate link.
 '99999999-9999-9999-9999-999999999999', -- For simplicity, we directly relate report 2 to issue 1 via Authority.
 'DUPLICATE', 
 0.925, 
 'AI', 
 'PENDING');
COMMIT;

-- STEP 11-12: Authority Alice confirms the duplicate relationship and links it.
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE issue_relationships 
SET review_status = 'APPROVED', 
    reviewed_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
    reviewed_at = CURRENT_TIMESTAMP, 
    review_notes = 'Confirmed duplicate location.' 
WHERE id = '55555555-1111-1111-1111-555555555555';

UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '77777777-7777-7777-7777-777777777777';
COMMIT;

-- STEP 13: Authority Alice verifies the issue.
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);
UPDATE issues SET current_status = 'VERIFIED' WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 14: Authority Alice assigns department and worker Bob.
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

INSERT INTO assignments (id, issue_id, worker_id, assigned_by, status) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 'ffffffff-ffff-ffff-ffff-ffffffffffff', -- Bob's Worker Profile
 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
 'ASSIGNED');

INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ASSIGNED', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Assigned to Bob.');

UPDATE issues SET current_status = 'ASSIGNED' WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 15: Worker Bob accepts the assignment.
BEGIN;
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

UPDATE assignments SET status = 'ACCEPTED', accepted_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ACCEPTED', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Accepting pothole patch task.');
UPDATE issues SET current_status = 'ACCEPTED' WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 16: Worker Bob starts work on site.
BEGIN;
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

UPDATE assignments SET status = 'IN_PROGRESS', started_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'IN_PROGRESS', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Arrived on site.');
UPDATE issues SET current_status = 'IN_PROGRESS' WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 17: Worker Bob completes work and uploads resolution proof metadata.
BEGIN;
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

INSERT INTO image_metadata (id, storage_provider, object_key, public_url, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by, moderation_status) VALUES
('44444444-4444-4444-4444-444444444444', 's3', 'civicfix-resolutions/bob-pothole-fixed.jpg', 'https://s3.amazonaws.com/civicfix-resolutions/bob-pothole-fixed.jpg', 'pothole_fixed.jpg', 'image/jpeg', 212000, 'sha256:d8ef801a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e', 1920, 1080, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'APPROVED');

INSERT INTO resolution_proofs (id, assignment_id, worker_id, description, before_image_id, after_image_id, status) VALUES
('22222222-aaaa-bbbb-cccc-dddddddddddd', '11111111-aaaa-bbbb-cccc-dddddddddddd', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 'Pothole filled and compacted.', '66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', 'SUBMITTED');

UPDATE assignments SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'COMPLETED', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Work completed.');
UPDATE issues SET current_status = 'RESOLUTION_SUBMITTED' WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 18-19: Authority Alice verifies the proof and marks issue as resolved.
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE resolution_proofs SET status = 'VERIFIED', reviewed_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', reviewed_at = CURRENT_TIMESTAMP WHERE id = '22222222-aaaa-bbbb-cccc-dddddddddddd';
UPDATE issues SET current_status = 'RESOLVED', resolved_at = CURRENT_TIMESTAMP WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- STEP 20: Citizen John submits feedback.
BEGIN;
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO feedback (id, user_id, issue_id, report_id, rating, comment) VALUES
('55555555-aaaa-bbbb-cccc-dddddddddddd', 'dddddddd-dddd-dddd-dddd-dddddddddddd', '99999999-9999-9999-9999-999999999999', '88888888-8888-8888-8888-888888888888', 5, 'Quick resolution, thank you!');
COMMIT;


-- ============================================================================
-- 2. OPERATIONAL SQL QUERIES (22 SCENARIOS)
-- ============================================================================

-- Query 1: Pending issues (reported or under review)
SELECT * 
FROM issues 
WHERE current_status IN ('REPORTED', 'UNDER_REVIEW') 
ORDER BY created_at ASC;

-- Query 2: Critical issues (severity or priority marked as CRITICAL)
SELECT * 
FROM issues 
WHERE approved_severity = 'CRITICAL' OR approved_priority = 'CRITICAL' 
ORDER BY created_at DESC;

-- Query 3: Issues by department (using code parameter e.g., 'DPW')
SELECT i.* 
FROM issues i 
JOIN departments d ON i.department_id = d.id 
WHERE d.code = 'DPW'
ORDER BY i.created_at DESC;

-- Query 4: Reports belonging to a specific issue ID
SELECT * 
FROM reports 
WHERE issue_id = '99999999-9999-9999-9999-999999999999'
ORDER BY created_at DESC;

-- Query 5: Complete status history for a specific issue ID
SELECT * 
FROM issue_status_history 
WHERE issue_id = '99999999-9999-9999-9999-999999999999' 
ORDER BY created_at ASC;

-- Query 6: Available workers sorted by experience
SELECT w.*, u.name, u.email 
FROM workers w 
JOIN users u ON w.user_id = u.id 
WHERE w.is_available = TRUE 
ORDER BY w.experience_years DESC;

-- Query 7: Available workers near a specific issue ID within radius (e.g. 5000 meters)
SELECT w.*, u.name, ST_Distance(w.current_location, i.location) AS distance_meters
FROM workers w 
JOIN users u ON w.user_id = u.id 
JOIN issues i ON i.id = '99999999-9999-9999-9999-999999999999' 
WHERE w.is_available = TRUE 
  AND ST_DWithin(w.current_location, i.location, 5000.0) 
ORDER BY distance_meters ASC;

-- Query 8: Nearby unresolved issues within radius (e.g., 2000m of a given point)
SELECT i.*, ST_Distance(i.location, ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography) AS distance_meters
FROM issues i 
WHERE i.current_status != 'RESOLVED' 
  AND ST_DWithin(i.location, ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography, 2000.0) 
ORDER BY distance_meters ASC;

-- Query 9: Pending duplicate candidates (waiting for authority review)
SELECT ir.*, src.title AS duplicate_issue_title, tgt.title AS canonical_issue_title 
FROM issue_relationships ir 
JOIN issues src ON ir.source_issue_id = src.id 
JOIN issues tgt ON ir.target_issue_id = tgt.id 
WHERE ir.relationship_type = 'DUPLICATE' 
  AND ir.review_status = 'PENDING';

-- Query 10: Worker assignments history and status for a specific user email
SELECT a.*, i.title AS issue_title, i.current_status AS issue_status 
FROM assignments a 
JOIN workers w ON a.worker_id = w.id 
JOIN users u ON w.user_id = u.id 
JOIN issues i ON a.issue_id = i.id 
WHERE u.email = 'bob.worker@example.com'
ORDER BY a.assigned_at DESC;

-- Query 11: Overdue unresolved issues exceeding days limit (e.g. 7 days)
SELECT * 
FROM issues 
WHERE current_status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED') 
  AND created_at < NOW() - CAST(7 || ' days' AS INTERVAL)
ORDER BY created_at ASC;

-- Query 12: Average resolution time (hours) by category
SELECT c.name AS category_name, 
       AVG(EXTRACT(EPOCH FROM (i.resolved_at - i.created_at)) / 3600.0) AS avg_resolution_hours
FROM issues i 
JOIN issue_categories c ON i.approved_category_id = c.id 
WHERE i.resolved_at IS NOT NULL 
GROUP BY c.name
ORDER BY avg_resolution_hours DESC;

-- Query 13: Grouped counts of issues by category
SELECT c.name AS category_name, COUNT(i.id) AS issue_count 
FROM issues i 
JOIN issue_categories c ON i.approved_category_id = c.id 
GROUP BY c.name
ORDER BY issue_count DESC;

-- Query 14: Grouped counts of issues by department
SELECT d.name AS department_name, COUNT(i.id) AS issue_count 
FROM issues i 
JOIN departments d ON i.department_id = d.id 
GROUP BY d.name
ORDER BY issue_count DESC;

-- Query 15: Grouped counts of issues by approved priority
SELECT approved_priority, COUNT(id) AS issue_count 
FROM issues 
WHERE approved_priority IS NOT NULL 
GROUP BY approved_priority
ORDER BY issue_count DESC;

-- Query 16: Hotspots clustered by a 0.001 degree spatial grid (approx 100m)
SELECT ST_AsText(ST_SnapToGrid(location::geometry, 0.001)) AS grid_center, 
       COUNT(*) AS issue_count 
FROM issues 
GROUP BY grid_center 
ORDER BY issue_count DESC 
LIMIT 10;

-- Query 17: Unresolved issues in an area boundary box (polygon envelope)
SELECT * 
FROM issues 
WHERE current_status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED') 
  AND ST_Contains(
      ST_MakeEnvelope(-122.4220, 37.7730, -122.4150, 37.7770, 4326)::geography::geometry, 
      location::geometry
  )
ORDER BY created_at DESC;

-- Query 18: A citizen's reports and their canonical issues (by reporter email)
SELECT r.id AS report_id, r.description AS report_description, r.created_at AS reported_at,
       i.id AS canonical_issue_id, i.title AS canonical_issue_title, i.current_status AS issue_status
FROM reports r 
JOIN users u ON r.reporter_id = u.id 
LEFT JOIN issues i ON r.issue_id = i.id 
WHERE u.email = 'john.citizen1@example.com'
ORDER BY r.created_at DESC;

-- Query 19: Current active assignments in the system
SELECT a.id AS assignment_id, i.id AS issue_id, i.title AS issue_title, 
       u.name AS worker_name, d.code AS department_code, a.status AS assignment_status
FROM assignments a 
JOIN workers w ON a.worker_id = w.id 
JOIN users u ON w.user_id = u.id 
JOIN departments d ON w.department_id = d.id 
JOIN issues i ON a.issue_id = i.id 
WHERE a.status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')
ORDER BY a.assigned_at ASC;

-- Query 20: Issues verified/reported without a department assignment
SELECT * 
FROM issues 
WHERE department_id IS NULL 
  AND current_status IN ('REPORTED', 'VERIFIED')
ORDER BY created_at ASC;

-- Query 21: Issues awaiting authority verification (new reports or worker resolved)
SELECT * 
FROM issues 
WHERE current_status IN ('REPORTED', 'RESOLUTION_SUBMITTED')
ORDER BY created_at ASC;

-- Query 22: AI Predictions that were overridden by human authorities
SELECT i.id AS issue_id, 
       i.title AS issue_title, 
       c.name AS approved_category, 
       p_cat.name AS predicted_category, 
       i.approved_severity AS approved_severity, 
       ap.predicted_severity AS predicted_severity, 
       i.approved_priority AS approved_priority, 
       ap.predicted_priority AS predicted_priority
FROM issues i 
JOIN issue_categories c ON i.approved_category_id = c.id 
JOIN ai_prediction_runs apr ON apr.issue_id = i.id 
JOIN ai_predictions ap ON ap.prediction_run_id = apr.id 
LEFT JOIN issue_categories p_cat ON ap.predicted_category_id = p_cat.id 
WHERE (i.approved_category_id IS DISTINCT FROM ap.predicted_category_id AND ap.predicted_category_id IS NOT NULL) 
   OR (i.approved_severity IS DISTINCT FROM ap.predicted_severity AND ap.predicted_severity IS NOT NULL) 
   OR (i.approved_priority IS DISTINCT FROM ap.predicted_priority AND ap.predicted_priority IS NOT NULL)
ORDER BY i.updated_at DESC;
