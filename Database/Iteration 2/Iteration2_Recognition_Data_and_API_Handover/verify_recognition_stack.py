"""Standalone feasibility checks for the PantryBuddy recognition stack.

This script is not backend production code. It verifies the local image model,
optional OCR installation, and optional Open Food Facts barcode lookup.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import requests
from PIL import Image


MODEL_ID = "google/siglip-base-patch16-224"
MODEL_REVISION = "7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed"


def load_labels(path: Path, limit: int) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            raise ValueError("visual_labels.csv has no header")
        label_column = next(
            (name for name in ("label", "product_name", "keyword") if name in reader.fieldnames),
            reader.fieldnames[0],
        )
        labels = []
        for row in reader:
            value = (row.get(label_column) or "").strip()
            if value and value not in labels:
                labels.append(value)
            if len(labels) >= limit:
                break
    if not labels:
        raise ValueError("No candidate labels found")
    return labels


def test_image(image_path: Path, labels_path: Path, label_limit: int) -> dict:
    from transformers import pipeline

    labels = load_labels(labels_path, label_limit)
    classifier = pipeline(
        task="zero-shot-image-classification",
        model=MODEL_ID,
        revision=MODEL_REVISION,
        device=-1,
    )
    image = Image.open(image_path).convert("RGB")
    results = classifier(image, candidate_labels=labels)
    return {"component": "siglip", "top_candidates": results[:5]}


def test_ocr(image_path: Path) -> dict:
    import pytesseract

    text = pytesseract.image_to_string(Image.open(image_path), lang="eng").strip()
    return {"component": "tesseract", "text": text}


def test_barcode(barcode: str) -> dict:
    if not barcode.isdigit():
        raise ValueError("Barcode must contain digits only")
    url = f"https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
    response = requests.get(
        url,
        params={"fields": "code,product_name,categories_tags,brands"},
        headers={"User-Agent": "PantryBuddy-Iteration2-Feasibility-Test/1.0"},
        timeout=15,
    )
    response.raise_for_status()
    payload = response.json()
    product = payload.get("product") or {}
    return {
        "component": "open_food_facts",
        "http_status": response.status_code,
        "found": payload.get("status") == 1,
        "code": product.get("code") or barcode,
        "product_name": product.get("product_name"),
        "brands": product.get("brands"),
        "categories_tags": product.get("categories_tags") or [],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", type=Path, help="Single-item image for SigLIP")
    parser.add_argument("--ocr-image", type=Path, help="Packaging image for OCR")
    parser.add_argument("--barcode", help="Barcode for Open Food Facts lookup")
    parser.add_argument(
        "--labels",
        type=Path,
        default=Path(__file__).with_name("visual_labels.csv"),
    )
    parser.add_argument("--label-limit", type=int, default=100)
    args = parser.parse_args()

    if not any((args.image, args.ocr_image, args.barcode)):
        parser.error("Provide --image, --ocr-image or --barcode")

    output = []
    if args.image:
        output.append(test_image(args.image, args.labels, args.label_limit))
    if args.ocr_image:
        output.append(test_ocr(args.ocr_image))
    if args.barcode:
        output.append(test_barcode(args.barcode))
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

