#!/usr/bin/env python3
"""
CivicFix AI Pipeline - MODEL_CARD.md Generator
-----------------------------------------------
Reads model_metrics.json and class_mapping.json produced by evaluate_model.py
and generates a human-readable MODEL_CARD.md following the project spec.

Outputs:
  MODEL_CARD.md

Usage:
  python generate_model_card.py                               # auto-detect paths
  python generate_model_card.py --metrics model_metrics.json
  python generate_model_card.py --metrics m.json --output ./
"""

import os
import sys
import json
import datetime
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# Default path resolution
# ---------------------------------------------------------------------------

DEFAULT_METRICS_CANDIDATES = [
    Path("/kaggle/working/civicfix_runs/civicfix_road_damage_seg_v1/weights/model_metrics.json"),
    Path("data/processed/civicfix_runs/civicfix_road_damage_seg_v1/weights/model_metrics.json"),
    Path("model_metrics.json"),
]
DEFAULT_CLASS_MAP_CANDIDATES = [
    Path("/kaggle/working/civicfix_runs/civicfix_road_damage_seg_v1/weights/class_mapping.json"),
    Path("data/processed/civicfix_runs/civicfix_road_damage_seg_v1/weights/class_mapping.json"),
    Path("class_mapping.json"),
]


def resolve_first(candidates: list[Path]) -> Path | None:
    for p in candidates:
        if p.exists():
            return p
    return None


# ---------------------------------------------------------------------------
# Template builder
# ---------------------------------------------------------------------------

UNSUPPORTED_CATEGORIES = [
    "Broken streetlights",
    "Water leakage / burst pipes",
    "Blocked drains",
    "Fallen trees",
    "Overflowing garbage bins",
    "Illegal dumping",
    "General public-infrastructure damage (not listed above)",
]


def _fmt_metric(val, decimals: int = 4) -> str:
    """Format a metric float or return 'N/A'."""
    if val is None:
        return "N/A"
    try:
        return f"{float(val):.{decimals}f}"
    except (TypeError, ValueError):
        return "N/A"


def generate_model_card(
    metrics: dict,
    class_mapping: dict,
    output_path: Path,
):
    """Build and write MODEL_CARD.md from metrics and class_mapping dicts."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")

    model_name    = metrics.get("model_name",    "civicfix_road_damage_segmentation")
    model_version = metrics.get("model_version", "v1")
    task_type     = metrics.get("task_type",     "image_segmentation")
    framework     = metrics.get("framework",     "Ultralytics YOLOv8n-seg")
    device        = metrics.get("training_device", "Unknown")
    eval_split    = metrics.get("evaluation_split", "test")
    disclaimer    = metrics.get("disclaimer", "")

    agg       = metrics.get("metrics", {})
    per_class = metrics.get("per_class_metrics", {})
    plots     = metrics.get("plot_artifacts", {})
    train_p   = metrics.get("training_parameters", {})

    supported = sorted(class_mapping.values())

    # ── Build markdown ───────────────────────────────────────────────────────
    lines: list[str] = []

    def h1(t):  lines.append(f"# {t}\n")
    def h2(t):  lines.append(f"## {t}\n")
    def h3(t):  lines.append(f"### {t}\n")
    def p(*args): lines.append(" ".join(str(a) for a in args) + "\n")
    def blank():  lines.append("")
    def rule():   lines.append("---\n")

    h1(f"CivicFix — AI Model Card: `{model_name}`")
    p(f"> Version **{model_version}** · Generated {now}")
    blank()

    # ── ⚠️ Critical Disclaimer ────────────────────────────────────────────────
    h2("⚠️  Critical Disclaimer")
    lines.append("> [!CAUTION]\n")
    lines.append(
        "> This model is validated for **educational and hackathon demonstration "
        "purposes only**. It is NOT claimed to be production-ready, perfect, or "
        "100% accurate. Metrics are computed on the held-out test split only and "
        "do not guarantee real-world performance.\n"
    )
    blank()
    lines.append("> [!WARNING]\n")
    lines.append(
        "> The model can ONLY recognise the three classes listed below. "
        "**All other civic-issue categories must be sent for authority review "
        "without fabricated AI predictions.** Generating AI predictions for "
        "unsupported categories is prohibited.\n"
    )
    blank()
    rule()

    # ── Model Overview ────────────────────────────────────────────────────────
    h2("1. Model Overview")
    lines.append(
        "| Property | Value |\n"
        "|---|---|\n"
        f"| **Model Name** | `{model_name}` |\n"
        f"| **Version** | `{model_version}` |\n"
        f"| **Task Type** | `{task_type}` |\n"
        f"| **Architecture** | `{framework}` |\n"
        f"| **Training Device** | `{device}` |\n"
        f"| **Evaluation Split** | `{eval_split}` |\n"
        f"| **Card Generated** | `{now}` |\n"
    )
    blank()
    rule()

    # ── Supported Classes ─────────────────────────────────────────────────────
    h2("2. Supported Visual Classes")
    p("This model can detect and segment **only** the following road-damage classes:")
    blank()
    lines.append("| Class ID | Class Name | Description |\n")
    lines.append("|---|---|---|\n")
    class_descriptions = {
        "pothole":    "Potholes and surface depressions in road pavement.",
        "road_crack": "Cracks, fractures, and fissures on road surfaces.",
        "manhole":    "Manhole covers visible on road surfaces.",
    }
    for cls_id, cls_name in sorted(class_mapping.items(), key=lambda x: int(x[0])):
        desc = class_descriptions.get(cls_name, "—")
        lines.append(f"| `{cls_id}` | `{cls_name}` | {desc} |\n")
    blank()
    rule()

    # ── Unsupported Categories ────────────────────────────────────────────────
    h2("3. Unsupported Categories — Authority Review Required")
    p(
        "The following civic-issue categories are **not** recognised by this model. "
        "Any citizen report containing imagery from these categories must be "
        "routed to authority review **without** a fabricated AI prediction:"
    )
    blank()
    for cat in UNSUPPORTED_CATEGORIES:
        lines.append(f"- {cat}\n")
    blank()
    lines.append("> [!IMPORTANT]\n")
    lines.append(
        "> When the inference engine returns `NO_SUPPORTED_VISUAL_CLASS` or the "
        "`ai_prediction_runs` record has zero `IMAGE_SEGMENTATION` rows, the report "
        "MUST be flagged for human review. Never populate `issues.category_id`, "
        "`severity`, or `priority` from AI for unsupported categories.\n"
    )
    blank()
    rule()

    # ── Training Dataset ──────────────────────────────────────────────────────
    h2("4. Training Dataset")
    lines.append(
        "| Property | Value |\n"
        "|---|---|\n"
        "| **Dataset Name** | Road Damage Dataset: Potholes, Cracks and Manholes |\n"
        "| **Source** | [Kaggle — lorenzoarcioni](https://www.kaggle.com/datasets/lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes) |\n"
        "| **Images** | 2,009 labelled images |\n"
        "| **Annotation Format** | YOLO polygon / instance segmentation (class_id x1 y1 … xn yn) |\n"
        "| **License Status** | `EDUCATIONAL_ONLY` (see `dataset_registry` table) |\n"
        "| **Attribution** | Dataset by Lorenzo Arcioni on Kaggle. Original imagery rights apply. |\n"
        "| **Split (seed=42)** | 70 % train / 15 % val / 15 % test |\n"
    )
    blank()
    lines.append("> [!CAUTION]\n")
    lines.append(
        "> This dataset is approved for **educational and hackathon demonstration only**. "
        "Commercial use requires explicit verification of the original imagery license. "
        "Do NOT change `dataset_registry.license_status` to `APPROVED` without legal sign-off.\n"
    )
    blank()
    rule()

    # ── Training Parameters ───────────────────────────────────────────────────
    h2("5. Training Configuration")
    if train_p:
        lines.append("| Parameter | Value |\n|---|---|\n")
        interesting = [
            "epochs", "batch", "imgsz", "patience",
            "seed", "optimizer", "lr0", "momentum", "weight_decay",
        ]
        for k in interesting:
            if k in train_p:
                lines.append(f"| `{k}` | `{train_p[k]}` |\n")
        # Fallback: show any remaining numeric params
        for k, v in train_p.items():
            if k not in interesting and isinstance(v, (int, float, str)):
                lines.append(f"| `{k}` | `{v}` |\n")
    else:
        p("Training parameters not available. See `args.yaml` in the training run directory.")
    blank()
    rule()

    # ── Evaluation Metrics ────────────────────────────────────────────────────
    h2("6. Evaluation Metrics (Held-Out Test Split)")
    lines.append("> [!NOTE]\n")
    lines.append(
        "> All metrics below are computed on the held-out **test** split "
        f"({_fmt_metric(0.15*100, 1)}% of the dataset). They represent performance "
        "on data the model has never seen during training or validation.\n"
    )
    blank()

    h3("6.1 Aggregate Segmentation Metrics")
    lines.append(
        "| Metric | Value |\n"
        "|---|---|\n"
        f"| Precision | `{_fmt_metric(agg.get('precision'))}` |\n"
        f"| Recall | `{_fmt_metric(agg.get('recall'))}` |\n"
        f"| mAP@50 | `{_fmt_metric(agg.get('mAP50'))}` |\n"
        f"| mAP@50-95 | `{_fmt_metric(agg.get('mAP50_95'))}` |\n"
    )
    blank()

    h3("6.2 Per-Class Metrics")
    lines.append("| Class | Precision | Recall | mAP@50-95 |\n|---|---|---|---|\n")
    for cls_name in supported:
        cm = per_class.get(cls_name, {})
        lines.append(
            f"| `{cls_name}` "
            f"| `{_fmt_metric(cm.get('precision'))}` "
            f"| `{_fmt_metric(cm.get('recall'))}` "
            f"| `{_fmt_metric(cm.get('mAP50_95'))}` |\n"
        )
    blank()

    h3("6.3 Evaluation Plot Artifacts")
    if any(plots.values()):
        for plot_name, plot_path in plots.items():
            if plot_path:
                lines.append(f"- **{plot_name.replace('_', ' ').title()}**: `{plot_path}`\n")
    else:
        p("Plot artifacts generated by Ultralytics `model.val()` — "
          "see the training run output directory.")
    blank()
    rule()

    # ── Limitations ────────────────────────────────────────────────────────────
    h2("7. Limitations")
    lines.append(
        "- **Training data scope**: Trained only on road-damage imagery. "
        "Performance on urban environments significantly different from the training set is unknown.\n"
    )
    lines.append(
        "- **Low-light / night imagery**: No night-time images in the training dataset. "
        "Confidence scores will be lower for night or rain conditions.\n"
    )
    lines.append(
        "- **Partial occlusion**: Heavily occluded potholes or manholes "
        "may be missed or have lower confidence.\n"
    )
    lines.append(
        "- **Class imbalance**: If the training dataset has significantly more pothole "
        "annotations than road_crack or manhole, per-class recall will vary. "
        "Review `split_class_counts.json` in `reports/`.\n"
    )
    lines.append(
        "- **Human oversight required**: All AI predictions are recommendations only. "
        "Category, severity, and priority values on canonical `issues` rows must be "
        "confirmed by a municipal authority before being acted upon.\n"
    )
    blank()
    rule()

    # ── Usage Instructions ────────────────────────────────────────────────────
    h2("8. Usage Instructions")
    lines.append("```bash\n")
    lines.append("# Single image inference\n")
    lines.append("python scripts/ai_pipeline/inference.py <image_path>\n")
    lines.append("\n")
    lines.append("# DB-integrated prediction (requires DATABASE_URL env var)\n")
    lines.append("export DATABASE_URL=postgresql://user:pass@host:5432/civicfix\n")
    lines.append("python scripts/ai_pipeline/db_integration.py <report_uuid> <image_path>\n")
    lines.append("\n")
    lines.append("# Dry-run (prints SQL without writing to DB)\n")
    lines.append("python scripts/ai_pipeline/db_integration.py <report_uuid> <image_path> --dry-run\n")
    lines.append("```\n")
    blank()
    rule()

    # ── Changelog ─────────────────────────────────────────────────────────────
    h2("9. Version History")
    lines.append(
        "| Version | Date | Notes |\n"
        "|---|---|---|\n"
        f"| `{model_version}` | {now} | Initial training on road-damage dataset (educational use). |\n"
    )
    blank()

    # ── Write file ────────────────────────────────────────────────────────────
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"[OK] MODEL_CARD.md → {output_path.resolve()}")
    return output_path


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate MODEL_CARD.md from model_metrics.json."
    )
    parser.add_argument(
        "--metrics", "-m",
        help="Path to model_metrics.json (auto-detected if omitted).",
    )
    parser.add_argument(
        "--class-map", "-c",
        help="Path to class_mapping.json (auto-detected if omitted).",
    )
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="Output directory for MODEL_CARD.md (defaults to metrics file dir).",
    )
    args = parser.parse_args()

    metrics_path = (
        Path(args.metrics) if args.metrics
        else resolve_first(DEFAULT_METRICS_CANDIDATES)
    )
    if metrics_path is None or not metrics_path.exists():
        print("[FAIL] model_metrics.json not found. Run evaluate_model.py first, "
              "or use --metrics.")
        sys.exit(1)

    class_map_path = (
        Path(args.class_map) if args.class_map
        else resolve_first(DEFAULT_CLASS_MAP_CANDIDATES)
    )

    with open(metrics_path, encoding="utf-8") as f:
        metrics = json.load(f)

    if class_map_path and class_map_path.exists():
        with open(class_map_path, encoding="utf-8") as f:
            class_mapping = json.load(f)
    else:
        print("[WARN] class_mapping.json not found — using default mapping.")
        class_mapping = {"0": "pothole", "1": "road_crack", "2": "manhole"}

    out_dir = (
        Path(args.output) if args.output
        else metrics_path.parent
    )
    output_path = out_dir / "MODEL_CARD.md"

    generate_model_card(metrics, class_mapping, output_path)


if __name__ == "__main__":
    main()
