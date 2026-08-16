-- Migration: 009_seed_data
-- Description: Seeds reference data for roles, issue categories, departments, department category preferences, skills, and workflow states.

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
('LOW', 10, 'Minor aesthetic or low-risk issue. No danger to traffic or life.'),
('MEDIUM', 20, 'Moderate damage or issue causing inconvenience, potential risk over time.'),
('HIGH', 30, 'High risk. Structural damage, traffic blockage, or outage of important services.'),
('CRITICAL', 40, 'Extreme risk. High likelihood of injury, vehicle damage, or structural failure.')
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
('RELATED', 'Issue is physically near or logically linked to another issue, but not a duplicate.'),
('MERGED', 'Issue is merged into another issue (reports transferred).'),
('SPLIT', 'Issue was wrongly merged/grouped and split into its own issue.')
ON CONFLICT (id) DO NOTHING;

-- 8. Insert Issue Categories (Fixed UUIDs for reference mapping)
INSERT INTO issue_categories (id, name, code, description) VALUES
('11111111-1111-1111-1111-111111111101', 'Pothole', 'pothole', 'Potholes or damage on the street surface.'),
('11111111-1111-1111-1111-111111111102', 'Damaged Road', 'damaged_road', 'Cracks, erosion, sinkholes, or large sections of damaged pavement.'),
('11111111-1111-1111-1111-111111111103', 'Broken Streetlight', 'streetlight', 'Dark or malfunctioning streetlights.'),
('11111111-1111-1111-1111-111111111104', 'Overflowing Garbage', 'garbage', 'Garbage bins overflowing, illegal waste dumps.'),
('11111111-1111-1111-1111-111111111105', 'Water Leakage', 'water_leakage', 'Burst pipes, water mains leaking clean water on public streets.'),
('11111111-1111-1111-1111-111111111106', 'Blocked Drain', 'blocked_drain', 'Stormwater drains blocked with debris, flooding streets.'),
('11111111-1111-1111-1111-111111111107', 'Fallen Tree', 'fallen_tree', 'Trees or branches blocking roads, sidewalks, or power lines.'),
('11111111-1111-1111-1111-111111111108', 'Infrastructure Damage', 'infrastructure_damage', 'Damaged public benches, fences, bus stops, or bridges.'),
('11111111-1111-1111-1111-111111111109', 'Illegal Dumping', 'illegal_dumping', 'Unauthorized dumping of trash or hazardous materials.'),
('11111111-1111-1111-1111-111111111110', 'Other', 'other', 'Civic issues not covered by existing categories.')
ON CONFLICT (id) DO NOTHING;

-- 9. Insert Departments (Fixed UUIDs for reference mapping)
INSERT INTO departments (id, name, code, description) VALUES
('22222222-2222-2222-2222-222222222201', 'Department of Public Works', 'DPW', 'Handles road repairs, potholes, and physical infrastructure.'),
('22222222-2222-2222-2222-222222222202', 'Department of Sanitation', 'DSN', 'Handles garbage collection, waste bins, and illegal dumping cleanups.'),
('22222222-2222-2222-2222-222222222203', 'Department of Water & Power', 'DWP', 'Handles municipal water supply, streetlights, and electrical problems.'),
('22222222-2222-2222-2222-222222222204', 'Department of Parks & Recreation', 'DPR', 'Handles fallen trees, vegetation clearance, and public parks.')
ON CONFLICT (id) DO NOTHING;

-- 10. Map Departments to Issue Categories
INSERT INTO department_categories (department_id, category_id, is_preferred) VALUES
('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101', true),  -- DPW -> Pothole
('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111102', true),  -- DPW -> Damaged Road
('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111108', true),  -- DPW -> Infrastructure Damage
('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111104', true),  -- DSN -> Garbage
('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111109', true),  -- DSN -> Illegal Dumping
('22222222-2222-2222-2222-222222222202', '11111111-1111-1111-1111-111111111106', true),  -- DSN -> Blocked Drain (Shared)
('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111103', true),  -- DWP -> Streetlight
('22222222-2222-2222-2222-222222222203', '11111111-1111-1111-1111-111111111105', true),  -- DWP -> Water Leakage
('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111107', true)   -- DPR -> Fallen Tree
ON CONFLICT ON CONSTRAINT pk_department_categories DO NOTHING;

-- 11. Insert Worker Skills
INSERT INTO skills (id, name, description) VALUES
('33333333-3333-3333-3333-333333333301', 'asphalt_paving', 'Pavement surfacing, pothole filling, asphalt mixing and rolling.'),
('33333333-3333-3333-3333-333333333302', 'electrical_wiring', 'Repairing municipal high-voltage wires, changing streetlights.'),
('33333333-3333-3333-3333-333333333303', 'plumbing_welding', 'Welding and repairing municipal water pipes, mains leaks fix.'),
('33333333-3333-3333-3333-333333333304', 'chainsaw_operation', 'Felling damaged trees, branches pruning, safety management.'),
('33333333-3333-3333-3333-333333333305', 'heavy_machinery', 'Operating excavators, backhoes, and road rollers.'),
('33333333-3333-3333-3333-333333333306', 'waste_sorting', 'Handling garbage collection, sorting hazardous chemicals.')
ON CONFLICT (id) DO NOTHING;
