-- Migration: 009_seed_data
-- Description: Seeds system static configuration reference records.

-- 1. Insert System Roles
INSERT INTO roles (id, name, description) VALUES
('00000000-0000-0000-0000-000000000001', 'ADMIN', 'System Administrator with full access rights.'),
('00000000-0000-0000-0000-000000000002', 'AUTHORITY', 'Municipal Authority worker capable of triaging, verifying, and assigning work.'),
('00000000-0000-0000-0000-000000000003', 'WORKER', 'Field worker assigned to resolve issues.'),
('00000000-0000-0000-0000-000000000004', 'CITIZEN', 'General public user reporting issues.')
ON CONFLICT (id) DO NOTHING;

-- 2. Insert Issue Statuses
INSERT INTO issue_statuses (id, description) VALUES
('REPORTED', 'Citizen report submitted and waiting for triage.'),
('UNDER_REVIEW', 'Issue is currently under review by municipal authorities.'),
('VERIFIED', 'Issue verified by authorities, pending department or worker assignment.'),
('ASSIGNED', 'Issue assigned to a department and worker, awaiting acceptance.'),
('ACCEPTED', 'Worker accepted the assignment.'),
('IN_PROGRESS', 'Worker started physical execution of work on site.'),
('RESOLUTION_SUBMITTED', 'Worker submitted resolution evidence (before/after photos).'),
('VERIFICATION_PENDING', 'Authorities verifying worker completion evidence.'),
('RESOLVED', 'Issue successfully resolved and confirmed by authority verification.'),
('REOPENED', 'Resolved issue reopened due to failed verification or recurring problem.'),
('CLOSED', 'Issue closed permanently.'),
('REJECTED', 'Issue rejected by authority (invalid report, private property, etc.).'),
('DUPLICATE', 'Issue marked as duplicate and linked to a canonical issue.')
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Severity Levels
INSERT INTO severity_levels (id, weight, description) VALUES
('LOW', 10, 'Minor aesthetic or low-risk issue.'),
('MEDIUM', 20, 'Moderate damage or issue causing inconvenience.'),
('HIGH', 30, 'High risk. Structural damage or traffic blockage.'),
('CRITICAL', 40, 'Emergency response required.')
ON CONFLICT (id) DO NOTHING;

-- 4. Insert Priority Levels
INSERT INTO priority_levels (id, weight, description) VALUES
('LOW', 10, 'Resolve within normal SLA (e.g. 14 days).'),
('MEDIUM', 20, 'Resolve within priority SLA (e.g. 7 days).'),
('HIGH', 30, 'Resolve quickly (e.g. 48 hours).'),
('CRITICAL', 40, 'Emergency response required (e.g. within 12 hours).')
ON CONFLICT (id) DO NOTHING;

-- 5. Insert Assignment Statuses
INSERT INTO assignment_statuses (id, description) VALUES
('ASSIGNED', 'Assigned to worker, pending worker action.'),
('ACCEPTED', 'Accepted by worker.'),
('REJECTED', 'Rejected by worker with reason.'),
('IN_PROGRESS', 'Work started on site.'),
('COMPLETED', 'Worker completed work and submitted evidence.'),
('CANCELLED', 'Assignment cancelled by authorities.')
ON CONFLICT (id) DO NOTHING;

-- 6. Insert Resolution Proof Statuses
INSERT INTO resolution_proof_statuses (id, description) VALUES
('SUBMITTED', 'Worker submitted proof, pending review.'),
('VERIFIED', 'Proof verified by authority.'),
('REJECTED', 'Proof rejected by authority. Worker must resubmit.'),
('RESUBMITTED', 'Worker resubmitted correction proof.')
ON CONFLICT (id) DO NOTHING;

-- 7. Insert Issue Relationship Types
INSERT INTO relationship_types (id, description) VALUES
('DUPLICATE', 'Report or issue duplicates an existing canonical issue.'),
('RELATED', 'Issue is physically near or logically linked to another issue.'),
('MERGED', 'Issue is merged into another issue.'),
('SPLIT', 'Issue was wrongly merged/grouped and split into its own issue.')
ON CONFLICT (id) DO NOTHING;

-- 8. Insert Issue Categories (Fixed UUIDs)
INSERT INTO issue_categories (id, code, name, description) VALUES
('11111111-1111-1111-1111-111111111101', 'pothole', 'Pothole', 'Potholes or damage on the street surface.'),
('11111111-1111-1111-1111-111111111102', 'damaged_road', 'Damaged Road', 'Cracks, erosion, sinkholes, or damaged pavement.'),
('11111111-1111-1111-1111-111111111103', 'streetlight', 'Broken Streetlight', 'Dark or malfunctioning streetlights.'),
('11111111-1111-1111-1111-111111111104', 'garbage', 'Overflowing Garbage', 'Garbage bins overflowing, illegal waste dumps.'),
('11111111-1111-1111-1111-111111111105', 'water_leakage', 'Water Leakage', 'Burst pipes, water mains leaking clean water.'),
('11111111-1111-1111-1111-111111111106', 'blocked_drain', 'Blocked Drain', 'Stormwater drains blocked with debris.'),
('11111111-1111-1111-1111-111111111107', 'fallen_tree', 'Fallen Tree', 'Trees or branches blocking roads or power lines.'),
('11111111-1111-1111-1111-111111111108', 'infrastructure_damage', 'Infrastructure Damage', 'Damaged public benches, fences, bus stops, or bridges.'),
('11111111-1111-1111-1111-111111111109', 'illegal_dumping', 'Illegal Dumping', 'Unauthorized dumping of trash or hazardous materials.'),
('11111111-1111-1111-1111-111111111110', 'other', 'Other', 'Civic issues not covered by existing categories.')
ON CONFLICT (id) DO NOTHING;

-- 9. Insert Departments (Fixed UUIDs)
INSERT INTO departments (id, code, name, description) VALUES
('22222222-2222-2222-2222-222222222201', 'ROAD_MAINT', 'Road Maintenance', 'Handles road repairs, potholes, and physical pavement.'),
('22222222-2222-2222-2222-222222222202', 'SANITATION', 'Sanitation', 'Handles garbage collection, waste bins, and illegal dumping.'),
('22222222-2222-2222-2222-222222222203', 'ELECTRICAL', 'Electrical', 'Handles municipal power, streetlights, and electrical problems.'),
('22222222-2222-2222-2222-222222222204', 'WATER_SUPPLY', 'Water Supply', 'Handles municipal water supply and water main leaks.'),
('22222222-2222-2222-2222-222222222205', 'DRAINAGE', 'Drainage', 'Handles stormwater drains, culverts, and flood prevention.'),
('22222222-2222-2222-2222-222222222206', 'PARKS', 'Parks', 'Handles fallen trees, vegetation clearance, and public parks.'),
('22222222-2222-2222-2222-222222222207', 'EMERGENCY', 'Emergency Services', 'Handles high priority emergency hazards.')
ON CONFLICT (id) DO NOTHING;

-- 10. Insert Worker Skills
INSERT INTO skills (id, name, description) VALUES
('33333333-3333-3333-3333-333333333301', 'pothole_repair', 'Pothole filling, asphalt mixing, compaction.'),
('33333333-3333-3333-3333-333333333302', 'road_repair', 'Pavement resurfacing, road grading.'),
('33333333-3333-3333-3333-333333333303', 'drainage_maintenance', 'Clearing storm drains, culvert repair.'),
('33333333-3333-3333-3333-333333333304', 'electrical_wiring', 'Repairing municipal high-voltage lines, streetlights.'),
('33333333-3333-3333-3333-333333333305', 'chainsaw_operation', 'Felling damaged trees, branch pruning.')
ON CONFLICT (id) DO NOTHING;
