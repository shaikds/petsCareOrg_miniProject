from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
from PIL import Image
import torch
import clip
import io
import os

app = FastAPI(
    title="PetCare Embedding Server",
    description="AI-powered embedding generation for pet adoption platform",
    version="1.0.0"
)

# Load CLIP model
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Loading CLIP model on device: {device}")
model, preprocess = clip.load("ViT-B/32", device=device)
print("CLIP model loaded successfully")

class TextIn(BaseModel):
    text: str

@app.get('/health')
def health_check():
    """Health check endpoint to verify server is running."""
    return {
        'status': 'healthy',
        'device': device,
        'model': 'ViT-B/32'
    }

@app.get('/')
def root():
    """Root endpoint with basic info."""
    return {
        'message': 'PetCare Embedding Server',
        'version': '1.0.0',
        'endpoints': {
            'health': '/health',
            'text_embedding': '/embed_text',
            'image_embedding': '/embed_image'
        }
    }

@app.post('/embed_text')
def embed_text(data: TextIn):
    """Generate text embedding using CLIP model."""
    try:
        if not data.text or not data.text.strip():
            return {'error': 'Text cannot be empty'}

        with torch.no_grad():
            text_tokens = clip.tokenize([data.text]).to(device)
            text_features = model.encode_text(text_tokens)
            embedding = text_features[0].cpu().tolist()

            return {
                'embedding': embedding,
                'dimensions': len(embedding),
                'model': 'ViT-B/32'
            }
    except Exception as e:
        return {'error': f'Text embedding failed: {str(e)}'}

@app.post('/embed_image')
async def embed_image(file: UploadFile = File(...)):
    """Generate image embedding using CLIP model."""
    try:
        # Validate file type
        if file.content_type not in ['image/jpeg', 'image/jpg', 'image/png', 'image/webp']:
            return {'error': 'Unsupported image format. Use JPEG, PNG, or WebP.'}

        # Read and process image
        image_bytes = await file.read()
        if len(image_bytes) == 0:
            return {'error': 'Empty image file'}

        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        image_input = preprocess(image).unsqueeze(0).to(device)

        with torch.no_grad():
            image_features = model.encode_image(image_input)
            embedding = image_features[0].cpu().tolist()

            return {
                'embedding': embedding,
                'dimensions': len(embedding),
                'model': 'ViT-B/32',
                'image_size': image.size
            }
    except Exception as e:
        return {'error': f'Image embedding failed: {str(e)}'}

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv('PORT', 8000))
    host = os.getenv('HOST', '0.0.0.0')

    print(f"Starting PetCare Embedding Server on {host}:{port}")
    print(f"Model device: {device}")
    print("Ready to generate embeddings!")

    uvicorn.run(app, host=host, port=port)