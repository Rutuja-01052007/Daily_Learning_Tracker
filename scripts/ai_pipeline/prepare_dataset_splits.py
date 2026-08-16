#!/usr/bin/env python3
"""
CivicFix AI Pipeline - Dataset Split & Manifest Generator
----------------------------------------------------------
Creates the working directory structure for Ultralytics YOLO segmentation training:

  civicfix_road_damage/
    images/  {train, val, test}
    labels/  {train, val, test}
    manifests/
      dataset_manifest.csv      (combined, all splits)
      train_manifest.csv
      val_manifest.csv
      test_manifest.csv
    reports/
      split_class_counts.json
    data.yaml

Performs a deterministic 70 % / 15 % / 15 % split with seed=42.
Image and its matching label always move together.
No image may appear in more than one split.

Usage:
  python prepare_dataset_splits.py                           # auto paths
  python prepare_dataset_splits.py --source /path/to/data
  python prepare_dataset_splits.py --source /s --output /o --seed 42
"""

import os
import sys
import csv
import json
import random
import shutil
import hashlib
import argparse
from pathlib import Path

DEFAULT_WORKING_DIR = Path("/kaggle/working/civicfix_road_damage")
LOCAL_WORKING_DIR   = Path("data/processed/civicfix_road_damage")

KAGGLE_INPUT_DIR    = Path("/kaggle/input/datasets/lorenzoarcioni"
                           "/road-damage-dataset-potholes-cracks-and-manholes/data")
LOCAL_INPUT_DIR     = Path("data/raw/road_damage/data")

SUPPORTED_EXTS      = {".jpg", ".jpeg", ".png", ".webp"}
CLASS_NAME_MAP      = {0: "pothole", 1: "road_crack", 2: "manhole"}


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

def get_default_working_dir() -> Path:
    return DEFAULT_WORKING_DIR if Path("/kaggle/working").exists() else LOCAL_WORKING_DIR


def find_source_dir() -> Path | None:
    for p in [KAGGLE_INPUT_DIR, LOCAL_INPUT_DIR, Path("data/raw/road_damage")]:
        if p.exists():
            return p
    return None


def sha256_of_file(filepath: Path) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_class_ids(label_path: Path) -> list[int]:
    """Return sorted list of unique class IDs found in a label file."""
    classes: set[int] = set()
    if label_path.exists():
        with open(label_path, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split()
                if parts:
                    try:
                        classes.add(int(parts[0]))
                    except ValueError:
                        pass
    return sorted(classes)


# ---------------------------------------------------------------------------
# Split logic
# ---------------------------------------------------------------------------

def prepare_splits(source_dir: Path, output_working_dir: Path, seed: int = 42):
    """
    Copy image-label pairs into the working directory split structure
    and generate manifests + data.yaml.

    Returns:
        Path to output_working_dir on success.
    """
    print("=" * 50)
    print("CIVICFIX DATASET SPLIT & MANIFEST PREPARATION")
    print(f"Source Dir:  {source_dir}")
    print(f"Output Dir:  {output_working_dir}")
    print(f"Seed:        {seed}")
    print("=" * 50)

    # ── Create directory structure ──────────────────────────────────────────
    for sub in [
        "images/train", "images/val", "images/test",
        "labels/train",  "labels/val",  "labels/test",
        "manifests", "reports",
    ]:
        (output_working_dir / sub).mkdir(parents=True, exist_ok=True)

    # ── Locate image & label roots ──────────────────────────────────────────
    images_dir = (source_dir / "images") if (source_dir / "images").exists() else source_dir
    labels_dir = (source_dir / "labels") if (source_dir / "labels").exists() else source_dir

    # ── Collect valid image-label pairs ────────────────────────────────────
    pairs: list[tuple[Path, Path]] = []
    for root, _, files in os.walk(images_dir):
        for f in files:
            img_path = Path(root) / f
            if img_path.suffix.lower() not in SUPPORTED_EXTS:
                continue
            stem = img_path.stem
            lbl_path = labels_dir / f"{stem}.txt"
            if not lbl_path.exists():
                matches = list(labels_dir.glob(f"**/{stem}.txt"))
                lbl_path = matches[0] if matches else None
            if lbl_path and lbl_path.exists():
                pairs.append((img_path, lbl_path))

    total = len(pairs)
    print(f"\nTotal verified image-label pairs: {total}")
    if total == 0:
        print("[FAIL] No valid image-label pairs found.")
        sys.exit(1)

    # ── Deterministic shuffle & split ───────────────────────────────────────
    random.seed(seed)
    random.shuffle(pairs)

    n_train = int(total * 0.70)
    n_val   = int(total * 0.15)

    split_map = {
        "train": pairs[:n_train],
        "val":   pairs[n_train: n_train + n_val],
        "test":  pairs[n_train + n_val:],
    }

    print(f"Split counts → train: {len(split_map['train'])}  "
          f"val: {len(split_map['val'])}  "
          f"test: {len(split_map['test'])}")

    # ── Copy files & build manifest rows ───────────────────────────────────
    fieldnames = [
        "original_source_path", "file_name", "split",
        "checksum", "class_ids_found",
        "target_image_path", "target_label_path",
    ]
    all_rows: list[dict] = []
    split_rows: dict[str, list[dict]] = {"train": [], "val": [], "test": []}

    # Per-split class counts for the report
    split_class_counts: dict[str, dict] = {
        split: {f"{k}_{v}": 0 for k, v in CLASS_NAME_MAP.items()}
        for split in ("train", "val", "test")
    }

    for split_name, pair_list in split_map.items():
        print(f"\nProcessing '{split_name}' split ({len(pair_list)} pairs)…")
        for img_p, lbl_p in pair_list:
            tgt_img = output_working_dir / "images" / split_name / img_p.name
            tgt_lbl = output_working_dir / "labels" / split_name / lbl_p.name

            if img_p.resolve() != tgt_img.resolve():
                shutil.copy2(img_p, tgt_img)
            if lbl_p.resolve() != tgt_lbl.resolve():
                shutil.copy2(lbl_p, tgt_lbl)

            checksum      = sha256_of_file(img_p)
            classes_found = extract_class_ids(lbl_p)

            row = {
                "original_source_path": str(img_p),
                "file_name":            img_p.name,
                "split":                split_name,
                "checksum":             checksum,
                "class_ids_found":      json.dumps(classes_found),
                "target_image_path":    str(tgt_img),
                "target_label_path":    str(tgt_lbl),
            }
            all_rows.append(row)
            split_rows[split_name].append(row)

            # Accumulate class counts
            for cls_id in classes_found:
                key = f"{cls_id}_{CLASS_NAME_MAP.get(cls_id, 'unknown')}"
                if key in split_class_counts[split_name]:
                    split_class_counts[split_name][key] += 1

    # ── Write combined manifest ─────────────────────────────────────────────
    combined_manifest = output_working_dir / "manifests" / "dataset_manifest.csv"
    _write_csv(combined_manifest, fieldnames, all_rows)
    print(f"\n[OK] Combined manifest → {combined_manifest}  ({len(all_rows)} rows)")

    # ── Write per-split manifests ───────────────────────────────────────────
    for split_name, rows in split_rows.items():
        split_manifest = output_working_dir / "manifests" / f"{split_name}_manifest.csv"
        _write_csv(split_manifest, fieldnames, rows)
        print(f"[OK] {split_name} manifest  → {split_manifest}  ({len(rows)} rows)")

    # ── Write split class counts report ────────────────────────────────────
    class_counts_report = {
        "seed":               seed,
        "total_pairs":        total,
        "split_sizes": {
            "train": len(split_map["train"]),
            "val":   len(split_map["val"]),
            "test":  len(split_map["test"]),
        },
        "split_class_counts": split_class_counts,
    }
    counts_path = output_working_dir / "reports" / "split_class_counts.json"
    with open(counts_path, "w", encoding="utf-8") as f:
        json.dump(class_counts_report, f, indent=2)
    print(f"[OK] Class count report → {counts_path}")

    # ── Generate data.yaml ──────────────────────────────────────────────────
    yaml_content = (
        f"path: {output_working_dir.as_posix()}\n"
        "train: images/train\n"
        "val:   images/val\n"
        "test:  images/test\n"
        "names:\n"
        "  0: pothole\n"
        "  1: road_crack\n"
        "  2: manhole\n"
    )
    yaml_path = output_working_dir / "data.yaml"
    with open(yaml_path, "w", encoding="utf-8") as f:
        f.write(yaml_content)
    print(f"[OK] data.yaml → {yaml_path}")

    print(f"\n[OK] Dataset prepared at: {output_working_dir.resolve()}")
    return output_working_dir


def _write_csv(path: Path, fieldnames: list[str], rows: list[dict]):
    with open(path, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="CivicFix dataset split & manifest generator."
    )
    parser.add_argument(
        "--source", "-s",
        help="Path to the source dataset root (auto-detected if omitted).",
    )
    parser.add_argument(
        "--output", "-o",
        help="Path for the output working directory (auto-detected if omitted).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Random seed for deterministic split (default: 42).",
    )
    args = parser.parse_args()

    src_dir = Path(args.source) if args.source else find_source_dir()
    if src_dir is None:
        print("[FAIL] Source dataset directory not found. Use --source.")
        sys.exit(1)

    out_dir = Path(args.output) if args.output else get_default_working_dir()

    prepare_splits(src_dir, out_dir, seed=args.seed)


if __name__ == "__main__":
    main()
