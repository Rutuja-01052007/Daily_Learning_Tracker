#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CivicFix AI Pipeline - Master Orchestrator
-------------------------------------------
Runs all pipeline stages in order with a single CLI entry point.

Stages (run in this order when --stage all is passed):
  1. validate   -> validate_dataset.py
  2. split      -> prepare_dataset_splits.py
  3. train      -> train_segmentation.py
  4. evaluate   -> evaluate_model.py
  5. model-card -> generate_model_card.py

Individual stages can be run independently:
  python run_pipeline.py --stage validate
  python run_pipeline.py --stage train
  python run_pipeline.py --stage infer --image path/to/image.jpg

Usage:
  python run_pipeline.py --stage all
  python run_pipeline.py --stage validate --dataset /path/to/data
  python run_pipeline.py --stage split   --source /path --output /working
  python run_pipeline.py --stage train   --yaml /working/data.yaml
  python run_pipeline.py --stage evaluate --weights best.pt --yaml data.yaml
  python run_pipeline.py --stage model-card --metrics model_metrics.json
  python run_pipeline.py --stage infer  --image photo.jpg [--weights best.pt]
  python run_pipeline.py --stage infer  --image photo.jpg --dry-run

Exit codes:
  0  All stages passed.
  1  One or more stages failed (details printed to stderr).
"""

import sys, io as _io
# Force UTF-8 on Windows terminals (avoids cp1252 UnicodeEncodeError)
if sys.platform == 'win32':
    sys.stdout = _io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
    sys.stderr = _io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

import os
import json
import argparse
import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Add ai_pipeline dir to path so we can import siblings directly
# ---------------------------------------------------------------------------
PIPELINE_DIR = Path(__file__).parent
sys.path.insert(0, str(PIPELINE_DIR))

# ---------------------------------------------------------------------------
# Colour helpers (gracefully degrade on Windows without VT100)
# ---------------------------------------------------------------------------
_USE_COLOR = sys.platform != "win32" or os.environ.get("FORCE_COLOR")

def _green(s):  return f"\033[92m{s}\033[0m" if _USE_COLOR else s
def _red(s):    return f"\033[91m{s}\033[0m" if _USE_COLOR else s
def _yellow(s): return f"\033[93m{s}\033[0m" if _USE_COLOR else s
def _bold(s):   return f"\033[1m{s}\033[0m"  if _USE_COLOR else s


# ---------------------------------------------------------------------------
# Stage 1 — Validate dataset
# ---------------------------------------------------------------------------

def stage_validate(args) -> bool:
    print(_bold("\n[STAGE 1/5] Dataset Validation"))
    from validate_dataset import validate_dataset, find_dataset_dir  # type: ignore

    ds_dir = Path(args.dataset) if args.dataset else find_dataset_dir()
    if ds_dir is None:
        print(_red("[FAIL] Dataset directory not found. Use --dataset."))
        return False

    report_path = (
        Path(args.report) if args.report
        else _resolve_working_dir(args) / "reports" / "data_quality_report.json"
    )

    report = validate_dataset(ds_dir, output_report_path=report_path)
    ok = report["valid_image_label_pairs"] > 0
    if ok:
        print(_green(f"[OK] Validation passed. {report['valid_image_label_pairs']} valid pairs."))
    else:
        print(_red("[FAIL] No valid pairs found after validation."))
    return ok


# ---------------------------------------------------------------------------
# Stage 2 — Prepare splits
# ---------------------------------------------------------------------------

def stage_split(args) -> bool:
    print(_bold("\n[STAGE 2/5] Dataset Split & Manifest Generation"))
    from prepare_dataset_splits import prepare_splits, find_source_dir  # type: ignore
    from validate_dataset import find_dataset_dir  # type: ignore

    src = Path(args.source) if args.source else find_source_dir() or find_dataset_dir()
    if src is None:
        print(_red("[FAIL] Source dataset directory not found. Use --source."))
        return False

    out = _resolve_working_dir(args)
    seed = int(args.seed) if args.seed else 42

    try:
        prepare_splits(src, out, seed=seed)
        print(_green(f"[OK] Split complete → {out}"))
        return True
    except SystemExit:
        return False
    except Exception as exc:
        print(_red(f"[FAIL] Split failed: {exc}"))
        return False


# ---------------------------------------------------------------------------
# Stage 3 — Train
# ---------------------------------------------------------------------------

def stage_train(args) -> bool:
    print(_bold("\n[STAGE 3/5] YOLO Segmentation Training"))
    from train_segmentation import train_yolo_segmentation  # type: ignore

    working_dir = _resolve_working_dir(args)
    yaml_path   = Path(args.yaml) if args.yaml else working_dir / "data.yaml"

    if not yaml_path.exists():
        print(_red(f"[FAIL] data.yaml not found: {yaml_path}. Run 'split' stage first."))
        return False

    project_dir = str(args.project_dir) if args.project_dir else str(working_dir.parent / "civicfix_runs")

    try:
        run_dir = train_yolo_segmentation(str(yaml_path), project_dir=project_dir)
        print(_green(f"[OK] Training complete → {run_dir}"))
        return True
    except SystemExit:
        return False
    except Exception as exc:
        print(_red(f"[FAIL] Training failed: {exc}"))
        return False


# ---------------------------------------------------------------------------
# Stage 4 — Evaluate
# ---------------------------------------------------------------------------

def stage_evaluate(args) -> bool:
    print(_bold("\n[STAGE 4/5] Model Evaluation on Held-Out Test Split"))
    from evaluate_model import evaluate_test_split, resolve_first, DEFAULT_WEIGHTS, DEFAULT_YAML  # type: ignore

    weights = Path(args.weights) if args.weights else resolve_first(DEFAULT_WEIGHTS)
    yaml_p  = Path(args.yaml)    if args.yaml    else resolve_first(DEFAULT_YAML)
    out_dir = Path(args.output)  if args.output  else None

    if weights is None or not weights.exists():
        print(_red("[FAIL] Weights file not found. Run 'train' stage first or use --weights."))
        return False
    if yaml_p is None or not yaml_p.exists():
        print(_red("[FAIL] data.yaml not found. Use --yaml."))
        return False

    try:
        evaluate_test_split(weights, yaml_p, output_dir=out_dir)
        print(_green("[OK] Evaluation complete."))
        return True
    except SystemExit:
        return False
    except Exception as exc:
        print(_red(f"[FAIL] Evaluation failed: {exc}"))
        return False


# ---------------------------------------------------------------------------
# Stage 5 — Model Card
# ---------------------------------------------------------------------------

def stage_model_card(args) -> bool:
    print(_bold("\n[STAGE 5/5] MODEL_CARD.md Generation"))
    from generate_model_card import (  # type: ignore
        generate_model_card,
        resolve_first,
        DEFAULT_METRICS_CANDIDATES,
        DEFAULT_CLASS_MAP_CANDIDATES,
    )

    metrics_path = (
        Path(args.metrics) if args.metrics
        else resolve_first(DEFAULT_METRICS_CANDIDATES)
    )
    if metrics_path is None or not metrics_path.exists():
        print(_red("[FAIL] model_metrics.json not found. Run 'evaluate' stage first."))
        return False

    class_map_path = resolve_first(DEFAULT_CLASS_MAP_CANDIDATES)

    with open(metrics_path, encoding="utf-8") as f:
        metrics_data = json.load(f)

    if class_map_path and class_map_path.exists():
        with open(class_map_path, encoding="utf-8") as f:
            class_mapping = json.load(f)
    else:
        class_mapping = {"0": "pothole", "1": "road_crack", "2": "manhole"}

    out_dir = Path(args.output) if args.output else metrics_path.parent
    output_path = out_dir / "MODEL_CARD.md"

    try:
        generate_model_card(metrics_data, class_mapping, output_path)
        print(_green(f"[OK] MODEL_CARD.md → {output_path}"))
        return True
    except Exception as exc:
        print(_red(f"[FAIL] Model card generation failed: {exc}"))
        return False


# ---------------------------------------------------------------------------
# Stage: infer (ad-hoc single image inference)
# ---------------------------------------------------------------------------

def stage_infer(args) -> bool:
    print(_bold("\nAd-Hoc Inference"))
    if not args.image:
        print(_red("[FAIL] --image is required for the 'infer' stage."))
        return False

    image_path = args.image

    if args.dry_run or not args.report_id:
        # Standalone inference — no DB write
        from inference import predict_civic_issue  # type: ignore
        weights_path = args.weights or ""
        result = predict_civic_issue(image_path, weights_path)
        print(json.dumps(result, indent=2))
        return True

    # With report_id → full DB flow
    from db_integration import execute_ai_database_flow  # type: ignore
    result = execute_ai_database_flow(
        report_id=args.report_id,
        image_key=image_path,
        source_image_id=getattr(args, "source_image_id", None),
        issue_id=getattr(args, "issue_id", None),
        confidence_threshold=float(getattr(args, "confidence", 0.50)),
        dry_run=bool(getattr(args, "dry_run", False)),
    )
    print(json.dumps(result, indent=2, default=str))
    return True


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _resolve_working_dir(args) -> Path:
    if args.output:
        return Path(args.output)
    if Path("/kaggle/working").exists():
        return Path("/kaggle/working/civicfix_road_damage")
    return Path("data/processed/civicfix_road_damage")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run_pipeline.py",
        description="CivicFix AI pipeline orchestrator.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--stage", "-s",
        required=True,
        choices=["all", "validate", "split", "train", "evaluate", "model-card", "infer"],
        help="Pipeline stage to run.",
    )
    # Common
    parser.add_argument("--dataset",     help="Dataset root directory (validate stage).")
    parser.add_argument("--source",      help="Source dataset directory (split stage).")
    parser.add_argument("--output",      help="Output / working directory.")
    parser.add_argument("--yaml",        help="Path to data.yaml.")
    parser.add_argument("--weights",     help="Path to best.pt.")
    parser.add_argument("--metrics",     help="Path to model_metrics.json.")
    parser.add_argument("--report",      help="Output path for data_quality_report.json.")
    parser.add_argument("--project-dir", dest="project_dir",
                        help="YOLO training project directory.")
    parser.add_argument("--seed",        default="42",
                        help="Random seed for dataset split (default: 42).")
    # Inference-specific
    parser.add_argument("--image",       help="Image path for inference.")
    parser.add_argument("--report-id",   dest="report_id",
                        help="Report UUID for DB-integrated inference.")
    parser.add_argument("--source-image-id", dest="source_image_id",
                        help="report_images UUID for DB-integrated inference.")
    parser.add_argument("--issue-id",    dest="issue_id",
                        help="Issues UUID for DB-integrated inference.")
    parser.add_argument("--confidence",  default="0.50",
                        help="Minimum confidence threshold (default: 0.50).")
    parser.add_argument("--dry-run",     action="store_true",
                        help="Print SQL without writing to DB (infer stage).")
    return parser


def main():
    parser = build_parser()
    args   = parser.parse_args()

    started = datetime.datetime.now()
    print(_bold("=" * 60))
    print(_bold(f"CIVICFIX AI PIPELINE — stage: {args.stage}"))
    print(_bold(f"Started: {started.strftime('%Y-%m-%d %H:%M:%S')}"))
    print(_bold("=" * 60))

    stage_fn_map = {
        "validate":   stage_validate,
        "split":      stage_split,
        "train":      stage_train,
        "evaluate":   stage_evaluate,
        "model-card": stage_model_card,
        "infer":      stage_infer,
    }

    if args.stage == "all":
        stages_to_run = ["validate", "split", "train", "evaluate", "model-card"]
    else:
        stages_to_run = [args.stage]

    results: dict[str, bool] = {}
    for stage_name in stages_to_run:
        fn = stage_fn_map[stage_name]
        ok = fn(args)
        results[stage_name] = ok
        if not ok and args.stage == "all":
            print(_red(f"\n[ABORT] Stage '{stage_name}' failed. Stopping pipeline."))
            break

    # ── Summary ──────────────────────────────────────────────────────────────
    elapsed = (datetime.datetime.now() - started).total_seconds()
    print(_bold("\n" + "=" * 60))
    print(_bold(f"PIPELINE SUMMARY  ({elapsed:.1f}s)"))
    print(_bold("=" * 60))
    all_ok = True
    for stage_name, ok in results.items():
        icon = _green("PASS") if ok else _red("FAIL")
        print(f"  [{icon}]  {stage_name}")
        if not ok:
            all_ok = False

    if all_ok:
        print(_green("\nAll stages completed successfully."))
    else:
        print(_red("\nOne or more stages failed. Review output above."))
        sys.exit(1)


if __name__ == "__main__":
    main()
