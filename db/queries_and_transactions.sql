-- SQL Script: CivicFix Queries and Transactions
-- Description: Complete 15-step lifecycle transaction and operational queries for
--              Dashboards, Maps, AI Pipeline, Duplicate Detection, and Analytics.

-- ============================================================================
-- 1. END-TO-END WORKFLOW TRANSACTIONS (15 STEPS)
-- ============================================================================

-- STEP 1 & 2: Citizen John Doe submits Report 1 and metadata is saved
BEGIN;
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO reports (id, reporter_id, issue_id, title, description, location) VALUES
('88888888-8888-8888-8888-888888888888', 'dddddddd-dddd-dddd-dddd-dddddddddddd', NULL,
 'Pothole near College Gate',
 'Large pothole near College Gate causing vehicle swerving.',
 ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography);

INSERT INTO report_images (
    id, report_id, storage_provider, object_key, original_filename,
    mime_type, file_size_bytes, checksum, width, height, uploaded_by_user_id
) VALUES (
    '66666666-6666-6666-6666-666666666666',
    '88888888-8888-8888-8888-888888888888',
    's3',
    'civicfix-reports/john-pothole-1.jpg',
    'pothole_far.jpg',
    'image/jpeg', 245000,
    'sha256:d83d8cfb3d4f828a2a11b95f190e29b19e78280f295f1e18e8d8d38bf930cd2e',
    1920, 1080,
    'dddddddd-dddd-dddd-dddd-dddddddddddd'
);

-- First report creates the canonical issue
INSERT INTO issues (
    id, title, canonical_description, category_id, severity, priority,
    current_status, department_id, location, address_line, city, postal_code
) VALUES (
    '99999999-9999-9999-9999-999999999999',
    'Pothole near College Gate',
    'Canonical issue representing deep pothole outside College Gate.',
    '11111111-1111-1111-1111-111111111101',
    'HIGH', 'HIGH', 'REPORTED',
    '22222222-2222-2222-2222-222222222201',
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography,
    '100 College Road', 'San Francisco', '94102'
);

UPDATE reports
SET issue_id = '99999999-9999-9999-9999-999999999999'
WHERE id = '88888888-8888-8888-8888-888888888888';
COMMIT;


-- STEP 3: AI Segmentation & Classification Predictions stored
-- NOTE: Column names match 005_ai_tables.sql (corrected schema).
--       IMAGE_SEGMENTATION row stores raw bbox + polygon per detection.
--       CLASSIFICATION row stores category + severity + priority recommendation.
BEGIN;

INSERT INTO ai_prediction_runs (
    id, issue_id, report_id, source_image_id, model_id, run_status
) VALUES (
    '33333333-1111-1111-1111-333333333333',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888',
    '66666666-6666-6666-6666-666666666666',
    '77777777-1111-1111-1111-777777777777',
    'COMPLETED'
);

-- Raw polygon detection output
INSERT INTO ai_predictions (
    prediction_run_id, prediction_type,
    class_id, class_name, confidence_score,
    bounding_box, segmentation_polygon, raw_output
) VALUES (
    '33333333-1111-1111-1111-333333333333',
    'IMAGE_SEGMENTATION',
    0, 'pothole', 0.9400,
    '{"x1": 120.0, "y1": 210.0, "x2": 310.0, "y2": 420.0}',
    '[[120.0,210.0],[310.0,210.0],[310.0,420.0],[120.0,420.0]]',
    '{"model": "civicfix_road_damage_segmentation", "version": "v1"}'
);

-- Combined category + severity + priority recommendation
INSERT INTO ai_predictions (
    prediction_run_id, prediction_type,
    predicted_category_id, predicted_severity, predicted_priority,
    confidence_score, raw_output
) VALUES (
    '33333333-1111-1111-1111-333333333333',
    'CLASSIFICATION',
    '11111111-1111-1111-1111-111111111101',
    'HIGH', 'HIGH',
    0.9400,
    '{"category": "pothole", "confidence": 0.94, "rule": "highest_confidence_detection"}'
);
COMMIT;


-- STEP 4: Officer Reviews Issue & Verifies Category/Severity/Priority
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE issues
SET current_status = 'VERIFIED',
    verified_by    = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    verified_at    = CURRENT_TIMESTAMP
WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;


-- STEP 5 & 6: Officer Assigns Worker, Worker Sees Task & Accepts/Starts
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

INSERT INTO assignments (
    id, issue_id, worker_id, department_id, assigned_by, assignment_status
) VALUES (
    '11111111-aaaa-bbbb-cccc-dddddddddddd',
    '99999999-9999-9999-9999-999999999999',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '22222222-2222-2222-2222-222222222201',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'ASSIGNED'
);

INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ASSIGNED',
 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Assigned to Bob Miller');

UPDATE issues SET current_status = 'ASSIGNED'
WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;

-- Worker Bob accepts task & starts work
BEGIN;
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

UPDATE assignments
SET assignment_status = 'ACCEPTED', accepted_at = CURRENT_TIMESTAMP
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'ACCEPTED',
 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Worker accepted task');

UPDATE assignments
SET assignment_status = 'IN_PROGRESS', started_at = CURRENT_TIMESTAMP
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

INSERT INTO assignment_events (assignment_id, event_type, actor_user_id, notes) VALUES
('11111111-aaaa-bbbb-cccc-dddddddddddd', 'IN_PROGRESS',
 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Worker started work on site');

UPDATE issues SET current_status = 'IN_PROGRESS'
WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;


-- STEP 7: Worker Resolves Issue and Uploads Resolution Proof
BEGIN;
SELECT set_config('app.current_user_id', 'cccccccc-cccc-cccc-cccc-cccccccccccc', true);

INSERT INTO resolution_proofs (
    id, issue_id, assignment_id, submitted_by_worker_id, status, description
) VALUES (
    '22222222-aaaa-bbbb-cccc-dddddddddddd',
    '99999999-9999-9999-9999-999999999999',
    '11111111-aaaa-bbbb-cccc-dddddddddddd',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    'SUBMITTED',
    'Pothole filled with fresh asphalt mix and rolled flat.'
);

INSERT INTO resolution_proof_images (
    id, resolution_proof_id, storage_provider, object_key,
    original_filename, mime_type, file_size_bytes, checksum, image_type
) VALUES (
    '44444444-4444-4444-4444-444444444444',
    '22222222-aaaa-bbbb-cccc-dddddddddddd',
    's3',
    'civicfix-resolutions/bob-pothole-after.jpg',
    'pothole_after.jpg', 'image/jpeg', 212000,
    'sha256:d8ef801a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e',
    'AFTER'
);

UPDATE assignments
SET assignment_status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP
WHERE id = '11111111-aaaa-bbbb-cccc-dddddddddddd';

UPDATE issues SET current_status = 'RESOLUTION_SUBMITTED'
WHERE id = '99999999-9999-9999-9999-999999999999';
COMMIT;


-- Officer Verifies Resolution Proof & Marks Issue RESOLVED
BEGIN;
SELECT set_config('app.current_user_id', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);

UPDATE resolution_proofs
SET status = 'VERIFIED',
    reviewed_by_user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    reviewed_at = CURRENT_TIMESTAMP
WHERE id = '22222222-aaaa-bbbb-cccc-dddddddddddd';

UPDATE issues
SET current_status = 'RESOLVED', resolved_at = CURRENT_TIMESTAMP
WHERE id = '99999999-9999-9999-9999-999999999999';

INSERT INTO notifications (
    id, recipient_user_id, notification_type, title, message, issue_id, report_id
) VALUES (
    gen_random_uuid(),
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'STATUS_UPDATE',
    'Issue Resolved',
    'Your reported pothole near College Gate has been resolved.',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888'
);
COMMIT;


-- STEP 8: Citizen Sees Resolved Status & Leaves Feedback
BEGIN;
SELECT set_config('app.current_user_id', 'dddddddd-dddd-dddd-dddd-dddddddddddd', true);

INSERT INTO feedback (
    id, issue_id, report_id, submitted_by_user_id, rating, comment
) VALUES (
    '55555555-aaaa-bbbb-cccc-dddddddddddd',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    5,
    'Excellent job! Repaired within 24 hours of reporting.'
);
COMMIT;


-- ============================================================================
-- 2. DASHBOARD QUERIES (AUTHORITY, WORKER, CITIZEN)
-- ============================================================================

-- Authority Dashboard Metrics
SELECT
    COUNT(*) FILTER (WHERE current_status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED'))
        AS total_open_issues,
    COUNT(*) FILTER (WHERE created_at >= CURRENT_DATE)
        AS issues_reported_today,
    COUNT(*) FILTER (WHERE current_status = 'REPORTED')
        AS pending_triage_count,
    COUNT(*) FILTER (WHERE current_status = 'RESOLUTION_SUBMITTED')
        AS pending_verification_count,
    COUNT(*) FILTER (WHERE department_id IS NULL
        AND current_status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED'))
        AS unassigned_issues_count
FROM issues;

-- Worker Dashboard Tasks
SELECT
    a.id            AS assignment_id,
    a.assignment_status,
    i.id            AS issue_id,
    i.title,
    i.severity,
    i.priority,
    ST_AsText(i.location) AS issue_location
FROM assignments  a
JOIN issues       i ON a.issue_id = i.id
JOIN workers      w ON a.worker_id = w.id
JOIN users        u ON w.user_id   = u.id
WHERE u.email = 'bob.worker@example.com'
  AND a.assignment_status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')
ORDER BY a.assigned_at DESC;

-- Citizen Dashboard My Reports
SELECT
    r.id             AS report_id,
    r.title          AS report_title,
    r.created_at     AS submitted_at,
    i.id             AS canonical_issue_id,
    i.current_status AS issue_status,
    i.resolved_at
FROM reports r
JOIN users u   ON r.reporter_id = u.id
LEFT JOIN issues i ON r.issue_id   = i.id
WHERE u.email = 'john.citizen1@example.com'
ORDER BY r.created_at DESC;


-- ============================================================================
-- 3. SPATIAL MAP & NEAREST-WORKER QUERIES
-- ============================================================================

-- Show Open Issues on Map with Lat/Lng Coordinates
SELECT
    id, title, current_status, severity, priority,
    ST_Y(location::geometry) AS latitude,
    ST_X(location::geometry) AS longitude
FROM issues
WHERE current_status NOT IN ('RESOLVED', 'CLOSED', 'REJECTED');

-- Find Available Workers Near an Issue within 5km Radius
SELECT
    w.id             AS worker_id,
    u.full_name      AS worker_name,
    d.name           AS department_name,
    w.years_experience,
    ST_Distance(w.current_location, i.location) AS distance_meters
FROM workers     w
JOIN users       u ON w.user_id       = u.id
JOIN departments d ON w.department_id = d.id
JOIN issues      i ON i.id = '99999999-9999-9999-9999-999999999999'
WHERE w.availability_status = 'AVAILABLE'
  AND w.worker_status = 'ACTIVE'
  AND ST_DWithin(w.current_location, i.location, 5000.0)
ORDER BY distance_meters ASC;

-- Find Nearby Issues within Radius (e.g. 50 meters for duplicate check)
SELECT
    id, title, current_status,
    ST_Distance(
        location,
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography
    ) AS distance_meters
FROM issues
WHERE ST_DWithin(
    location,
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography,
    50.0
)
ORDER BY distance_meters ASC;


-- ============================================================================
-- 4. ANALYTICS & INSIGHT QUERIES
-- ============================================================================

-- Issues by Category Breakdown
SELECT
    c.name       AS category_name,
    COUNT(i.id)  AS total_issues
FROM issues i
JOIN issue_categories c ON i.category_id = c.id
GROUP BY c.name
ORDER BY total_issues DESC;

-- Average Time to Resolution (in Hours) by Category
SELECT
    c.name AS category_name,
    AVG(EXTRACT(EPOCH FROM (i.resolved_at - i.created_at)) / 3600.0)
        AS avg_resolution_hours
FROM issues i
JOIN issue_categories c ON i.category_id = c.id
WHERE i.resolved_at IS NOT NULL
GROUP BY c.name;

-- Worker Workload & Completion Rate
SELECT
    u.full_name      AS worker_name,
    COUNT(a.id)      AS total_assigned_tasks,
    COUNT(*) FILTER (WHERE a.assignment_status = 'COMPLETED') AS completed_tasks,
    ROUND(
        (COUNT(*) FILTER (WHERE a.assignment_status = 'COMPLETED')::numeric
         / NULLIF(COUNT(a.id), 0)) * 100,
        2
    ) AS completion_percentage
FROM workers   w
JOIN users     u ON w.user_id   = u.id
JOIN assignments a ON a.worker_id = w.id
GROUP BY u.full_name;

-- Issue Hotspots Clustered by 0.001 Spatial Grid (Approx 100m)
SELECT
    ST_AsText(ST_SnapToGrid(location::geometry, 0.001)) AS grid_center,
    COUNT(*)                                             AS incident_count
FROM issues
GROUP BY grid_center
ORDER BY incident_count DESC
LIMIT 10;


-- ============================================================================
-- 5. AI LAYER QUERIES
-- ============================================================================

-- 5a. Retrieve all AI prediction results for a specific report
--     Returns both segmentation detections and category/priority recommendations.
SELECT
    apr.id               AS run_id,
    apr.run_status,
    apr.started_at,
    apr.completed_at,
    m.model_name,
    m.model_version,
    p.prediction_type,
    p.class_id,
    p.class_name,
    p.confidence_score,
    p.bounding_box,
    p.segmentation_polygon,
    ic.name              AS recommended_category_name,
    p.predicted_severity,
    p.predicted_priority,
    p.raw_output
FROM ai_prediction_runs  apr
JOIN ai_models            m  ON apr.model_id          = m.id
LEFT JOIN ai_predictions  p  ON p.prediction_run_id   = apr.id
LEFT JOIN issue_categories ic ON p.predicted_category_id = ic.id
WHERE apr.report_id = '88888888-8888-8888-8888-888888888888'
ORDER BY apr.started_at DESC, p.confidence_score DESC NULLS LAST;


-- 5b. Retrieve only segmentation polygon detections for a given run
--     Useful for overlaying bounding boxes and masks on the citizen's uploaded image.
SELECT
    p.id,
    p.class_id,
    p.class_name,
    p.confidence_score,
    p.bounding_box,
    p.segmentation_polygon,
    p.mask_storage_key
FROM ai_predictions p
WHERE p.prediction_run_id = '33333333-1111-1111-1111-333333333333'
  AND p.prediction_type   = 'IMAGE_SEGMENTATION'
ORDER BY p.confidence_score DESC;


-- 5c. Latest active AI model details (used by db_integration.py to resolve model_id)
SELECT
    id,
    model_name,
    model_version,
    task_type,
    framework,
    class_mapping,
    artifact_object_key,
    metrics
FROM ai_models
WHERE is_active = TRUE
LIMIT 1;


-- 5d. AI prediction run performance summary by model version
SELECT
    m.model_name,
    m.model_version,
    COUNT(apr.id)                                                   AS total_runs,
    COUNT(*) FILTER (WHERE apr.run_status = 'COMPLETED')            AS completed_runs,
    COUNT(*) FILTER (WHERE apr.run_status = 'FAILED')               AS failed_runs,
    ROUND(AVG(EXTRACT(EPOCH FROM (apr.completed_at - apr.started_at))), 2)
                                                                    AS avg_inference_seconds,
    AVG(p.confidence_score) FILTER (WHERE p.prediction_type = 'IMAGE_SEGMENTATION')
                                                                    AS avg_detection_confidence
FROM ai_models          m
LEFT JOIN ai_prediction_runs  apr ON apr.model_id        = m.id
LEFT JOIN ai_predictions       p   ON p.prediction_run_id = apr.id
GROUP BY m.model_name, m.model_version
ORDER BY m.model_version DESC;


-- ============================================================================
-- 6. UNSUPPORTED CATEGORY & AUTHORITY REVIEW ROUTING
-- ============================================================================

-- 6a. Find all prediction runs where NO supported visual class was detected.
--     These reports must be routed to authority review without a fabricated AI prediction.
--     A run is "unsupported" when it COMPLETED but has zero IMAGE_SEGMENTATION rows.
SELECT
    apr.id              AS run_id,
    apr.report_id,
    apr.issue_id,
    apr.started_at,
    r.title             AS report_title,
    r.description       AS citizen_description,
    ST_Y(r.location::geometry) AS latitude,
    ST_X(r.location::geometry) AS longitude
FROM ai_prediction_runs apr
JOIN reports            r   ON r.id = apr.report_id
WHERE apr.run_status = 'COMPLETED'
  AND NOT EXISTS (
      SELECT 1
      FROM ai_predictions p
      WHERE p.prediction_run_id = apr.id
        AND p.prediction_type = 'IMAGE_SEGMENTATION'
  )
ORDER BY apr.started_at DESC;


-- 6b. Reports with FAILED prediction runs (pipeline error — also need authority triage)
SELECT
    apr.id          AS run_id,
    apr.report_id,
    apr.error_message,
    apr.started_at,
    r.title         AS report_title
FROM ai_prediction_runs apr
JOIN reports            r ON r.id = apr.report_id
WHERE apr.run_status = 'FAILED'
ORDER BY apr.started_at DESC;


-- 6c. Issues awaiting triage that have no AI prediction run at all
--     (e.g. image upload completed but inference job not yet queued)
SELECT
    i.id            AS issue_id,
    i.title,
    i.current_status,
    i.created_at,
    ri.object_key   AS image_object_key
FROM issues         i
JOIN reports        r  ON r.issue_id  = i.id
JOIN report_images  ri ON ri.report_id = r.id
WHERE i.current_status = 'REPORTED'
  AND NOT EXISTS (
      SELECT 1
      FROM ai_prediction_runs apr
      WHERE apr.issue_id = i.id
         OR apr.report_id = r.id
  )
ORDER BY i.created_at ASC;
