"""Reference backend-only wrapper for Google Cloud Vision Label Detection.

Google Vision is used only for visual labels. OCR remains Tesseract/Tesseract.js.
Never expose Google credentials or this internal endpoint directly to the browser.
"""
import os
from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from google.cloud import vision

app = FastAPI(title="PantryBuddy Google Vision Recognition")
MAX_BYTES = int(os.getenv("MAX_IMAGE_BYTES", "6000000"))
SERVICE_KEY = os.getenv("RECOGNITION_SERVICE_KEY", "")
client = vision.ImageAnnotatorClient()

def authorised(value: str | None) -> None:
    if not SERVICE_KEY or value != SERVICE_KEY:
        raise HTTPException(status_code=401, detail="Invalid service key")

@app.get("/health")
def health() -> dict:
    return {"ok": True, "provider": "google-cloud-vision", "feature": "LABEL_DETECTION"}

@app.post("/image-labels")
async def image_labels(
    image: UploadFile = File(...),
    x_service_key: str | None = Header(default=None),
) -> dict:
    authorised(x_service_key)
    content = await image.read(MAX_BYTES + 1)
    if not content or len(content) > MAX_BYTES:
        raise HTTPException(status_code=413, detail="Image is empty or too large")
    response = client.label_detection(image=vision.Image(content=content), max_results=20)
    if response.error.message:
        raise HTTPException(status_code=502, detail=response.error.message)
    return {
        "provider": "google-cloud-vision",
        "feature": "LABEL_DETECTION",
        "candidates": [
            {"label": item.description, "score": round(float(item.score), 6)}
            for item in response.label_annotations
        ],
        "action": "CONFIRM",
    }
