# CivicFix Database & AI Data Layer Architecture Specification

This document provides the complete, production-ready specification for the **CivicFix** database and AI data layer.

---

## 1. Executive Database Decisions

*   **Database Engine**: **PostgreSQL (v15+)**. Chosen for its enterprise-grade durability, transaction safety, robust support for JSONB, and advanced trigger capabilities.
*   **Geographical Extension**: **PostGIS**. Mandatory to handle coordinate calculations. All locations are stored using `geography(Point, 4326)` representing longitude and latitude.
*   **Primary Keys**: **UUIDv4** (`gen_random_uuid()`) for all primary keys. This prevents ID enumeration attacks, enables safe offline/client-side ID generation, and supports horizontal scaling without ID collisions.
*   **Aesthetic & Style Rules**:
    *   Lowercase table and column names using snake_case (e.g., `issue_status_history`).
    *   Explicit naming conventions for all constraints (e.g., `fk_reports_reporter`).
    *   Separate image metadata storage from the core operational tables.

---

## 2. Problems in the Current ER Diagram

Critique of the initial rough ER diagram:
1.  **Multivalued Skills Column**: `workers.skills` was proposed as a comma-separated string or simple array. This violates **First Normal Form (1NF)**. It prevents joining on skills, indexing them efficiently, or ensuring skill validation.
2.  **Single Image Limitation**: `issues.image_url` and `reports.image_url` limit citizens and workers to uploading exactly one image. A proper audit and resolution flow requires multiple photos (e.g., wide shot, close-up, and before/after verification).
3.  **Ambiguous Report vs. Issue Ownership**: The rough design did not clearly separate a citizen's subjective report from the city's canonical operational issue. Keeping them on a single tier causes duplicate reports to overwrite canonical status data or bloat the issues backlog with duplicate workflows.
4.  **No AI Prediction Auditing**: The rough design lacks tracking for model versions, prediction runs, and confidence scores. Overwriting fields directly with AI predictions destroys the audit trail of model performance and human overrides.
5.  **No Assignment Event Trail**: `assignments` only tracked the current status and timestamps. There was no historical trail of *why* assignments were rejected or cancelled, which is critical for worker performance analysis.

---

## 3. Report-versus-Issue Analysis

*   **Option A Selected**: `reports.issue_id` is nullable during intake. After triage, it is linked to an existing issue or a new issue.
*   **Rationale**:
    *   **Intake Isolation**: Citizens submit reports asynchronously. We should not pollute the `issues` board with unverified data or duplicates.
    *   **Duplicate Merging**: When a new report is submitted, spatial and text AI models check for active issues nearby. If a match is found (e.g., within 20 meters), the report is linked to the existing issue. This keeps the operational view clean.
    *   **Historical Preservation**: De-duplicating a report does not delete it. The citizen's original text, coordinates, and images remain intact in the `reports` table.
    *   **Split Mechanism**: If an Authority mistakenly links a report to the wrong issue, they can easily split it by creating a new `issues` record and updating `reports.issue_id` to point to the new ID. No data is lost.

---

## 4. Final Table List

### 1. `roles` (MVP)
*   **Purpose**: Roles mapping (ADMIN, AUTHORITY, WORKER, CITIZEN).
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.
*   **Cardinality**: 1:N with `user_roles`.

### 2. `users` (MVP)
*   **Purpose**: Core identity, authentication, and credentials.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.
*   **Constraints**: Lowercase and format checks for email.
*   **Cardinality**: 1:N with `user_roles`, `reports`, `notifications`, `feedback`, `audit_logs`.

### 3. `user_roles` (MVP)
*   **Purpose**: Many-to-many junction for users and roles.
*   **Primary Key**: `(user_id, role_id)` composite.
*   **Foreign Keys**: `user_id` -> `users(id)` (CASCADE), `role_id` -> `roles(id)` (RESTRICT).

### 4. `departments` (MVP)
*   **Purpose**: Municipal departments (DPW, DSN, DWP, DPR).
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.

### 5. `issue_categories` (MVP)
*   **Purpose**: Reference table of issue types (pothole, streetlight, etc.).
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.

### 6. `department_categories` (MVP)
*   **Purpose**: Junction mapping departments to categories they can resolve.
*   **Primary Key**: `(department_id, category_id)` composite.
*   **Foreign Keys**: `department_id` -> `departments(id)` (CASCADE), `category_id` -> `issue_categories(id)` (CASCADE).

### 7. `skills` (MVP)
*   **Purpose**: Reference table of worker skills (asphalt_paving, plumbing, etc.).
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.

### 8. `workers` (MVP)
*   **Purpose**: Profile for municipal field workers.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: `user_id` -> `users(id)` (RESTRICT), `department_id` -> `departments(id)` (RESTRICT).

### 9. `worker_skills` (MVP)
*   **Purpose**: Junction table linking workers to their skills.
*   **Primary Key**: `(worker_id, skill_id)` composite.
*   **Foreign Keys**: `worker_id` -> `workers(id)` (CASCADE), `skill_id` -> `skills(id)` (RESTRICT).

### 10. `issue_statuses` (MVP)
*   **Purpose**: State lookup table (REPORTED, VERIFIED, IN_PROGRESS, RESOLVED, etc.).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 11. `severity_levels` (MVP)
*   **Purpose**: Severity weights lookup (LOW, MEDIUM, HIGH, CRITICAL).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 12. `priority_levels` (MVP)
*   **Purpose**: Priority weights lookup (LOW, MEDIUM, HIGH, CRITICAL).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 13. `assignment_statuses` (MVP)
*   **Purpose**: Assignment states lookup (ASSIGNED, ACCEPTED, REJECTED, COMPLETED).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 14. `resolution_proof_statuses` (MVP)
*   **Purpose**: Workflow state for worker submissions (SUBMITTED, VERIFIED, REJECTED).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 15. `relationship_types` (MVP)
*   **Purpose**: Relationship types (DUPLICATE, RELATED, MERGED, SPLIT).
*   **Primary Key**: `id` VARCHAR(50).
*   **Foreign Keys**: None.

### 16. `issues` (MVP)
*   **Purpose**: Canonical operational record of a civic problem.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `approved_category_id` -> `issue_categories(id)` (RESTRICT)
    *   `approved_severity` -> `severity_levels(id)` (RESTRICT)
    *   `approved_priority` -> `priority_levels(id)` (RESTRICT)
    *   `current_status` -> `issue_statuses(id)` (RESTRICT)
    *   `department_id` -> `departments(id)` (RESTRICT)

### 17. `reports` (MVP)
*   **Purpose**: Subjective citizen submissions.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `reporter_id` -> `users(id)` (RESTRICT)
    *   `issue_id` -> `issues(id)` (RESTRICT)

### 18. `image_metadata` (MVP)
*   **Purpose**: Centralized storage mapping for file references.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: `uploaded_by` -> `users(id)` (SET NULL).

### 19. `report_images` (MVP)
*   **Purpose**: Junction mapping images to reports.
*   **Primary Key**: `(report_id, image_id)` composite.
*   **Foreign Keys**: `report_id` -> `reports(id)` (CASCADE), `image_id` -> `image_metadata(id)` (CASCADE).

### 20. `issue_images` (MVP)
*   **Purpose**: Junction mapping images to issues (e.g. representative photos).
*   **Primary Key**: `(issue_id, image_id)` composite.
*   **Foreign Keys**: `issue_id` -> `issues(id)` (CASCADE), `image_id` -> `image_metadata(id)` (CASCADE).

### 21. `issue_relationships` (MVP)
*   **Purpose**: Duplication, parent-child, and merge history.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `source_issue_id` -> `issues(id)` (RESTRICT)
    *   `target_issue_id` -> `issues(id)` (RESTRICT)
    *   `relationship_type` -> `relationship_types(id)` (RESTRICT)
    *   `reviewed_by` -> `users(id)` (SET NULL)

### 22. `assignments` (MVP)
*   **Purpose**: Issue assignments to field workers.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `issue_id` -> `issues(id)` (RESTRICT)
    *   `worker_id` -> `workers(id)` (RESTRICT)
    *   `assigned_by` -> `users(id)` (RESTRICT)
    *   `status` -> `assignment_statuses(id)` (RESTRICT)

### 23. `assignment_events` (MVP)
*   **Purpose**: Historic event trail for assignments (rejections, cancellations).
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `assignment_id` -> `assignments(id)` (CASCADE)
    *   `status` -> `assignment_statuses(id)` (RESTRICT)
    *   `changed_by` -> `users(id)` (RESTRICT)

### 24. `issue_status_history` (MVP)
*   **Purpose**: Lifecycle logging of issue status transitions.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `issue_id` -> `issues(id)` (CASCADE)
    *   `previous_status` -> `issue_statuses(id)` (RESTRICT)
    *   `new_status` -> `issue_statuses(id)` (RESTRICT)
    *   `changed_by` -> `users(id)` (SET NULL)

### 25. `resolution_proofs` (MVP)
*   **Purpose**: Worker-submitted completion documentation.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `assignment_id` -> `assignments(id)` (RESTRICT)
    *   `worker_id` -> `workers(id)` (RESTRICT)
    *   `before_image_id` -> `image_metadata(id)` (RESTRICT)
    *   `after_image_id` -> `image_metadata(id)` (RESTRICT)
    *   `status` -> `resolution_proof_statuses(id)` (RESTRICT)
    *   `reviewed_by` -> `users(id)` (RESTRICT)

### 26. `notifications` (MVP)
*   **Purpose**: Persistent in-app messages.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `recipient_id` -> `users(id)` (CASCADE)
    *   `related_issue_id` -> `issues(id)` (SET NULL)
    *   `related_report_id` -> `reports(id)` (SET NULL)

### 27. `feedback` (MVP)
*   **Purpose**: User rating and reviews for resolved issues.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `user_id` -> `users(id)` (RESTRICT)
    *   `issue_id` -> `issues(id)` (RESTRICT)
    *   `report_id` -> `reports(id)` (SET NULL)

### 28. `audit_logs` (MVP)
*   **Purpose**: Append-only log of database mutations.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: `actor_user_id` -> `users(id)` (RESTRICT).

### 29. `ai_prediction_runs` (Future / AI Layer)
*   **Purpose**: Log of model executions.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `issue_id` -> `issues(id)` (CASCADE)
    *   `report_id` -> `reports(id)` (CASCADE)

### 30. `ai_predictions` (Future / AI Layer)
*   **Purpose**: Specific classification, duplicate scoring, and severity outputs.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**:
    *   `prediction_run_id` -> `ai_prediction_runs(id)` (CASCADE)
    *   `predicted_category_id` -> `issue_categories(id)` (RESTRICT)
    *   `predicted_severity` -> `severity_levels(id)` (RESTRICT)
    *   `predicted_priority` -> `priority_levels(id)` (RESTRICT)
    *   `target_issue_id` -> `issues(id)` (RESTRICT)

### 31. `dataset_registry` (Future / ML Ingestion)
*   **Purpose**: Ingested datasets listing.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: None.

### 32. `dataset_samples` (Future / ML Ingestion)
*   **Purpose**: Annotations and data splits for ML model training.
*   **Primary Key**: `id` UUID.
*   **Foreign Keys**: `dataset_id` -> `dataset_registry(id)` (RESTRICT).

---

## 5. Final Relationship Model

The relationship model follows these connections:
*   A user can have many roles through `user_roles`.
*   A worker belongs to a department and has many skills through `worker_skills`.
*   A department can handle many categories through `department_categories`.
*   A citizen (`users`) submits `reports` which contain `report_images` referencing `image_metadata`.
*   A report is matched to a canonical `issue`. Multiple reports can point to the same issue.
*   An issue has many assignments, but only one active assignment at a time (enforced by a partial unique index).
*   Workers upload before/after photos linked to `resolution_proofs`.
*   Feedback is linked to a user and the resolved issue.
*   The database triggers record changes in `issue_status_history` and `audit_logs` automatically.

---

## 6. PostgreSQL and PostGIS Decisions

*   **Extensions**: `postgis` and `pgcrypto` enabled.
*   **Spatial Storage**: `geography(Point, 4326)` representing WGS84 coordinate systems (longitude/latitude).
*   **Index**: GiST (Generalized Search Tree) indexes are created on `issues.location`, `reports.location`, and `workers.current_location` to speed up bounding boxes and radial queries.
*   **Accuracy**: Using `geography` guarantees that spatial calculations (e.g. `ST_DWithin`) operate in meters instead of degrees, eliminating projection coordinate errors.

---

## 11. Normalization Analysis

*   **First Normal Form (1NF)**: All columns contain atomic values. Comma-separated strings for worker skills are eliminated and placed in `worker_skills`. Repeating image columns are eliminated and handled by the `image_metadata` and junction tables.
*   **Second Normal Form (2NF)**: All tables are in 1NF and have primary keys. All non-key columns depend fully on the primary key (composite keys are only used in junction tables).
*   **Third Normal Form (3NF)**: All tables are in 2NF, and no transitive dependencies exist. For example, `workers.department_name` is eliminated because it is dependent on `workers.department_id` which depends on `workers.id`.
*   **Justified Denormalization**:
    *   `issues.current_status`: Kept in the issues table for rapid board visualization, while the full transition trail is preserved in `issue_status_history`.
    *   `issues.approved_priority` and `issues.approved_severity`: Stored on the issue record for fast reads, whereas model predictions are stored separately in `ai_predictions`.

---

## 12. Deletion Policies & Constraints

*   **Accidental Deletion Protection**:
    *   `ON DELETE RESTRICT` is used for critical entities (e.g. `users`, `issues`, `departments`, `workers`). This prevents deleting a user who has submitted reports, or deleting a department that has active workers.
    *   `ON DELETE CASCADE` is reserved for dependent child records that have no historical value without their parent (e.g. `user_roles`, `worker_skills`, `report_images`, `issue_images`, `assignment_events`).
    *   `ON DELETE SET NULL` is used for non-essential audit fields (e.g. `image_metadata.uploaded_by`, `issue_relationships.reviewed_by`).
*   **Key Check Constraints**:
    *   Email checks: lowercase string format and regex validation.
    *   Confidence and duplicate scores: `[0.000, 1.000]`.
    *   Feedback Rating: `[1, 5]`.
    *   Dimensions and file sizes: `> 0`.
    *   Self-relationships in issue merges are blocked (`source_issue_id != target_issue_id`).

---

## 13. Indexing Strategy

*   **Spatial (GiST)**:
    *   `idx_issues_location` on `issues(location)`
    *   `idx_reports_location` on `reports(location)`
    *   `idx_workers_location` on `workers(current_location)`
*   **B-Tree Indexes for Foreign Keys**:
    *   All foreign keys are explicitly indexed to avoid full table scans during joins and deletion checks.
*   **Partial Indexes**:
    *   `idx_notifications_recipient_unread` on `notifications(recipient_id) WHERE is_read = FALSE` (reduces indexing overhead, speeds up notification centers).
    *   `idx_unique_active_assignment` on `assignments(issue_id) WHERE status IN ('ASSIGNED', 'ACCEPTED', 'IN_PROGRESS')` (acts as a constraint ensuring single-worker-active integrity).

---

## 14. Dataset Research Table

| Dataset Name | Official Source URL | Download URL | Records/Images | Classes | Format | License | Commercial Use | Student / MVP Suitability | Limitations |
|---|---|---|---|---|---|---|---|---|---|
| **RDD2022** (Road Damage Dataset 2022) | [GitHub Source](https://github.com/sekilab/RoadDamageDetector) | [Kaggle Dataset](https://www.kaggle.com/datasets/chitholian/road-damage-dataset-rdd2022) | 47,420 images | Potholes, Transverse Cracks, Alligator Cracks | Pascal VOC XML / YOLO | CC BY-SA 4.0 | Yes (Attribution required) | High | Variable lighting, mostly Japanese/Indian roads. |
| **PothRGBD** | [ArXiv Research](https://arxiv.org/abs/2103.01168) | [Kaggle Dataset](https://www.kaggle.com/datasets/chitholian/pothrgbd) | 1,000 paired images | Pothole segmentation | PNG + depth / YOLO | MIT License | Yes | High | Limited size, Intel RealSense specific depth. |
| **Urban Community Issues** | [Kaggle Source](https://www.kaggle.com/datasets/rajeevpaudel/urban-community-issues) | Same as Source | 3,000 images | Garbage, Pothole, Streetlight, Drains | YOLO txt | CC BY-NC-SA 4.0 | No (Non-commercial) | High for MVP/Hackathon | Commercial prohibition. Crowdsourced labels. |
| **OpenStreetMap & Overpass API** | [OSM Portal](https://www.openstreetmap.org/) | [Overpass Turbo](https://overpass-turbo.eu/) | Millions of vector records | Highways, streetlights, schools, hospitals | GeoJSON / PBF | ODbL | Yes (Attribution required) | High | Volunteer density variation. |

---

## 15. Dataset Ingestion and Preprocessing Plan

1.  **Pipeline Sequence**:
    *   **Acquisition**: Python script downloads raw data using Kaggle API / OSM Overpass API, validating MD5 checksums.
    *   **Validation**: Corrupt images are detected using OpenCV (`cv2.imread(path) is not None`) and logged as `is_corrupted = TRUE` in `dataset_samples`.
    *   **Normalization**: Coordinates and bounding boxes normalized to standard float range `[0.0, 1.0]`. Class names mapped to system lookup categories.
    *   **Deduplication**: Duplicate images flagged by perceptual hashing (pHash).
    *   **Splitting**: Data partitioned into 70% Train, 15% Validation, and 15% Test. Data leakage is prevented by splitting on geographical grid cells rather than random sampling.
    *   **Registry**: The run metadata is recorded in `dataset_registry` and samples in `dataset_samples`.
2.  **Metadata Registry**:
    *   A clean audit trail matches trained model checkpoints (`model_registry` or model version string) directly to the `dataset_registry` version and preprocessing script version, ensuring reproducibility.

---

## 16. Priority-Model Feature Design

To feed the ML priority scoring model, the database schema supports:
1.  **Issue Frequency**: Count of reports linked to the same issue (`SELECT COUNT(*) FROM reports WHERE issue_id = ...`).
2.  **Location Proximity**: Calculations for distances to schools, hospitals, or transit nodes.
3.  **Road Classification**: Joins on road class (arterial, residential, highway).
4.  **Weather Observations**: Nullable fields for local temperature, rainfall intensity, and wind speed at report time.
5.  **Historical SLAs**: Categorized resolution times (`resolved_at - created_at`) for similar historical issues in the same area.
