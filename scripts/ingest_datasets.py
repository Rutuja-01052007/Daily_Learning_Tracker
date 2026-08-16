#!/usr/bin/env python3
"""
CivicFix - Automated Dataset Ingestion & Validation Pipeline
--------------------------------------------------------------
Downloads the APPROVED Kaggle dataset securely without exposing API credentials.
Generates a dataset file inventory, validates image/annotation formats, detects
annotation formats automatically, and records provenance metadata.

APPROVED DATASETS (first model — v1):
  lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes
    → Classes: pothole (0), road_crack (1), manhole (2)
    → License status: EDUCATIONAL_ONLY (see db/migrations/011_dataset_registry.sql)

All other datasets are NOT approved for the v1 model and must NOT be added here
without explicit project authorization and a new dataset_registry entry.

Credentials:
  Kaggle API credentials must be in environment variables ONLY:
    KAGGLE_USERNAME
    KAGGLE_KEY
  Never store them in source code, config files, or PostgreSQL.

Usage:
  KAGGLE_USERNAME=... KAGGLE_KEY=... python ingest_datasets.py
"""

import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path

# ---------------------------------------------------------------------------
# Approved datasets — only one for the v1 model
# ---------------------------------------------------------------------------
APPROVED_DATASETS = [
    {
        "id":         "lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes",
        "target_dir": "data/raw/road_damage",
        "name":       "Road Damage Dataset: Potholes, Cracks and Manholes",
        # License status at time of inclusion — see 011_dataset_registry.sql
        "license_status": "EDUCATIONAL_ONLY",
        "note": (
            "Approved for CivicFix v1 model training (educational/hackathon only). "
            "Commercial use requires explicit license verification. "
            "Do NOT add other datasets without updating dataset_registry."
        ),
    },
]


# ---------------------------------------------------------------------------
# Credentials check
# ---------------------------------------------------------------------------

def check_credentials():
    """Verify Kaggle API credentials without printing sensitive values."""
    username = os.environ.get("KAGGLE_USERNAME")
    key      = os.environ.get("KAGGLE_KEY")

    if not username or not key:
        print(
            "ERROR: Kaggle API credentials missing from the environment.\n"
            "Set them as environment variables:\n"
            "  export KAGGLE_USERNAME=your_username\n"
            "  export KAGGLE_KEY=your_api_key\n"
            "Do NOT store credentials in source code or config files."
        )
        sys.exit(1)

    print("[OK] Kaggle credentials verified (present in environment variables).")


# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------

def download_dataset(dataset_info: dict):
    """Download a single Kaggle dataset to target_dir using the Kaggle CLI."""
    dataset_id  = dataset_info["id"]
    target_path = Path(dataset_info["target_dir"])
    target_path.mkdir(parents=True, exist_ok=True)

    print(f"\n---> Downloading dataset: {dataset_id}")
    print(f"     License status: {dataset_info['license_status']}")
    print(f"     Target: {target_path.resolve()}")

    # Warn if not APPROVED
    if dataset_info["license_status"] not in ("APPROVED",):
        print(
            f"[WARN] Dataset license_status is '{dataset_info['license_status']}'. "
            "This dataset may be used for educational/hackathon purposes only. "
            "Do NOT use for commercial purposes without explicit legal approval."
        )

    cmd = [
        sys.executable, "-m", "kaggle", "datasets", "download",
        "-d", dataset_id,
        "-p", str(target_path),
        "--unzip",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"[OK] Downloaded and unzipped: {dataset_id} → {target_path}")
        if result.stdout.strip():
            print(result.stdout.strip())
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] Download failed for dataset: {dataset_id}")
        print(f"  stderr: {e.stderr.strip()}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------

def calculate_checksum(filepath: Path) -> str:
    """Compute SHA-256 checksum of a file."""
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def detect_annotation_format(directory: Path) -> list[str]:
    """Automatically detect annotation format(s) in downloaded directory."""
    formats: set[str] = set()
    for root, _, files in os.walk(directory):
        for f in files:
            ext = Path(f).suffix.lower()
            if ext == ".txt":
                formats.add("YOLO (.txt)")
            elif ext == ".xml":
                formats.add("Pascal VOC (.xml)")
            elif ext == ".json":
                formats.add("COCO / JSON (.json)")
    return list(formats) if formats else ["Unknown / Unannotated"]


def generate_inventory(dataset_info: dict) -> dict:
    """Report actual directory structure, image counts, and formats."""
    raw_dir           = Path(dataset_info["target_dir"])
    image_extensions  = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

    total_files       = 0
    image_files:  list[Path] = []
    annotation_files: list[Path] = []

    print(f"\n--- Directory Inventory: {dataset_info['name']} ---")
    print(f"Path: {raw_dir.resolve()}")

    for root, dirs, files in os.walk(raw_dir):
        level  = len(Path(root).relative_to(raw_dir).parts)
        indent = "    " * level
        print(f"{indent}folder: {Path(root).name}/")
        for fname in files[:5]:
            print(f"{indent}    - {fname}")
        if len(files) > 5:
            print(f"{indent}    … ({len(files) - 5} more files)")

        for fname in files:
            total_files += 1
            ext = Path(fname).suffix.lower()
            full = Path(root) / fname
            if ext in image_extensions:
                image_files.append(full)
            elif ext in {".txt", ".xml", ".json"}:
                annotation_files.append(full)

    ann_formats = detect_annotation_format(raw_dir)

    print(f"\nTotal files:       {total_files}")
    print(f"Total images:      {len(image_files)}")
    print(f"Total annotations: {len(annotation_files)}")
    print(f"Annotation format: {', '.join(ann_formats)}")

    return {
        "dataset_id":         dataset_info["id"],
        "name":               dataset_info["name"],
        "license_status":     dataset_info["license_status"],
        "target_dir":         str(raw_dir),
        "total_files":        total_files,
        "image_count":        len(image_files),
        "annotation_count":   len(annotation_files),
        "annotation_formats": ann_formats,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 50)
    print("CIVICFIX AUTOMATED DATASET INGESTION PIPELINE")
    print("=" * 50)

    # 1. Verify credentials securely
    check_credentials()

    # 2. Download and inventory approved datasets
    inventory_summary: list[dict] = []
    for ds in APPROVED_DATASETS:
        download_dataset(ds)
        inv = generate_inventory(ds)
        inventory_summary.append(inv)

    # 3. Save ingestion manifest
    manifest_dir = Path("data/manifests")
    manifest_dir.mkdir(parents=True, exist_ok=True)
    manifest_file = manifest_dir / "ingestion_manifest.json"

    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(inventory_summary, f, indent=2)

    print(f"\n[OK] Dataset ingestion complete.")
    print(f"     Manifest → {manifest_file.resolve()}")

    # 4. Remind about next step
    print(
        "\nNext step: validate the downloaded dataset before training.\n"
        "  python scripts/ai_pipeline/run_pipeline.py --stage validate\n"
        "  python scripts/ai_pipeline/run_pipeline.py --stage all"
    )


if __name__ == "__main__":
    main()
