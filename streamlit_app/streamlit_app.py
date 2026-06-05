import streamlit as st
import torch
from transformers import AutoModelForImageSegmentation
from PIL import Image
import torchvision.transforms as T
import numpy as np
import os

st.set_page_config(page_title="BackGone Background Removal", page_icon="🎨")

st.title("🎨 BackGone Background Removal")
st.markdown("Upload an image to remove its background using AI")

@st.cache_resource
def load_model():
    """Load the RMBG-2.0 model (cached for performance)"""
    try:
        hf_token = os.environ.get("HF_TOKEN", "")
        if not hf_token:
            try:
                hf_token = st.secrets["hf_token"]
            except:
                pass

        if hf_token:
            from huggingface_hub import login
            login(token=hf_token)

        model = AutoModelForImageSegmentation.from_pretrained(
            "briaai/RMBG-2.0",
            trust_remote_code=True,
            low_cpu_mem_usage=True
        )
        model = model.eval()
        if torch.cuda.is_available():
            model = model.to("cuda")
        return model
    except Exception as e:
        st.error(f"Error loading model: {e}")
        st.info("💡 Set HF_TOKEN in Streamlit secrets or environment variable")
        return None

def preprocess_image(img: Image.Image) -> torch.Tensor:
    """Preprocess image for the model"""
    transform = T.Compose([
        T.Resize((1024, 1024)),
        T.ToTensor(),
        T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
    ])
    return transform(img).unsqueeze(0)

def remove_background(model, img: Image.Image) -> Image.Image:
    """Remove background from image"""
    device = "cuda" if torch.cuda.is_available() else "cpu"

    input_tensor = preprocess_image(img).to(device)

    with torch.no_grad():
        outputs = model(input_tensor)

    mask = torch.sigmoid(outputs[3]).squeeze()

    mask = mask.cpu().numpy()

    img_np = np.array(img)

    from PIL import Image as PILImage
    mask_pil = PILImage.fromarray((mask * 255).astype(np.uint8))
    mask_pil = mask_pil.resize((img_np.shape[1], img_np.shape[0]), PILImage.LANCZOS)
    mask_np = np.array(mask_pil) / 255.0

    if len(img_np.shape) == 3:
        mask_np = np.stack([mask_np, mask_np, mask_np], axis=-1)

    result = np.concatenate([
        img_np,
        (mask_np * 255).astype(np.uint8)
    ], axis=-1)

    return PILImage.fromarray(result, mode="RGBA")

def create_comparison(img: Image.Image, mask: np.ndarray) -> Image.Image:
    """Create side-by-side comparison image"""
    img_np = np.array(img) / 255.0

    mask_resized = np.array(Image.fromarray((mask * 255).astype(np.uint8)).resize(
        (img_np.shape[1], img_np.shape[0]), Image.LANCZOS
    )) / 255.0

    mask_3ch = np.stack([mask_resized, mask_resized, mask_resized], axis=-1)
    removed = img_np * mask_3ch

    comparison = np.zeros((img_np.shape[0], img_np.shape[1] * 3, 3))
    comparison[:, :img_np.shape[1]] = img_np
    comparison[:, img_np.shape[1]:img_np.shape[1]*2] = np.stack([mask_resized]*3, axis=-1)
    comparison[:, img_np.shape[1]*2:] = removed

    return Image.fromarray((comparison * 255).astype(np.uint8))

uploaded_file = st.file_uploader(
    "Choose an image...",
    type=['jpg', 'jpeg', 'png', 'webp']
)

if uploaded_file is not None:
    img = Image.open(uploaded_file).convert("RGB")

    col1, col2 = st.columns(2)

    with col1:
        st.image(img, caption="Original Image", use_container_width=True)

    with col2:
        with st.spinner("Loading model..."):
            model = load_model()

        if model is not None:
            with st.spinner("Removing background... ⏳"):
                try:
                    device = "cuda" if torch.cuda.is_available() else "cpu"
                    input_tensor = preprocess_image(img).to(device)

                    with torch.no_grad():
                        outputs = model(input_tensor)

                    mask = torch.sigmoid(outputs[3]).squeeze().cpu().numpy()

                    comparison = create_comparison(img, mask)
                    st.image(comparison, caption="Original | Mask | Result", use_container_width=True)

                    result_img = remove_background(model, img)

                    from io import BytesIO
                    buf = BytesIO()
                    result_img.save(buf, format="PNG")
                    buf.seek(0)

                    st.download_button(
                        label="📥 Download Result (PNG with transparency)",
                        data=buf,
                        file_name="background_removed.png",
                        mime="image/png"
                    )

                    st.success("✅ Background removed successfully!")

                    if torch.cuda.is_available():
                        st.info(f"🖥️ GPU: {torch.cuda.get_device_name(0)}")
                    else:
                        st.info("💻 Running on CPU (will be slower)")

                except Exception as e:
                    st.error(f"Error processing image: {e}")
                    
st.markdown("---")
st.markdown("""
### 📝 How to use
1. Upload an image (JPG, PNG, or WebP)
2. Wait for the AI to process it
3. Download the result with transparent background

### ℹ️ About
This app uses **RMBG-2.0** (Robust Background Removal), a state-of-the-art AI model
for removing backgrounds from images. The model is loaded directly from Hugging Face.
""")
