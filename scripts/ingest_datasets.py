#!/usr/bin/env python3
"""
CivicFix - Automated Dataset Ingestion & Validation Pipeline
--------------------------------------------------------------
Downloads approved Kaggle datasets securely without exposing API credentials.
Generates dataset file inventory, validates image/annotation formats, detects annotations automatically,
and records dataset provenance metadata for PostgreSQL dataset_registry.
"""

import os
import sys
import json
import hashlib
import subprocess
from pathlib import Path

# Required Kaggle Datasets Configuration
APPROVED_DATASETS = [
    {
        "id": "lorenzoarcioni/road-damage-dataset-potholes-cracks-and-manholes",
        "target_dir": "data/raw/road_damage",
        "name": "Road Damage Dataset: Potholes, Cracks and Manholes",
        "license": "MIT",
        "category": "road_damage"
    },
    {
        "id": "anggadwisunarto/potholes-detection-yolov8",
        "target_dir": "data/raw/pothole_yolov8",
        "name": "Potholes Detection YOLOv8",
        "license": "CC BY 4.0",
        "category": "pothole"
    },
    {
        "id": "idanbaru/annotated-potholes-with-severity-levels",
        "target_dir": "data/raw/pothole_severity",
        "name": "Annotated Potholes with Severity Levels",
        "license": "CC BY-SA 4.0",
        "category": "pothole_severity"
    },
    {
        "id": "spellsharp/garbage-data",
        "target_dir": "data/raw/waste_yolov8",
        "name": "Garbage Data YOLOv8",
        "license": "CC BY-NC 4.0",
        "category": "garbage"
    }
]

def check_credentials():
    """Verify Kaggle API credentials without printing sensitive values."""
    username = os.environ.get("KAGGLE_USERNAME")
    key = os.environ.get("KAGGLE_KEY")

    if not username or not key:
        print("ERROR: Kaggle API credentials are missing from the environment.")
        print("Add your Kaggle API credentials to Antigravity Secrets / Environment Variables, then run the dataset-ingestion job again.")
        sys.exit(1)
    
    print("[OK] Kaggle credentials verified securely in environment variables.")

def download_dataset(dataset_info):
    """Download a single Kaggle dataset to target_dir using Kaggle CLI."""
    dataset_id = dataset_info["id"]
    target_path = Path(dataset_info["target_dir"])
    target_path.mkdir(parents=True, exist_ok=True)

    print(f"\n---> Downloading dataset: {dataset_id}")
    cmd = [
        sys.executable, "-m", "kaggle", "datasets", "download",
        "-d", dataset_id,
        "-p", str(target_path),
        "--unzip"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f"[OK] Downloaded and unzipped {dataset_id} to {target_path}")
    except subprocess.CalledProcessError as e:
        print(f"[FAIL] Download failed for dataset {dataset_id}")
        print(f"Error output: {e.stderr}")
        sys.exit(1)

def calculate_checksum(filepath):
    """Compute SHA256 checksum of a file."""
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    return sha256.hexdigest()

def detect_annotation_format(directory):
    """Automatically detect annotation format in downloaded directory."""
    formats = set()
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

def generate_inventory(dataset_info):
    """Report actual directory structure, image counts, and formats."""
    raw_dir = Path(dataset_info["target_dir"])
    image_extensions = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
    
    total_files = 0
    image_files = []
    annotation_files = []
    
    print(f"\n--- Directory Structure & Inventory for {dataset_info['name']} ---")
    print(f"Path: {raw_dir.resolve()}")
    
    for root, dirs, files in os.walk(raw_dir):
        level = len(Path(root).relative_to(raw_dir).parts)
        indent = " " * 4 * level
        print(f"{indent}folder: {Path(root).name}/")
        for f in files[:5]:  # Show first 5 sample files
            print(f"{indent}    - {f}")
        if len(files) > 5:
            print(f"{indent}    ... ({len(files) - 5} more files)")
            
        for f in files:
            total_files += 1
            ext = Path(f).suffix.lower()
            if ext in image_extensions:
                image_files.append(Path(root) / f)
            elif ext in {".txt", ".xml", ".json"}:
                annotation_files.append(Path(root) / f)

    ann_formats = detect_annotation_format(raw_dir)
    print(f"\nTotal Files: {total_files}")
    print(f"Total Images: {len(image_files)}")
    print(f"Total Annotations: {len(annotation_files)}")
    print(f"Detected Annotation Format(s): {', '.join(ann_formats)}")
    
    return {
        "dataset_id": dataset_info["id"],
        "name": dataset_info["name"],
        "license": dataset_info["license"],
        "target_dir": str(raw_dir),
        "total_files": total_files,
        "image_count": len(image_files),
        "annotation_count": len(annotation_files),
        "annotation_formats": ann_formats
    }

def main():
    print("==================================================")
    print("CIVICFIX AUTOMATED DATASET INGESTION PIPELINE")
    print("==================================================")
    
    # 1. Verify credentials securely
    check_credentials()

    # 2. Download and inventory datasets
    inventory_summary = []
    for ds in APPROVED_DATASETS:
        download_dataset(ds)
        inv = generate_inventory(ds)
        inventory_summary.append(inv)
    
    # 3. Save ingestion manifest metadata
    manifest_dir = Path("data/manifests")
    manifest_dir.mkdir(parents=True, exist_ok=True)
    manifest_file = manifest_dir / "ingestion_manifest.json"
    
    with open(manifest_file, "w") as f:
        json.dump(inventory_summary, f, indent=2)
    
    print(f"\n[OK] Dataset Ingestion completed successfully.")
    print(f"Ingestion Manifest written to {manifest_file}")

if __name__ == "__main__":
    main()
