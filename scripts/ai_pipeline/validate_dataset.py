#!/usr/bin/env python3
"""
CivicFix AI Pipeline - Dataset Validation Script
-------------------------------------------------
Validates images and polygon segmentation labels for the Road Damage Dataset:
Potholes, Cracks and Manholes.

Validation rules:
  1. Supported image extensions: .jpg, .jpeg, .png, .webp.
  2. Every image must have a matching .txt label file.
  3. Every non-empty label file must have at least one valid annotation row.
  4. Every segmentation label row:
       - First value:  class ID (0=pothole, 1=road_crack, 2=manhole).
       - Remaining:    even count of floats (x, y pairs).
       - Minimum 6 coordinates (3 polygon points).
       - All coordinates in range [0.0, 1.0].
  5. Empty label files (no non-empty lines) are recorded — they are valid for
     background-only images but must be counted separately.
  6. Corrupt / unreadable images are detected via PIL.Image.verify().
  7. A data_quality_report.json is written to the output path.

Usage:
  python validate_dataset.py                           # auto-detects dataset dir
  python validate_dataset.py --dataset /path/to/data  # explicit path
  python validate_dataset.py --report /path/report.json
"""

import os
import sys
import json
import argparse
from pathlib import Path

KAGGLE_INPUT_DIR = Path("/kaggle/input/datasets/lorenzoarcioni"
                        "/road-damage-dataset-potholes-cracks-and-manholes/data")
LOCAL_INPUT_DIR  = Path("data/raw/road_damage/data")

VALID_CLASS_IDS      = {0, 1, 2}
CLASS_NAME_MAP       = {0: "pothole", 1: "road_crack", 2: "manhole"}
SUPPORTED_IMG_EXTS   = {".jpg", ".jpeg", ".png", ".webp"}


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------

def find_dataset_dir():
    """Return the first existing candidate dataset directory."""
    candidates = [
        KAGGLE_INPUT_DIR,
        LOCAL_INPUT_DIR,
        Path("data/raw/road_damage"),
    ]
    for p in candidates:
        if p.exists():
            return p
    print("[FAIL] Dataset directory not found. Checked:\n"
          + "\n".join(f"  {c}" for c in candidates))
    return None


# ---------------------------------------------------------------------------
# Image corruption check
# ---------------------------------------------------------------------------

def is_image_corrupt(img_path: Path) -> bool:
    """
    Return True when the image file is unreadable or fails PIL verification.
    PIL.Image.verify() detects truncation and some corruption; we also try
    a full load to catch more subtle decode failures.
    """
    try:
        from PIL import Image  # type: ignore
        with Image.open(img_path) as img:
            img.verify()           # fast structural check
        # verify() closes the file-handle; re-open for full decode test
        with Image.open(img_path) as img:
            img.load()             # full pixel decode — catches truncated JPEG
        return False
    except ImportError:
        # Pillow not installed: skip corruption check, log a warning once
        return False               # assume OK — warn at report level
    except Exception:
        return True


# ---------------------------------------------------------------------------
# Label validation
# ---------------------------------------------------------------------------

def validate_label_file(label_file: Path):
    """
    Validate a single .txt label file.

    Returns:
        dict with keys:
          is_empty           (bool)   – file exists but has zero non-empty lines
          valid_rows         (int)    – number of annotation rows that passed
          error_list         (list)   – error dicts for failed rows
          class_counts       (dict)   – {class_id: count} for valid rows
    """
    result = {
        "is_empty":     False,
        "valid_rows":   0,
        "error_list":   [],
        "class_counts": {0: 0, 1: 0, 2: 0},
    }

    try:
        with open(label_file, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        result["error_list"].append({
            "type":       "LABEL_READ_ERROR",
            "label_file": str(label_file),
            "message":    str(e),
        })
        return result

    non_empty_lines = [l.strip() for l in lines if l.strip()]

    if not non_empty_lines:
        result["is_empty"] = True
        return result

    for line_no, line in enumerate(non_empty_lines, 1):
        parts = line.split()

        # --- class_id ---
        try:
            class_id = int(parts[0])
        except (ValueError, IndexError):
            result["error_list"].append({
                "type":       "INVALID_CLASS_ID_FORMAT",
                "label_file": str(label_file),
                "line":       line_no,
                "message":    f"Class ID '{parts[0] if parts else ''}' is not an integer.",
            })
            continue

        if class_id not in VALID_CLASS_IDS:
            result["error_list"].append({
                "type":       "UNSUPPORTED_CLASS_ID",
                "label_file": str(label_file),
                "line":       line_no,
                "message":    f"Class ID {class_id} not in allowed set {{0, 1, 2}}.",
            })
            continue

        # --- coordinate pairs ---
        coords = parts[1:]

        if len(coords) < 6:
            result["error_list"].append({
                "type":       "INSUFFICIENT_POLYGON_COORDINATES",
                "label_file": str(label_file),
                "line":       line_no,
                "message":    (f"Polygon has only {len(coords)} coordinate values. "
                               "Minimum required is 6 (3 points × 2 floats)."),
            })
            continue

        if len(coords) % 2 != 0:
            result["error_list"].append({
                "type":       "ODD_COORDINATE_COUNT",
                "label_file": str(label_file),
                "line":       line_no,
                "message":    (f"Coordinate count {len(coords)} is odd — "
                               "must be even (x, y pairs)."),
            })
            continue

        # --- bounds check [0.0, 1.0] ---
        out_of_bounds = False
        for val_str in coords:
            try:
                val = float(val_str)
                if val < 0.0 or val > 1.0:
                    out_of_bounds = True
                    break
            except ValueError:
                out_of_bounds = True
                break

        if out_of_bounds:
            result["error_list"].append({
                "type":       "COORDINATES_OUT_OF_BOUNDS",
                "label_file": str(label_file),
                "line":       line_no,
                "message":    "All coordinate values must be normalized floats in [0.0, 1.0].",
            })
            continue

        # Row is valid
        result["valid_rows"] += 1
        if class_id in result["class_counts"]:
            result["class_counts"][class_id] += 1

    return result


# ---------------------------------------------------------------------------
# Main validation entry point
# ---------------------------------------------------------------------------

def validate_dataset(dataset_dir, output_report_path=None):
    """
    Validate all image-label pairs in dataset_dir.

    Returns the full quality report dict.
    """
    dataset_dir = Path(dataset_dir)
    print("=" * 50)
    print("CIVICFIX DATASET SEGMENTATION VALIDATOR")
    print(f"Dataset Path: {dataset_dir}")
    print("=" * 50)

    images_dir = dataset_dir / "images" if (dataset_dir / "images").exists() else dataset_dir
    labels_dir = dataset_dir / "labels" if (dataset_dir / "labels").exists() else dataset_dir

    if not images_dir.exists():
        print(f"[FAIL] Images directory not found: {images_dir}")
        sys.exit(1)
    if not labels_dir.exists():
        print(f"[FAIL] Labels directory not found: {labels_dir}")
        sys.exit(1)

    # ── Collect images ──────────────────────────────────────────────────────
    image_files = []
    for root, _, files in os.walk(images_dir):
        for f in files:
            if Path(f).suffix.lower() in SUPPORTED_IMG_EXTS:
                image_files.append(Path(root) / f)

    print(f"Total candidate images found: {len(image_files)}")

    # ── Check Pillow availability ────────────────────────────────────────────
    try:
        import PIL  # noqa: F401
        pillow_available = True
    except ImportError:
        pillow_available = False
        print("[WARN] Pillow (PIL) not installed — corrupt image detection disabled. "
              "Install via: pip install Pillow")

    # ── Per-image validation ─────────────────────────────────────────────────
    errors           = []
    valid_pairs      = []
    corrupt_images   = []
    missing_labels   = []
    empty_labels     = []
    total_class_counts = {0: 0, 1: 0, 2: 0}
    invalid_label_rows = 0

    for img_path in image_files:
        stem = img_path.stem

        # Find label file (direct path or nested search)
        label_file = labels_dir / f"{stem}.txt"
        if not label_file.exists():
            matches = list(labels_dir.glob(f"**/{stem}.txt"))
            label_file = matches[0] if matches else None

        if label_file is None:
            missing_labels.append(str(img_path))
            errors.append({
                "type":    "MISSING_LABEL_FILE",
                "image":   str(img_path),
                "message": f"Matching label file '{stem}.txt' not found.",
            })
            continue

        # Corrupt image check
        if pillow_available and is_image_corrupt(img_path):
            corrupt_images.append(str(img_path))
            errors.append({
                "type":    "CORRUPT_IMAGE",
                "image":   str(img_path),
                "message": "Image file failed PIL decode / verify check.",
            })
            continue

        # Label validation
        lv = validate_label_file(label_file)

        if lv["is_empty"]:
            empty_labels.append(str(label_file))
            # Empty label = no annotations — treat as a valid "background" pair
            # but record it separately so training can decide how to handle it.
            valid_pairs.append({"image": str(img_path), "label": str(label_file)})
            continue

        if lv["error_list"]:
            invalid_label_rows += len(lv["error_list"])
            errors.extend(lv["error_list"])
            # Only exclude the pair if it has ZERO valid rows
            if lv["valid_rows"] == 0:
                continue

        # At least one valid annotation row — count it
        valid_pairs.append({"image": str(img_path), "label": str(label_file)})
        for cls_id, cnt in lv["class_counts"].items():
            total_class_counts[cls_id] += cnt

    # ── Build report ─────────────────────────────────────────────────────────
    report = {
        "dataset_directory":        str(dataset_dir),
        "pillow_available":         pillow_available,
        "total_images_found":       len(image_files),
        "valid_image_label_pairs":  len(valid_pairs),
        "missing_label_files":      len(missing_labels),
        "corrupt_images":           len(corrupt_images),
        "empty_label_files":        len(empty_labels),
        "invalid_label_rows":       invalid_label_rows,
        "total_errors":             len(errors),
        "class_counts": {
            "0_pothole":   total_class_counts[0],
            "1_road_crack": total_class_counts[1],
            "2_manhole":   total_class_counts[2],
        },
        "missing_label_list":  missing_labels[:20],
        "corrupt_image_list":  corrupt_images[:20],
        "empty_label_list":    empty_labels[:20],
        "errors":              errors[:100],   # cap at 100 for readability
    }

    # ── Write report ─────────────────────────────────────────────────────────
    if output_report_path is None:
        output_report_path = Path("data_quality_report.json")
    output_report_path = Path(output_report_path)
    output_report_path.parent.mkdir(parents=True, exist_ok=True)

    with open(output_report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)

    # ── Console summary ───────────────────────────────────────────────────────
    print("\n--- Validation Summary ---")
    print(f"Valid pairs:         {report['valid_image_label_pairs']}")
    print(f"Missing labels:      {report['missing_label_files']}")
    print(f"Corrupt images:      {report['corrupt_images']}")
    print(f"Empty label files:   {report['empty_label_files']}")
    print(f"Invalid label rows:  {report['invalid_label_rows']}")
    print(f"Class annotation counts:")
    for k, v in report["class_counts"].items():
        print(f"  {k}: {v}")
    print(f"\nData Quality Report → {output_report_path.resolve()}")

    if errors:
        print(f"\n[WARNING] {len(errors)} data quality issue(s) found. "
              "Review the report before training.")
        if len(valid_pairs) == 0:
            print("[FAIL] Zero valid pairs found. Stopping dataset pipeline.")
            sys.exit(1)
    else:
        print("\n[OK] Dataset validation passed with 0 errors.")

    return report


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="CivicFix dataset validation script."
    )
    parser.add_argument(
        "--dataset", "-d",
        help="Path to the dataset root directory (auto-detected if omitted).",
    )
    parser.add_argument(
        "--report", "-r",
        default=None,
        help="Output path for data_quality_report.json.",
    )
    args = parser.parse_args()

    ds_dir = Path(args.dataset) if args.dataset else find_dataset_dir()
    if ds_dir is None:
        print("Please specify --dataset path.")
        sys.exit(1)

    validate_dataset(ds_dir, output_report_path=args.report)


if __name__ == "__main__":
    main()
