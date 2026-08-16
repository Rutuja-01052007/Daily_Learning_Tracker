#!/usr/bin/env python3
"""
CivicFix AI Pipeline - YOLO Segmentation Training Script
--------------------------------------------------------
Trains an Ultralytics YOLOv8n-seg polygon segmentation model on the
CivicFix Road Damage Dataset (Potholes, Cracks, and Manholes).

Execution Plan:
1. 5-Epoch Validation Test Run
2. 30-Epoch V1 Training Run (batch=4, img=640, patience=10, seed=42)
3. GPU Memory Fallback (batch=4 -> batch=2 on CUDA OOM)
4. Saves model checkpoints & evaluation plots
"""

import os
import sys
import json
import shutil
from pathlib import Path

def train_yolo_segmentation(data_yaml_path, project_dir="/kaggle/working/civicfix_runs"):
    print("==================================================")
    print("CIVICFIX YOLO SEGMENTATION TRAINING PIPELINE")
    print(f"Data Config: {data_yaml_path}")
    print(f"Project Output: {project_dir}")
    print("==================================================")

    try:
        from ultralytics import YOLO
    except ImportError:
        print("[FAIL] Ultralytics package is not installed.")
        print("Install via: pip install ultralytics")
        sys.exit(1)

    # 1. Verification of data.yaml
    if not Path(data_yaml_path).exists():
        print(f"[FAIL] data.yaml not found at {data_yaml_path}")
        sys.exit(1)

    model_name = "yolov8n-seg.pt"
    print(f"Loading pretrained segmentation model: {model_name}...")
    model = YOLO(model_name)

    # Step 1: 5-Epoch Validation Test Run
    print("\n---> Starting 5-Epoch Validation Test Run...")
    try:
        test_results = model.train(
            data=str(data_yaml_path),
            epochs=5,
            imgsz=640,
            batch=4,
            pretrained=True,
            seed=42,
            plots=True,
            project=project_dir,
            name="validation_test_run",
            exist_ok=True
        )
        print("[OK] Validation test run completed successfully.")
    except Exception as e:
        error_msg = str(e).lower()
        if "out of memory" in error_msg or "cuda" in error_msg:
            print("[WARN] CUDA Out of Memory during 5-epoch test. Retrying with batch=2...")
            test_results = model.train(
                data=str(data_yaml_path),
                epochs=5,
                imgsz=640,
                batch=2,
                pretrained=True,
                seed=42,
                plots=True,
                project=project_dir,
                name="validation_test_run",
                exist_ok=True
            )
        else:
            print(f"[FAIL] Error during validation test run: {e}")
            sys.exit(1)

    # Step 2: 30-Epoch V1 Training Run
    print("\n---> Starting 30-Epoch V1 Production Training Run...")
    v1_model = YOLO(model_name)
    run_name = "civicfix_road_damage_seg_v1"
    
    try:
        train_results = v1_model.train(
            data=str(data_yaml_path),
            epochs=30,
            imgsz=640,
            batch=4,
            pretrained=True,
            patience=10,
            seed=42,
            plots=True,
            project=project_dir,
            name=run_name,
            exist_ok=True
        )
    except Exception as e:
        error_msg = str(e).lower()
        if "out of memory" in error_msg or "cuda" in error_msg:
            print("[WARN] CUDA Out of Memory during 30-epoch training. Reducing batch size to 2 and retrying...")
            train_results = v1_model.train(
                data=str(data_yaml_path),
                epochs=30,
                imgsz=640,
                batch=2,
                pretrained=True,
                patience=10,
                seed=42,
                plots=True,
                project=project_dir,
                name=run_name,
                exist_ok=True
            )
        else:
            print(f"[FAIL] Training failed with error: {e}")
            sys.exit(1)

    run_dir = Path(project_dir) / run_name
    print(f"\n[OK] Training complete. Artifacts saved in: {run_dir.resolve()}")
    
    # Save class_mapping.json artifact
    class_mapping = {
        "0": "pothole",
        "1": "road_crack",
        "2": "manhole"
    }
    with open(run_dir / "class_mapping.json", "w") as f:
        json.dump(class_mapping, f, indent=2)

    return run_dir

if __name__ == "__main__":
    yaml_p = Path("/kaggle/working/civicfix_road_damage/data.yaml")
    if not yaml_p.exists():
        yaml_p = Path("data/processed/civicfix_road_damage/data.yaml")
    if not yaml_p.exists():
        yaml_p = Path("scripts/ai_pipeline/data.yaml")

    train_yolo_segmentation(yaml_p)
