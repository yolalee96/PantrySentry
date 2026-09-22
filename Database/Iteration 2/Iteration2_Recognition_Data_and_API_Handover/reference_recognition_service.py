"""Private CPU image/OCR service. All classifications are suggestions, never inventory writes."""
import csv
import io
import os
import secrets
import threading
from pathlib import Path
from typing import Annotated

import numpy as np
import pytesseract
from fastapi import FastAPI, Header, HTTPException, Request, Depends
from PIL import Image, ImageOps, UnidentifiedImageError

ROOT = Path(__file__).resolve().parent
MAX_BYTES = 8 * 1024 * 1024
Image.MAX_IMAGE_PIXELS = 12_000_000
KEY = os.environ.get('RECOGNITION_SERVICE_KEY','')
MODEL = 'google/siglip-base-patch16-224'
REVISION = '7fd15f0689c79d79e38b1c2e2e2370a7bf2761ed'
lock = threading.Lock()
model = processor = text_features = None
labels = []
app = FastAPI(title='PantryBuddy private recognition service',version='3.0.0')

def auth(x_service_key: Annotated[str | None, Header()] = None):
    if not KEY or not x_service_key or not secrets.compare_digest(KEY,x_service_key):
        raise HTTPException(401,'Private service key required')

async def read_image(request):
    raw = bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw)>MAX_BYTES: raise HTTPException(413,'Image exceeds 8 MiB')
    try:
        image=Image.open(io.BytesIO(raw))
        if image.format not in ('JPEG','PNG','WEBP'): raise ValueError('Unsupported format')
        if image.width*image.height>12_000_000: raise ValueError('Image exceeds 12 megapixels')
        image=ImageOps.exif_transpose(image).convert('RGB')
        image.thumbnail((2400,2400))
        return image
    except (UnidentifiedImageError,ValueError,Image.DecompressionBombError,OSError) as e:
        raise HTTPException(400,'Invalid or oversized JPEG, PNG or WebP image') from e

def load_model():
    global model,processor,text_features,labels
    if model is not None: return
    import torch
    from transformers import AutoModel, AutoProcessor
    torch.set_num_threads(4)
    p=AutoProcessor.from_pretrained(MODEL,revision=REVISION)
    m=AutoModel.from_pretrained(MODEL,revision=REVISION,use_safetensors=True).eval()
    with (ROOT/'visual_labels.csv').open(encoding='utf-8') as f: rows=list(csv.DictReader(f))
    labels=[r['label'] for r in rows]
    labels += ['a non-food household object','an empty scene','a person','an unreadable package']
    texts=['a photo of '+name for name in labels[:-4]]+labels[-4:]
    features=[]
    with torch.inference_mode():
        for start in range(0,len(texts),32):
            batch=p(text=texts[start:start+32],padding='max_length',truncation=True,return_tensors='pt')
            f=m.get_text_features(**batch)
            features.append(f / f.norm(p=2,dim=-1,keepdim=True))
    processor=p; text_features=torch.cat(features); model=m

def classify(image):
    import torch
    with lock:
        load_model()
        with torch.inference_mode():
            inp=processor(images=image,return_tensors='pt')
            f=model.get_image_features(**inp)
            f=f / f.norm(p=2,dim=-1,keepdim=True)
            logits=(f @ text_features.T)*model.logit_scale.exp()+model.logit_bias
            scores=logits.sigmoid()[0]
            values,indices=scores.topk(min(5,len(labels)))
        result=[{'name':labels[int(i)],'score':round(float(v),6)} for v,i in zip(values,indices)]
    if int(indices[0])>=len(labels)-4:
        return {'candidates':[],'action':'MANUAL_INPUT','reason':'NON_FOOD_OR_UNCLEAR'}
    return {'candidates':[r for r in result if r['name'] not in labels[-4:]],'action':'CONFIRM',
            'scoreMeaning':'Uncalibrated image-text similarity; not accuracy or food-safety confidence'}

def ocr(image):
    # Memory input and unique internal temporary files managed by pytesseract; no shared upload path.
    text=pytesseract.image_to_string(image,lang='eng',config='--psm 11',timeout=25).strip()
    return {'text':text,'action':'CONFIRM' if text else 'MANUAL_INPUT'}

@app.get('/health')
def health():
    return {'ok':True,'modelLoaded':model is not None,'modelId':MODEL,'modelRevision':REVISION,
            'ocr':'Tesseract English','maxImageBytes':MAX_BYTES}

@app.post('/warmup',dependencies=[Depends(auth)])
def warmup():
    with lock: load_model()
    return {'ok':True,'visualLabels':len(labels)-4}

@app.post('/image',dependencies=[Depends(auth)])
async def image_route(request:Request):
    from starlette.concurrency import run_in_threadpool
    image=await read_image(request)
    return {**(await run_in_threadpool(classify,image)),'requiresConfirmation':True,'scope':'ONE_ITEM_OR_USER_CROP'}

@app.post('/ocr',dependencies=[Depends(auth)])
async def ocr_route(request:Request):
    from starlette.concurrency import run_in_threadpool
    image=await read_image(request)
    try: result=await run_in_threadpool(ocr,image)
    except RuntimeError as e: raise HTTPException(504,'OCR timed out; enter name manually') from e
    return {**result,'requiresConfirmation':True}

@app.post('/photo',dependencies=[Depends(auth)])
async def photo_route(request:Request):
    from starlette.concurrency import run_in_threadpool
    image=await read_image(request)
    visual=await run_in_threadpool(classify,image)
    try: text=await run_in_threadpool(ocr,image)
    except RuntimeError: text={'text':'','action':'MANUAL_INPUT','warning':'OCR_TIMEOUT'}
    return {'visual':visual,'ocr':text,'requiresConfirmation':True,'scope':'ONE_ITEM_OR_USER_CROP'}
