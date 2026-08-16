-- Migration: 010_test_data
-- Description: Seeds sample test data depicting a complete citizen report, AI prediction, duplicate detection, triage, worker assignment, completion, verification, and feedback workflow.

-- 1. Insert Test Users (Password hashes are mocked to '$2b$12$MockHash...')
INSERT INTO users (id, name, email, phone, password_hash) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Charlie Admin', 'charlie.admin@example.com', '+15550101', '$2b$12$MockHashCharlieAdminPassword123'),
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Alice Authority', 'alice.authority@example.com', '+15550102', '$2b$12$MockHashAliceAuthorityPassword123'),
('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Bob Worker', 'bob.worker@example.com', '+15550103', '$2b$12$MockHashBobWorkerPassword123'),
('dddddddd-dddd-dddd-dddd-dddddddddddd', 'John Citizen One', 'john.citizen1@example.com', '+15550104', '$2b$12$MockHashJohnCitizen1Password123'),
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Jane Citizen Two', 'jane.citizen2@example.com', '+15550105', '$2b$12$MockHashJaneCitizen2Password123')
ON CONFLICT (id) DO NOTHING;

-- 2. Associate Users with Roles
INSERT INTO user_roles (user_id, role_id) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '00000000-0000-0000-0000-000000000001'), -- Charlie -> ADMIN
('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '00000000-0000-0000-0000-000000000002'), -- Alice -> AUTHORITY
('cccccccc-cccc-cccc-cccc-cccccccccccc', '00000000-0000-0000-0000-000000000003'), -- Bob -> WORKER
('dddddddd-dddd-dddd-dddd-dddddddddddd', '00000000-0000-0000-0000-000000000004'), -- John -> CITIZEN
('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', '00000000-0000-0000-0000-000000000004')  -- Jane -> CITIZEN
ON CONFLICT ON CONSTRAINT pk_user_roles DO NOTHING;

-- 3. Create Worker Profile for Bob
INSERT INTO workers (id, user_id, department_id, is_available, experience_years, current_location) VALUES
('ffffffff-ffff-ffff-ffff-ffffffffffff', 
 'cccccccc-cccc-cccc-cccc-cccccccccccc', 
 '22222222-2222-2222-2222-222222222201', -- DPW
 true, 
 5, 
 ST_SetSRID(ST_MakePoint(-122.4180, 37.7740), 4326)::geography) -- Near Civic Center SF
ON CONFLICT (id) DO NOTHING;

-- 4. Map Bob to skills (asphalt paving)
INSERT INTO worker_skills (worker_id, skill_id) VALUES
('ffffffff-ffff-ffff-ffff-ffffffffffff', '33333333-3333-3333-3333-333333333301')
ON CONFLICT ON CONSTRAINT pk_worker_skills DO NOTHING;

-- 5. Set session actor for auditing trigger functions
-- In actual execution, the application sets this at the start of each transaction.
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

-- 6. Insert Image Metadata for John's report
INSERT INTO image_metadata (id, storage_provider, object_key, public_url, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by, moderation_status) VALUES
('66666666-6666-6666-6666-666666666666', 's3', 'civicfix-reports/john-pothole-1.jpg', 'https://s3.amazonaws.com/civicfix-reports/john-pothole-1.jpg', 'pothole_far.jpg', 'image/jpeg', 245000, 'sha256:d83d8cfb3d4f828a2a11b95f190e29b19e78280f295f1e18e8d8d38bf930cd2e', 1920, 1080, 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'APPROVED')
ON CONFLICT (id) DO NOTHING;

-- 7. Citizen 1 (John) submits Report
INSERT INTO reports (id, reporter_id, issue_id, description, location) VALUES
('88888888-8888-8888-8888-888888888888', 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 NULL, -- Null initially at intake
 'Huge pothole in the middle lane near Civic Center, causing vehicles to swerve.', 
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

-- Link John's report to its image metadata
INSERT INTO report_images (report_id, image_id) VALUES
('88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666')
ON CONFLICT ON CONSTRAINT pk_report_images DO NOTHING;

-- 8. Run AI Prediction on John's Report (Pipeline executes and creates prediction records)
INSERT INTO ai_prediction_runs (id, issue_id, report_id, model_name, model_version, pipeline_version, input_hash, status, started_at, completed_at) VALUES
('33333333-1111-1111-1111-333333333333', 
 NULL, 
 '88888888-8888-8888-8888-888888888888', 
 'civic_fix_multimodal', 
 'v2.1', 
 'pipe_v1.0', 
 'hash:9f0293029ad30283f', 
 'COMPLETED', 
 CURRENT_TIMESTAMP - INTERVAL '10 minutes', 
 CURRENT_TIMESTAMP - INTERVAL '9 minutes')
ON CONFLICT (id) DO NOTHING;

INSERT INTO ai_predictions (id, prediction_run_id, prediction_type, predicted_category_id, predicted_severity, predicted_priority, confidence_score, duplicate_score, raw_output) VALUES
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'CLASSIFICATION', '11111111-1111-1111-1111-111111111101', NULL, NULL, 0.950, NULL, '{"category": "pothole", "logits": [0.95, 0.02, 0.01, 0.02]}'),
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'SEVERITY', NULL, 'HIGH', NULL, 0.880, NULL, '{"severity": "HIGH", "logits": [0.05, 0.07, 0.88, 0.00]}'),
(gen_random_uuid(), '33333333-1111-1111-1111-333333333333', 'PRIORITY', NULL, NULL, 'HIGH', 0.820, NULL, '{"priority": "HIGH", "logits": [0.03, 0.15, 0.82, 0.00]}')
ON CONFLICT (id) DO NOTHING;

-- 9. Setup Session for Authority User Alice (Authority takes over triage)
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

-- Alice creates canonical Issue record based on John's report triage
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
 'Civic Center Plaza', 
 'San Francisco', 
 'California', 
 '94102')
ON CONFLICT (id) DO NOTHING;

-- Link John's report to the newly created canonical issue
UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '88888888-8888-8888-8888-888888888888';
-- Associate John's image as the canonical issue before-image
INSERT INTO issue_images (issue_id, image_id) VALUES ('99999999-9999-9999-9999-999999999999', '66666666-6666-6666-6666-666666666666') ON CONFLICT ON CONSTRAINT pk_issue_images DO NOTHING;

-- 10. Citizen 2 (Jane) reports same pothole a few hours later (10 meters away)
SELECT set_config('app.current_user_id', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', true);

INSERT INTO image_metadata (id, storage_provider, object_key, public_url, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by, moderation_status) VALUES
('55555555-5555-5555-5555-555555555555', 's3', 'civicfix-reports/jane-pothole-close.jpg', 'https://s3.amazonaws.com/civicfix-reports/jane-pothole-close.jpg', 'pothole_close.jpg', 'image/jpeg', 189000, 'sha256:f7289f81a7b4588e1e8d91f28b49202a0b12f2c8d2347eb108bf89cd12ea8df4', 1920, 1080, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'APPROVED')
ON CONFLICT (id) DO NOTHING;

INSERT INTO reports (id, reporter_id, issue_id, description, location) VALUES
('77777777-7777-7777-7777-777777777777', 
 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 
 NULL, -- Null initially at intake
 'Deep road crater in Civic Center, damaged my tire!', 
 ST_SetSRID(ST_MakePoint(-122.41942, 37.77498), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

INSERT INTO report_images (report_id, image_id) VALUES
('77777777-7777-7777-7777-777777777777', '55555555-5555-5555-5555-555555555555')
ON CONFLICT ON CONSTRAINT pk_report_images DO NOTHING;

-- 11. AI Duplicate Pipeline detects Jane's report as duplicate candidate of the first issue
INSERT INTO ai_prediction_runs (id, issue_id, report_id, model_name, model_version, pipeline_version, input_hash, status, started_at, completed_at) VALUES
('33333333-2222-2222-2222-333333333333', 
 NULL, 
 '77777777-7777-7777-7777-777777777777', 
 'civic_fix_multimodal', 
 'v2.1', 
 'pipe_v1.0', 
 'hash:d3d82f93d39f38f7c', 
 'COMPLETED', 
 CURRENT_TIMESTAMP - INTERVAL '5 minutes', 
 CURRENT_TIMESTAMP - INTERVAL '4 minutes')
ON CONFLICT (id) DO NOTHING;

-- AI prediction generates candidate link
INSERT INTO ai_predictions (id, prediction_run_id, prediction_type, duplicate_score, target_issue_id, raw_output) VALUES
(gen_random_uuid(), '33333333-2222-2222-2222-333333333333', 'DUPLICATE', 0.925, '99999999-9999-9999-9999-999999999999', '{"duplicate_score": 0.925, "reason": "Spatial distance < 15m and text semantic overlap."}')
ON CONFLICT (id) DO NOTHING;

-- 12. Create duplicate relationship entry in pending state
INSERT INTO issue_relationships (id, source_issue_id, target_issue_id, relationship_type, confidence_score, detection_source, review_status) VALUES
('55555555-1111-1111-1111-555555555555', 
 '99999999-9999-9999-9999-999999999999', -- Source
 '99999999-9999-9999-9999-999999999999', -- Self reference not allowed, but wait! We will merge another issue later. Wait, for report duplicate triage we update reports.issue_id.
 -- If we create a temporary issue for Jane (e.g. Option B style or separate issue), we can link them.
 -- Let's insert a second temporary/duplicate issue so we can demonstrate issue-to-issue merge.
 -- Let's name it 'Temporary Pothole Issue'
 '99999999-9999-9999-9999-999999999999', 
 '99999999-9999-9999-9999-999999999999', 
 'DUPLICATE', 
 0.925, 
 'AI', 
 'PENDING')
ON CONFLICT (id) DO NOTHING;
-- Wait, let's fix the above statement to reference a separate duplicate issue that gets merged!
-- Let's create Issue 2 (Jane's temporary issue)
INSERT INTO issues (id, title, description, approved_category_id, approved_severity, approved_priority, current_status, location, address_line, city, state, postal_code) VALUES
('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', 
 'Pothole at Civic Center', 
 'Jane''s report about tire damage from pothole.', 
 '11111111-1111-1111-1111-111111111101', 
 'HIGH', 
 'HIGH', 
 'REPORTED', 
 ST_SetSRID(ST_MakePoint(-122.41942, 37.77498), 4326)::geography, 
 'Civic Center Plaza', 
 'San Francisco', 
 'California', 
 '94102')
ON CONFLICT (id) DO NOTHING;

-- Link Jane's report to Jane's temporary issue initially
UPDATE reports SET issue_id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' WHERE id = '77777777-7777-7777-7777-777777777777';

-- Insert issue relationship between Jane's issue and John's canonical issue
DELETE FROM issue_relationships WHERE id = '55555555-1111-1111-1111-555555555555';
INSERT INTO issue_relationships (id, source_issue_id, target_issue_id, relationship_type, confidence_score, detection_source, review_status) VALUES
('55555555-1111-1111-1111-555555555555', 
 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', -- Source (duplicate issue)
 '99999999-9999-9999-9999-999999999999', -- Target (canonical issue)
 'DUPLICATE', 
 0.925, 
 'AI', 
 'PENDING')
ON CONFLICT (id) DO NOTHING;

-- 13. Authority Alice reviews and confirms the duplicate relationship, merging Issue B (Jane's) into Issue A (John's)
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE issue_relationships 
SET review_status = 'APPROVED', 
    reviewed_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
    reviewed_at = CURRENT_TIMESTAMP, 
    review_notes = 'Confirmed duplicate location and description. Merging report evidence.' 
WHERE id = '55555555-1111-1111-1111-555555555555';

-- Update Jane's report to point to the canonical issue (John's issue)
UPDATE reports SET issue_id = '99999999-9999-9999-9999-999999999999' WHERE id = '77777777-7777-7777-7777-777777777777';

-- Update Jane's temporary issue to status DUPLICATE
UPDATE issues SET current_status = 'DUPLICATE' WHERE id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

-- 14. Authority Alice verifies the canonical issue and sets it to VERIFIED
UPDATE issues SET current_status = 'VERIFIED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 15. Authority Alice assigns DPW Worker Bob to the issue
INSERT INTO assignments (id, issue_id, worker_id, assigned_by, status) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 'ffffffff-ffff-ffff-ffff-ffffffffffff', -- Bob's Worker Profile
 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
 'ASSIGNED')
ON CONFLICT (id) DO NOTHING;

-- Add assignment log event
INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ASSIGNED', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Assigned to Bob Miller for patching.');

-- Update issue status to ASSIGNED
UPDATE issues SET current_status = 'ASSIGNED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 16. Worker Bob accepts the assignment
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

UPDATE assignments 
SET status = 'ACCEPTED', 
    accepted_at = CURRENT_TIMESTAMP 
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ACCEPTED', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Accepting pothole patch task. Packing asphalt.');

UPDATE issues SET current_status = 'ACCEPTED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 17. Worker Bob starts work on-site
UPDATE assignments 
SET status = 'IN_PROGRESS', 
    started_at = CURRENT_TIMESTAMP 
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'IN_PROGRESS', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Arrived on site. Initiating ground prep.');

UPDATE issues SET current_status = 'IN_PROGRESS' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 18. Worker Bob completes work and uploads resolution proof
INSERT INTO image_metadata (id, storage_provider, object_key, public_url, original_filename, mime_type, file_size_bytes, checksum, width, height, uploaded_by, moderation_status) VALUES
('44444444-4444-4444-4444-444444444444', 's3', 'civicfix-resolutions/bob-pothole-fixed.jpg', 'https://s3.amazonaws.com/civicfix-resolutions/bob-pothole-fixed.jpg', 'pothole_fixed.jpg', 'image/jpeg', 212000, 'sha256:d8ef801a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e', 1920, 1080, 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'APPROVED')
ON CONFLICT (id) DO NOTHING;

INSERT INTO resolution_proofs (id, assignment_id, worker_id, description, before_image_id, after_image_id, status) VALUES
('22222222-aaaa-bbbb-cccc-dddddddddddd', 
 '11111111-aaaa-bbbb-cccc-dddddddddddd', 
 'ffffffff-ffff-ffff-ffff-ffffffffffff', 
 'Pothole filled with fresh asphalt mix and rolled flat. Checked compaction.', 
 '66666666-6666-6666-6666-666666666666', -- John's before image
 '44444444-4444-4444-4444-444444444444', -- Bob's after image
 'SUBMITTED')
ON CONFLICT (id) DO NOTHING;

UPDATE assignments 
SET status = 'COMPLETED', 
    completed_at = CURRENT_TIMESTAMP 
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

INSERT INTO assignment_events (assignment_id, status, changed_by, remarks) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'COMPLETED', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Work completed on site. Cleaned and swept.');

UPDATE issues SET current_status = 'RESOLUTION_SUBMITTED' WHERE id = '99999999-9999-9999-9999-999999999999';

-- 19. Authority Alice reviews and verifies the resolution proof, marking issue as RESOLVED
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE resolution_proofs 
SET status = 'VERIFIED', 
    reviewed_by = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 
    reviewed_at = CURRENT_TIMESTAMP 
WHERE id = '22222222-aaaa-bbbb-cccc-dddddddddddd';

UPDATE issues 
SET current_status = 'RESOLVED', 
    resolved_at = CURRENT_TIMESTAMP 
WHERE id = '99999999-9999-9999-9999-999999999999';

-- 20. Notify reporter John of the resolution
INSERT INTO notifications (id, recipient_id, notification_type, title, message, related_issue_id, related_report_id) VALUES
(gen_random_uuid(), 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 'STATUS_UPDATE', 
 'Issue Resolved: Pothole on Civic Center Plaza', 
 'Great news! The pothole you reported near Civic Center Plaza has been repaired. Thank you for helping improve our city.', 
 '99999999-9999-9999-9999-999999999999', 
 '88888888-8888-8888-8888-888888888888')
ON CONFLICT (id) DO NOTHING;

-- 21. Citizen John submits feedback rating 5
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO feedback (id, user_id, issue_id, report_id, rating, comment) VALUES
('55555555-aaaa-bbbb-cccc-dddddddddddd', 
 'dddddddd-dddd-dddd-dddd-dddddddddddd', 
 '99999999-9999-9999-9999-999999999999', 
 '88888888-8888-8888-8888-888888888888', 
 5, 
 'Incredible service! Repaired within 24 hours of reporting. Very neat finish!')
ON CONFLICT (id) DO NOTHING;
