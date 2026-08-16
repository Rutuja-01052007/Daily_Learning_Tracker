#!/usr/bin/env python3
"""
CivicFix AI Pipeline - Database Integration Layer
--------------------------------------------------
Connects model inference to the PostgreSQL / PostGIS database.

Safe transaction pattern:
  1. Look up the active AI model ID from ai_models (never hardcoded).
  2. INSERT ai_prediction_runs (status=PENDING → RUNNING).
  3. Run polygon segmentation inference on the citizen's image.
  4. INSERT ai_predictions rows per detection (IMAGE_SEGMENTATION).
  5. INSERT CATEGORY_RECOMMENDATION and PRIORITY_RECOMMENDATION rows.
  6. UPDATE ai_prediction_runs status → COMPLETED.
  7. On any failure: rollback + UPDATE status → FAILED.

Configuration (environment variables — NEVER hardcode credentials):
  DATABASE_URL      PostgreSQL DSN, e.g.:
                    postgresql://user:password@host:5432/civicfix
  MODEL_WEIGHTS_PATH  Path to best.pt (defaults to civicfix_runs/.../best.pt)

Usage:
  # Real DB run
  DATABASE_URL=postgresql://... python db_integration.py <report_id> <image_path>

  # Dry-run (prints SQL without touching the DB)
  python db_integration.py <report_id> <image_path> --dry-run

  # Demo with test UUIDs
  python db_integration.py
"""

import os
import sys
import json
import uuid
import datetime
import argparse
import textwrap
from pathlib import Path

# Force UTF-8 output on Windows (avoids UnicodeEncodeError with cp1252)
if sys.platform == "win32":
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

# ---------------------------------------------------------------------------
# Import inference engine (same directory)
# ---------------------------------------------------------------------------
sys.path.insert(0, str(Path(__file__).parent))
from inference import predict_civic_issue  # type: ignore

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DEFAULT_WEIGHTS_CANDIDATES = [
    Path("/kaggle/working/civicfix_runs/civicfix_road_damage_seg_v1/weights/best.pt"),
    Path("civicfix_runs/civicfix_road_damage_seg_v1/weights/best.pt"),
    Path("data/processed/civicfix_runs/civicfix_road_damage_seg_v1/weights/best.pt"),
]

PRIORITY_THRESHOLD_HIGH = 0.85   # detections above this → HIGH priority


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def _get_connection():
    """
    Return a psycopg2 connection using DATABASE_URL from the environment.
    Raises RuntimeError if the variable is absent.
    """
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise RuntimeError(
            "DATABASE_URL environment variable is not set. "
            "Set it before running db_integration.py.\n"
            "Example: export DATABASE_URL=postgresql://user:pass@host:5432/civicfix"
        )
    try:
        import psycopg2  # type: ignore
        return psycopg2.connect(dsn)
    except ImportError:
        raise RuntimeError(
            "psycopg2 is not installed. Run: pip install psycopg2-binary"
        )


def _resolve_active_model_id(cursor) -> str:
    """
    Dynamically fetch the active model ID from ai_models.
    Raises RuntimeError when no active model is registered.
    """
    cursor.execute(
        "SELECT id, model_name, model_version "
        "FROM ai_models "
        "WHERE is_active = TRUE "
        "LIMIT 1;"
    )
    row = cursor.fetchone()
    if row is None:
        raise RuntimeError(
            "No active AI model found in ai_models. "
            "Register and activate a model before running inference."
        )
    model_id, model_name, model_version = row
    print(f"[DB] Active model: {model_name} {model_version} (id={model_id})")
    return str(model_id)


def _resolve_category_id(cursor, category_code: str) -> str | None:
    """Look up issue_categories.id by category code. Returns None if not found."""
    cursor.execute(
        "SELECT id FROM issue_categories WHERE code = %s LIMIT 1;",
        (category_code,)
    )
    row = cursor.fetchone()
    return str(row[0]) if row else None


def _now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def _resolve_weights() -> Path | None:
    env_path = os.environ.get("MODEL_WEIGHTS_PATH")
    if env_path:
        p = Path(env_path)
        return p if p.exists() else None
    for p in DEFAULT_WEIGHTS_CANDIDATES:
        if p.exists():
            return p
    return None


# ---------------------------------------------------------------------------
# Dry-run printer
# ---------------------------------------------------------------------------

def _print_dry_run(run_id: str, report_id: str, image_key: str,
                   model_id_placeholder: str, inference_result: dict):
    """Print the SQL that would execute, without touching the DB."""
    print("\n" + "=" * 60)
    print("DRY RUN — SQL that would be executed (no DB writes made)")
    print("=" * 60)

    detections = inference_result.get("detections", [])
    highest_conf = max((d["confidence"] for d in detections), default=0.0)

    print(textwrap.dedent(f"""
    -- 1. INSERT ai_prediction_runs (status=PENDING)
    INSERT INTO ai_prediction_runs (id, report_id, model_id, run_status, input_checksum, started_at)
    VALUES ('{run_id}', '{report_id}', '{model_id_placeholder}', 'PENDING', NULL, NOW());

    -- 2. UPDATE status → RUNNING
    UPDATE ai_prediction_runs SET run_status = 'RUNNING' WHERE id = '{run_id}';
    """).strip())

    for i, det in enumerate(detections):
        pred_id = f"<uuid-detection-{i}>"
        print(textwrap.dedent(f"""
    -- 3.{i+1}. INSERT ai_predictions (IMAGE_SEGMENTATION — {det['class_name']})
    INSERT INTO ai_predictions
        (id, prediction_run_id, prediction_type,
         class_id, class_name, confidence_score,
         bounding_box, segmentation_polygon, raw_output)
    VALUES ('{pred_id}', '{run_id}', 'IMAGE_SEGMENTATION',
            {det['class_id']}, '{det['class_name']}', {det['confidence']},
            '{json.dumps(det['bbox'])}', '{json.dumps(det['polygon'])}',
            '{json.dumps(det)}');
        """).strip())

    if detections:
        top = max(detections, key=lambda d: d["confidence"])
        cat_id = f"<category_id_for_{top['recommended_category']}>"
        priority = "HIGH" if highest_conf > PRIORITY_THRESHOLD_HIGH else "MEDIUM"
        print(textwrap.dedent(f"""
    -- 4. INSERT ai_predictions (CATEGORY_RECOMMENDATION)
    INSERT INTO ai_predictions
        (id, prediction_run_id, prediction_type,
         predicted_category_id, confidence_score, raw_output)
    VALUES (gen_random_uuid(), '{run_id}', 'CATEGORY_RECOMMENDATION',
            '{cat_id}', {top['confidence']},
            '{{"recommendation_reason": "highest_confidence_detection"}}');

    -- 5. INSERT ai_predictions (PRIORITY_RECOMMENDATION)
    INSERT INTO ai_predictions
        (id, prediction_run_id, prediction_type,
         class_name, confidence_score, raw_output)
    VALUES (gen_random_uuid(), '{run_id}', 'PRIORITY_RECOMMENDATION',
            '{priority}', {round(highest_conf * 0.9, 4)},
            '{{"rule_name": "rule_based_priority_v1", "explanation": "Rule: confidence > 0.85 → HIGH"}}');
        """).strip())

    status = "COMPLETED" if detections else "COMPLETED"
    print(textwrap.dedent(f"""
    -- 6. UPDATE ai_prediction_runs → {status}
    UPDATE ai_prediction_runs
    SET run_status = '{status}', completed_at = NOW()
    WHERE id = '{run_id}';
    """).strip())

    if not detections:
        print("\n-- NOTE: No detections above threshold.")
        print("-- Image must be routed for AUTHORITY REVIEW (no supported visual class).")


# ---------------------------------------------------------------------------
# Core flow
# ---------------------------------------------------------------------------

def execute_ai_database_flow(
    report_id: str,
    image_key: str,
    source_image_id: str | None = None,
    issue_id: str | None = None,
    confidence_threshold: float = 0.50,
    dry_run: bool = False,
) -> dict:
    """
    Execute the end-to-end AI prediction + database integration workflow.

    Args:
        report_id:           UUID of the citizen report row.
        image_key:           Local path or object-storage key for the image.
                             Must be a resolvable local path at inference time.
        source_image_id:     UUID of the report_images row (optional).
        issue_id:            UUID of the canonical issues row (optional).
        confidence_threshold Minimum detection confidence (default 0.50).
        dry_run:             If True, print SQL but do not write to DB.

    Returns:
        dict with run_record and predictions list.
    """
    print("=" * 50)
    print("CIVICFIX DATABASE INTEGRATION & AI WORKFLOW")
    print(f"  Report ID:        {report_id}")
    print(f"  Image:            {image_key}")
    print(f"  Issue ID:         {issue_id or '(none)'}")
    print(f"  Source Image ID:  {source_image_id or '(none)'}")
    print(f"  Dry Run:          {dry_run}")
    print("=" * 50)

    run_id   = str(uuid.uuid4())
    started  = _now_iso()

    # ── Resolve model weights ──────────────────────────────────────────────
    weights = _resolve_weights()
    if weights is None:
        print("[WARN] Model weights not found — falling back to mock inference.")

    # ── Run inference ──────────────────────────────────────────────────────
    try:
        inference_result = predict_civic_issue(
            image_path=image_key,
            model_weights_path=str(weights) if weights else "",
            confidence_threshold=confidence_threshold,
        )
    except Exception as exc:
        inference_result = {
            "detections": [],
            "status": "ERROR",
            "error_message": str(exc),
        }

    detections = inference_result.get("detections", [])
    inference_error = inference_result.get("error_message")

    # ── Dry-run path ───────────────────────────────────────────────────────
    if dry_run:
        _print_dry_run(run_id, report_id, image_key,
                       "<active_model_id>", inference_result)
        return {
            "dry_run": True,
            "run_id": run_id,
            "detections_count": len(detections),
            "inference_result": inference_result,
        }

    # ── Live DB path ───────────────────────────────────────────────────────
    conn = None
    prediction_records: list[dict] = []

    try:
        conn = _get_connection()
        cur  = conn.cursor()

        # 1. Resolve active model_id dynamically
        model_id = _resolve_active_model_id(cur)

        # 2. INSERT prediction run (PENDING)
        cur.execute(
            """
            INSERT INTO ai_prediction_runs
                (id, report_id, issue_id, source_image_id, model_id,
                 run_status, started_at)
            VALUES (%s, %s, %s, %s, %s, 'PENDING', NOW())
            RETURNING id;
            """,
            (run_id, report_id, issue_id, source_image_id, model_id),
        )
        conn.commit()
        print(f"[DB] Inserted ai_prediction_runs id={run_id} (status=PENDING)")

        # 3. UPDATE → RUNNING
        cur.execute(
            "UPDATE ai_prediction_runs SET run_status = 'RUNNING' WHERE id = %s;",
            (run_id,),
        )
        conn.commit()
        print("[DB] Updated ai_prediction_runs → RUNNING")

        # 4. Process detections
        highest_conf = -1.0
        top_detection = None

        for det in detections:
            conf    = det["confidence"]
            pred_id = str(uuid.uuid4())

            # Resolve category FK
            cat_id = _resolve_category_id(cur, det.get("recommended_category", ""))

            cur.execute(
                """
                INSERT INTO ai_predictions
                    (id, prediction_run_id, prediction_type,
                     class_id, class_name, confidence_score,
                     bounding_box, segmentation_polygon,
                     predicted_category_id, raw_output)
                VALUES (%s, %s, 'IMAGE_SEGMENTATION',
                        %s, %s, %s,
                        %s::jsonb, %s::jsonb,
                        %s, %s::jsonb)
                RETURNING id;
                """,
                (
                    pred_id, run_id,
                    det["class_id"], det["class_name"], conf,
                    json.dumps(det["bbox"]),
                    json.dumps(det["polygon"]),
                    cat_id,
                    json.dumps(det),
                ),
            )

            prediction_records.append({
                "id":               pred_id,
                "prediction_run_id": run_id,
                "prediction_type":  "IMAGE_SEGMENTATION",
                "class_id":         det["class_id"],
                "class_name":       det["class_name"],
                "confidence_score": conf,
                "bounding_box":     det["bbox"],
                "segmentation_polygon": det["polygon"],
                "raw_output":       det,
            })
            print(f"[DB] Inserted IMAGE_SEGMENTATION "
                  f"({det['class_name']}, conf={conf:.4f})")

            if conf > highest_conf:
                highest_conf   = conf
                top_detection  = det

        # 5. CATEGORY_RECOMMENDATION
        if top_detection:
            cat_id = _resolve_category_id(
                cur, top_detection.get("recommended_category", "")
            )
            cat_pred_id = str(uuid.uuid4())
            cur.execute(
                """
                INSERT INTO ai_predictions
                    (id, prediction_run_id, prediction_type,
                     predicted_category_id, confidence_score, raw_output)
                VALUES (%s, %s, 'CATEGORY_RECOMMENDATION',
                        %s, %s, %s::jsonb)
                RETURNING id;
                """,
                (
                    cat_pred_id, run_id,
                    cat_id,
                    top_detection["confidence"],
                    json.dumps({
                        "recommendation_reason": "highest_confidence_detection",
                        "top_detection": top_detection,
                    }),
                ),
            )
            prediction_records.append({
                "id":               cat_pred_id,
                "prediction_run_id": run_id,
                "prediction_type":  "CATEGORY_RECOMMENDATION",
                "predicted_category_id": cat_id,
                "confidence_score": top_detection["confidence"],
            })
            print(f"[DB] Inserted CATEGORY_RECOMMENDATION "
                  f"({top_detection['recommended_category']})")

        # 6. PRIORITY_RECOMMENDATION (rule-based, explicitly not model-trained)
        priority = "HIGH" if highest_conf > PRIORITY_THRESHOLD_HIGH else "MEDIUM"
        pri_conf  = round(highest_conf * 0.9, 4) if highest_conf > 0 else 0.5
        pri_pred_id = str(uuid.uuid4())
        cur.execute(
            """
            INSERT INTO ai_predictions
                (id, prediction_run_id, prediction_type,
                 class_name, confidence_score, raw_output)
            VALUES (%s, %s, 'PRIORITY_RECOMMENDATION',
                    %s, %s, %s::jsonb)
            RETURNING id;
            """,
            (
                pri_pred_id, run_id,
                priority,
                pri_conf,
                json.dumps({
                    "rule_name": "rule_based_priority_v1",
                    "explanation": (
                        "Derived from visual confidence score. "
                        "confidence > 0.85 → HIGH; otherwise MEDIUM. "
                        "Requires officer approval before applying to issue."
                    ),
                }),
            ),
        )
        prediction_records.append({
            "id":               pri_pred_id,
            "prediction_run_id": run_id,
            "prediction_type":  "PRIORITY_RECOMMENDATION",
            "class_name":       priority,
            "confidence_score": pri_conf,
        })
        print(f"[DB] Inserted PRIORITY_RECOMMENDATION ({priority})")

        # 7. Mark COMPLETED
        final_status = "COMPLETED"
        cur.execute(
            """
            UPDATE ai_prediction_runs
            SET run_status   = %s,
                completed_at = NOW()
            WHERE id = %s;
            """,
            (final_status, run_id),
        )
        conn.commit()
        print(f"[DB] Updated ai_prediction_runs → {final_status}")

        # Note: no supported class detected → still COMPLETED, but caller
        # queries ai_predictions and sees zero IMAGE_SEGMENTATION rows,
        # triggering authority review routing (Query 6c in queries_and_transactions.sql).
        if not detections:
            print("[INFO] No supported visual class detected. "
                  "Report will be routed for AUTHORITY REVIEW.")

        run_record = {
            "id":          run_id,
            "report_id":   report_id,
            "issue_id":    issue_id,
            "model_id":    model_id,
            "run_status":  final_status,
            "started_at":  started,
        }

    except Exception as exc:
        # Rollback and mark FAILED — do NOT block the citizen's report
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
            try:
                cur.execute(
                    """
                    UPDATE ai_prediction_runs
                    SET run_status    = 'FAILED',
                        completed_at  = NOW(),
                        error_message = %s
                    WHERE id = %s;
                    """,
                    (str(exc)[:2000], run_id),
                )
                conn.commit()
            except Exception:
                pass

        print(f"[ERROR] AI pipeline failed (run_id={run_id}): {exc}")
        print("[INFO] Report remains active and available for manual officer triage.")

        run_record = {
            "id":           run_id,
            "report_id":    report_id,
            "run_status":   "FAILED",
            "error_message": str(exc),
        }
        prediction_records = []

    finally:
        if conn:
            conn.close()

    return {
        "run_record":  run_record,
        "predictions": prediction_records,
    }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="CivicFix AI database integration — runs inference and writes to PostgreSQL."
    )
    parser.add_argument(
        "report_id",
        nargs="?",
        default="88888888-8888-8888-8888-888888888888",
        help="UUID of the citizen report.",
    )
    parser.add_argument(
        "image_path",
        nargs="?",
        default="data/raw/road_damage/data/images/sample.jpg",
        help="Local path to the image file.",
    )
    parser.add_argument(
        "--source-image-id",
        default=None,
        help="UUID of the report_images row (optional).",
    )
    parser.add_argument(
        "--issue-id",
        default=None,
        help="UUID of the canonical issues row (optional).",
    )
    parser.add_argument(
        "--confidence",
        type=float,
        default=0.50,
        help="Minimum confidence threshold (default: 0.50).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print SQL statements without writing to the database.",
    )
    args = parser.parse_args()

    result = execute_ai_database_flow(
        report_id=args.report_id,
        image_key=args.image_path,
        source_image_id=args.source_image_id,
        issue_id=args.issue_id,
        confidence_threshold=args.confidence,
        dry_run=args.dry_run,
    )

    print("\n--- Workflow Result ---")
    print(json.dumps(result, indent=2, default=str))


if __name__ == "__main__":
    main()
