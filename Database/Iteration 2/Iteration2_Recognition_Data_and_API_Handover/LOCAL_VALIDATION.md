# Local Validation Evidence

The proposed recognition stack was tested locally before handover. This validation demonstrates technical feasibility; it is not an accuracy or food-safety study.

## Environment tested

- Recognition runtime: Python 3.11 in a local Docker container
- Image model: `google/siglip-base-patch16-224`
- Pinned model revision: `7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed`
- OCR engine: Tesseract with English language data
- Barcode metadata: Open Food Facts API v2
- Image-label input: the validated label set was rebuilt as 946 English candidate labels after non-English canonical taxonomy tags were removed

## Tests completed

| Component | Test performed | Result |
|---|---|---|
| SigLIP model | Model downloaded, loaded on CPU and evaluated against the candidate labels | Passed |
| Food image | A public-domain banana image was submitted | `Banana` was the first candidate (similarity approximately 0.879) |
| OCR | A test package image containing `ORGANIC BANANA MILK` and `BEST BEFORE 20 SEP 2026` was processed | Both text lines were extracted |
| Barcode API | Barcode `3017620422003` was requested from Open Food Facts | HTTP 200; Nutella product metadata and category tags returned |
| Category mapping | Open Food Facts tags for the Nutella test were matched through the prepared mapping data | Mapped to `Condiments, Sauces & Canned Goods` and marked for confirmation |
| Service controls | Missing service key and an image larger than the configured upload limit were tested | Requests were rejected as expected |

## Interpretation

- SigLIP can suggest an English item label from a single-item image without project-specific training.
- Tesseract can extract visible English packaging text but does not understand the food or verify a printed date.
- Open Food Facts can return packaged-product metadata when a barcode exists in its database.
- The SQL mapping data connects model labels, OCR text and Open Food Facts category tags to PantryBuddy's existing categories.
- All channels can fail or return ambiguous results, so the user must confirm the name and category before an inventory item is saved.

## What is not transferred

The local Docker image, downloaded model cache, environment secrets and temporary test images are not included. They are machine-specific and may be large. The backend team should install the dependencies and download the model in its own development or deployment environment.

`reference_recognition_service.py` is the tested image/OCR wrapper and may be used as implementation reference. `verify_recognition_stack.py` is a standalone feasibility test. Neither file implements PantryBuddy user authentication, database access or inventory creation; those integrations remain the backend team's responsibility.
