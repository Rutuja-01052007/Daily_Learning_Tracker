-- Migration: 010_test_data
-- Description: Seeds end-to-end test scenario matching all 15 workflow steps.

-- 1. Insert Test Users
INSERT INTO users (id, full_name, email, phone, password_hash) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Charlie Admin', 'charlie.admin@example.com', '+15550101', '$2b$12$MockHashCharlieAdminPassword123'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Alice Authority', 'alice.authority@example.com', '+15550102', '$2b$12$MockHashAliceAuthorityPassword123'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Bob Worker', 'bob.worker@example.com', '+15550103', '$2b$12$MockHashBobWorkerPassword123'),
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'John Citizen One', 'john.citizen1@example.com', '+15550104', '$2b$12$MockHashJohnCitizen1Password123'),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Jane Citizen Two', 'jane.citizen2@example.com', '+15550105', '$2b$12$MockHashJaneCitizen2Password123')
ON CONFLICT (id) DO NOTHING;

-- 2. Map Users to Roles
INSERT INTO user_roles (user_id, role_id) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-000000000001'), -- Charlie -> ADMIN
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-0000-0000-000000000002'), -- Alice -> AUTHORITY
('cccccccc-cccc-cccc-cccc-cccccccccccc', '00000000-0000-0000-0000-000000000003'), -- Bob -> WORKER
('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-000000000004'), -- John -> CITIZEN
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '00000000-0000-0000-0000-000000000004')  -- Jane -> CITIZEN
ON CONFLICT ON CONSTRAINT pk_user_roles DO NOTHING;

-- 3. Create Worker Profile for Bob
INSERT INTO workers (id, user_id, department_id, worker_status, availability_status, years_experience, current_location) VALUES
('ffffffff-ffff-ffff-ffff-ffffffffffff', 
 'cccccccc-cccc-cccc-cccc-cccccccccccc', 
 '22222222-2222-2222-2222-222222222201', -- Road Maintenance
 'ACTIVE', 
 'AVAILABLE', 
 5, 
 ST_SetSRID(ST_MakePoint(-122.4180, 37.7740), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

-- Map Bob to skills (pothole repair)
INSERT INTO worker_skills (worker_id, skill_id) VALUES
('ffffffff-ffff-ffff-ffff-ffffffffffff', '33333333-3333-3333-3333-333333333301')
ON CONFLICT ON CONSTRAINT pk_worker_skills DO NOTHING;

-- 4. Set Session User for Trigger Auditing
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

-- 5. Citizen 1 (John) Submits Report 1
INSERT INTO reports (id, reporter_id, issue_id, title, description, location) VALUES
('88888888-8888-8888-8888-888888888888', 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 NULL, -- Null during intake
 'Pothole near College Gate', 
 'Large pothole near College Gate causing vehicle swerving.', 
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

-- Report 1 Image Metadata
INSERT INTO report_images (id, report_id, storage_provider, object_key, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by_user_id) VALUES
('66666666-6666-6666-6666-666666666666', 
 '88888888-8888-8888-8888-888888888888', 
 's3', 
 'civicfix-reports/john-pothole-1.jpg', 
 'pothole_far.jpg', 
 'image/jpeg', 
 245000, 
 'sha256:d83d8cfb3d4f828a2a11b95f190e29b19e78280f295f1e18e8d8d38bf930cd2e', 
 1920, 
 1080, 
 'dddddddd-dddd-dddd-dddd-dddddddddddd')
ON CONFLICT (id) DO NOTHING;

-- 6. Authority Creates Canonical Issue & Links Report 1
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

INSERT INTO issues (id, title, canonical_description, category_id, severity, priority, current_status, department_id, location, address_line, city, postal_code) VALUES
('99999999-9999-9999-9999-999999999999', 
 'Pothole near College Gate', 
 'Canonical issue representing deep pothole outside College Gate.', 
 '11111111-1111-1111-1111-111111111101', -- Pothole
 'HIGH', 
 'HIGH', 
 'REPORTED', 
 '22222222-2222-2222-2222-222222222201', -- Road Maintenance
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography, 
 '100 College Road', 
 'San Francisco', 
 '94102')
ON CONFLICT (id) DO NOTHING;

UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '88888888-8888-8888-8888-888888888888';

-- 7. Register AI Model & Record Prediction Run
-- Note: is_active=TRUE requires metrics + artifact_object_key per the schema constraint.
-- The test model uses a placeholder artifact key so the constraint is satisfied.
INSERT INTO ai_models (
    id, model_name, model_version, model_type, task_type, framework,
    class_mapping, artifact_storage_provider, artifact_object_key,
    training_dataset_name, training_dataset_url, training_dataset_license,
    metrics, is_active
) VALUES (
    '77777777-1111-1111-1111-777777777777',
    'civicfix_road_damage_segmentation',
    'v1',
    'SEGMENTATION',
    'image_segmentation',
    'Ultralytics YOLOv8n-seg',
    '{"0": "pothole", "1": "road_crack", "2": "manhole"}',
    's3',
    'civicfix-models/civicfix_road_damage_seg_v1/best.pt',
    'Road Damage Dataset: Potholes, Cracks and Manholes',
    'https://www.kaggle.com/datasets/lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes',
    'EDUCATIONAL_ONLY',
    '{"precision": 0.0, "recall": 0.0, "mAP50": 0.0, "mAP50_95": 0.0, "note": "placeholder - replace with actual trained model metrics"}',
    TRUE
) ON CONFLICT (id) DO NOTHING;

INSERT INTO ai_prediction_runs (id, issue_id, report_id, source_image_id, model_id, run_status) VALUES
('33333333-1111-1111-1111-333333333333',
 '99999999-9999-9999-9999-999999999999',
 '88888888-8888-8888-8888-888888888888',
 '66666666-6666-6666-6666-666666666666',  -- John's uploaded image
 '77777777-1111-1111-1111-777777777777',
 'COMPLETED')
ON CONFLICT (id) DO NOTHING;

-- IMAGE_SEGMENTATION row: the raw polygon detection result
INSERT INTO ai_predictions (
    id, prediction_run_id, prediction_type,
    class_id, class_name, confidence_score,
    bounding_box, segmentation_polygon, raw_output
) VALUES (
    gen_random_uuid(),
    '33333333-1111-1111-1111-333333333333',
    'IMAGE_SEGMENTATION',
    0, 'pothole', 0.9400,
    '{"x1": 120.0, "y1": 210.0, "x2": 310.0, "y2": 420.0}',
    '[[120.0,210.0],[310.0,210.0],[310.0,420.0],[120.0,420.0]]',
    '{"model": "civicfix_road_damage_segmentation", "version": "v1"}'
) ON CONFLICT (id) DO NOTHING;

-- CLASSIFICATION row: combined category + severity + priority recommendation
INSERT INTO ai_predictions (
    id, prediction_run_id, prediction_type,
    predicted_category_id, predicted_severity, predicted_priority,
    confidence_score, raw_output
) VALUES (
    gen_random_uuid(),
    '33333333-1111-1111-1111-333333333333',
    'CLASSIFICATION',
    '11111111-1111-1111-1111-111111111101',  -- pothole category
    'HIGH',
    'HIGH',
    0.9400,
    '{"category": "pothole", "confidence": 0.94, "rule": "highest_confidence_detection"}'
) ON CONFLICT (id) DO NOTHING;

-- 8. Citizen 2 (Jane) Submits Report 2 for the SAME Pothole (Duplicate submission)
SELECT set_config('app.current_user_id', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

INSERT INTO reports (id, reporter_id, issue_id, title, description, location) VALUES
('77777777-7777-7777-7777-777777777777', 
 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 
 NULL, 
 'Deep pothole outside College Gate', 
 'Deep pothole outside the same College Gate. Damaged my tire!', 
 ST_SetSRID(ST_MakePoint(-122.41942, 37.77498), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

INSERT INTO report_images (id, report_id, storage_provider, object_key, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by_user_id) VALUES
('55555555-5555-5555-5555-555555555555', 
 '77777777-7777-7777-7777-777777777777', 
 's3', 
 'civicfix-reports/jane-pothole-2.jpg', 
 'pothole_close.jpg', 
 'image/jpeg', 
 189000, 
 'sha256:f7289f81a7b4588e1e8d91f28b49202a0b12f2c8d2347eb108bf89cd12ea8df4', 
 1920, 
 1080, 
 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')
ON CONFLICT (id) DO NOTHING;

-- 9. Authority Confirms Link of Jane's Report to Canonical Issue
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '77777777-7777-7777-7777-777777777777';

-- 10. Authority Verifies Issue and Assigns Worker Bob
UPDATE issues 
SET current_status = 'VERIFIED', 
    verified_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
    verified_at = CURRENT_TIMESTAMP 
WHERE id = '99999999-9999-9999-9999-999999999999';

INSERT INTO assignments (id, issue_id, worker_id, department_id, assigned_by, assignment_status) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 'ffffffff-ffff-ffff-ffff-ffffffffffff', 
 '22222222-2222-2222-2222-222222222201', 
 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
 'ASSIGNED')
ON CONFLICT (id) DO NOTHING;

INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ASSIGNED', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Assigned to Bob Miller');

UPDATE issues SET current_status = 'ASSIGNED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 11. Worker Bob Accepts & Starts Work
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

UPDATE assignments SET assignment_status = 'ACCEPTED', accepted_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ACCEPTED', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Worker accepted task.');

UPDATE assignments SET assignment_status = 'IN_PROGRESS', started_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'IN_PROGRESS', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Worker started work on site.');

UPDATE issues SET current_status = 'IN_PROGRESS' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 12. Worker Submits Resolution Proof with Resolution Proof Images
INSERT INTO resolution_proofs (id, issue_id, assignment_id, submitted_by_worker_id, status, description) VALUES
('22222222-aaaa-bbbb-cccc-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 '11111111-aaaa-bbbb-cccc-dddddddddddd', 
 'ffffffff-ffff-ffff-ffff-ffffffffffff', 
 'SUBMITTED', 
 'Pothole filled with fresh asphalt mix and rolled flat.')
ON CONFLICT (id) DO NOTHING;

INSERT INTO resolution_proof_images (id, resolution_proof_id, storage_provider, object_key, original_filename, mime_type, file_size_bytes, checksum, image_type) VALUES
('44444444-4444-4444-4444-444444444444', 
 '22222222-aaaa-bbbb-cccc-dddddddddddd', 
 's3', 
 'civicfix-resolutions/bob-pothole-after.jpg', 
 'pothole_after.jpg', 
 'image/jpeg', 
 212000, 
 'sha256:d8ef801a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e', 
 'AFTER')
ON CONFLICT (id) DO NOTHING;

UPDATE assignments SET assignment_status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';
UPDATE issues SET current_status = 'RESOLUTION_SUBMITTED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 13. Authority Verifies Proof & Issue Becomes RESOLVED
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE resolution_proofs 
SET status = 'VERIFIED', 
    reviewed_by_user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
    reviewed_at = CURRENT_TIMESTAMP 
WHERE id = '22222222-aaaa-bbbb-cccc-dddddddddddd';

UPDATE issues 
SET current_status = 'RESOLVED', 
    resolved_at = CURRENT_TIMESTAMP 
WHERE id = '99999999-9999-9999-9999-999999999999';

-- 14. Send Notifications to Citizens John & Jane
INSERT INTO notifications (id, recipient_user_id, notification_type, title, message, issue_id, report_id) VALUES
(gen_random_uuid(), 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'STATUS_UPDATE', 'Issue Resolved', 'Your reported pothole near College Gate has been resolved.', '99999999-9999-9999-9999-999999999999', '88888888-8888-8888-8888-888888888888'),
(gen_random_uuid(), 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'STATUS_UPDATE', 'Issue Resolved', 'Your reported pothole near College Gate has been resolved.', '99999999-9999-9999-9999-999999999999', '77777777-7777-7777-7777-777777777777')
ON CONFLICT (id) DO NOTHING;

-- 15. Citizen John Submits Feedback
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO feedback (id, issue_id, report_id, submitted_by_user_id, rating, comment) VALUES
('55555555-aaaa-bbbb-cccc-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 '88888888-8888-8888-8888-888888888888', 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 5, 
 'Excellent job! Repaired within 24 hours of reporting.')
ON CONFLICT (id) DO NOTHING;
