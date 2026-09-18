import io
import os
import base64
from typing import Optional
import cv2
import numpy as np
import torch
from torchvision import transforms
from PIL import Image
import timm

IMG_SIZE = 224
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

CLASS_NAMES = ["counterfeit", "genuine"]

class NotABanknoteError(ValueError):
    """Raised when an uploaded image is determined not to be a banknote."""
    pass

# Transforms identical to notebook val_tfms
transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
])

# Transforms for banknote detector (ImageNet normalization)
detector_transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225])
])

def load_detector_model(weights_path: Optional[str] = None):
    if weights_path is None:
        weights_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "banknote_detector.pth")
    if not os.path.exists(weights_path):
        print(f"[WARNING] Banknote detector weights not found at: {weights_path}")
        return None
    import torchvision.models as tv_models
    import torch.nn as nn
    detector = tv_models.mobilenet_v3_small(weights=None)
    detector.classifier = nn.Sequential(
        nn.Linear(576, 128),
        nn.Hardswish(),
        nn.Dropout(p=0.2),
        nn.Linear(128, 2)
    )
    checkpoint = torch.load(weights_path, map_location=DEVICE)
    detector.load_state_dict(checkpoint)
    detector.to(DEVICE)
    detector.eval()
    return detector

def verify_is_banknote(detector, bgr_image: np.ndarray) -> float:
    """
    Returns probability (0.0 to 1.0) that the image is a banknote.
    """
    if detector is None or bgr_image is None or bgr_image.size == 0:
        return 1.0  # Fallback if detector is unavailable
    try:
        rgb = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2RGB)
        pil_img = Image.fromarray(rgb)
        t = detector_transform(pil_img).unsqueeze(0).to(DEVICE)
        with torch.no_grad():
            out = detector(t)
            probs = torch.softmax(out, dim=1)[0]
        return float(probs[1].item())
    except Exception as e:
        print(f"[WARNING] Detector error: {e}")
        return 1.0

def load_banknote_model(weights_path: str):
    if not os.path.exists(weights_path):
        raise FileNotFoundError(f"Model weights not found at: {weights_path}")
        
    model = timm.create_model("deit_tiny_patch16_224", pretrained=False, num_classes=2)
    checkpoint = torch.load(weights_path, map_location=DEVICE)
    model.load_state_dict(checkpoint)
    model.to(DEVICE)
    model.eval()
    return model

def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]       # top-left
    rect[2] = pts[np.argmax(s)]       # bottom-right
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]    # top-right
    rect[3] = pts[np.argmax(diff)]    # bottom-left
    return rect

def four_point_transform(image, pts):
    rect = order_points(pts)
    (tl, tr, br, bl) = rect

    widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    maxWidth = max(int(widthA), int(widthB))

    heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    maxHeight = max(int(heightA), int(heightB))

    if maxWidth <= 20 or maxHeight <= 20:
        return image

    dst = np.array([
        [0, 0],
        [maxWidth - 1, 0],
        [maxWidth - 1, maxHeight - 1],
        [0, maxHeight - 1]
    ], dtype="float32")

    M = cv2.getPerspectiveTransform(rect, dst)
    return cv2.warpPerspective(image, M, (maxWidth, maxHeight))

def enhance_lighting_clahe(bgr_image: np.ndarray, clip_limit: float = 2.0, tile_size: int = 8) -> np.ndarray:
    """
    Equalizes illumination variations (shadows, warm/cool lighting) while preserving
    color fidelity and enhancing micro-textures on banknotes.
    """
    if bgr_image is None or bgr_image.size == 0:
        return bgr_image
    lab = cv2.cvtColor(bgr_image, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=(tile_size, tile_size))
    l_equalized = clahe.apply(l_channel)
    lab_merged = cv2.merge((l_equalized, a_channel, b_channel))
    return cv2.cvtColor(lab_merged, cv2.COLOR_LAB2BGR)

def detect_and_crop_banknote(image_bgr: np.ndarray):
    """
    Enhanced Stage 1: Isolates banknote from complex scenes/tables using
    bilateral filtering, multi-method contour analysis, aspect-ratio validation,
    4-point perspective rectification, and CLAHE illumination enhancement.
    Returns: (processed_bgr, was_cropped: bool)
    """
    h, w = image_bgr.shape[:2]

    # Downscale for faster and noise-resistant contour search
    max_dim = 900
    scale = 1.0
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        small_bgr = cv2.resize(image_bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
    else:
        small_bgr = image_bgr.copy()

    # 1. Edge-preserving bilateral filter (smooths background grain while keeping note edges sharp)
    filtered = cv2.bilateralFilter(small_bgr, 7, 50, 50)
    gray = cv2.cvtColor(filtered, cv2.COLOR_BGR2GRAY)

    candidates = []

    # 2. Morphological gradient + Otsu thresholding (highlights boundary transitions)
    kernel_grad = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    grad = cv2.morphologyEx(gray, cv2.MORPH_GRADIENT, kernel_grad)
    _, thresh_grad = cv2.threshold(grad, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    thresh_grad = cv2.morphologyEx(thresh_grad, cv2.MORPH_CLOSE, kernel_grad, iterations=2)
    contours_grad, _ = cv2.findContours(thresh_grad, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates.extend(contours_grad)

    # 3. Canny edge detector stream
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(blurred, 30, 120)
    kernel_canny = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dilated = cv2.dilate(edges, kernel_canny, iterations=2)
    contours_canny, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates.extend(contours_canny)

    # 4. Standard Otsu threshold stream
    _, thresh_otsu = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    closed_otsu = cv2.morphologyEx(thresh_otsu, cv2.MORPH_CLOSE, kernel_canny, iterations=2)
    contours_otsu, _ = cv2.findContours(closed_otsu, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates.extend(contours_otsu)

    small_area = small_bgr.shape[0] * small_bgr.shape[1]
    best_poly = None
    best_area = 0

    for cnt in candidates:
        area = cv2.contourArea(cnt)
        # Banknote should occupy between 5% and 95% of the frame
        if area < 0.05 * small_area or area > 0.95 * small_area:
            continue

        rect = cv2.minAreaRect(cnt)
        (rw, rh) = rect[1]
        if rw <= 10 or rh <= 10:
            continue

        # Aspect ratio filter: accommodate perspective foreshortening & camera angles (~1.15 to 3.2)
        aspect = max(rw, rh) / min(rw, rh)
        if not (1.15 <= aspect <= 3.2):
            continue

        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.025 * peri, True)

        # Primary preference: strictly 4-corner convex polygon
        if len(approx) == 4 and cv2.isContourConvex(approx):
            if area > best_area:
                best_area = area
                best_poly = approx.reshape(4, 2)
        else:
            # Fallback: oriented bounding box if contour fills at least 65% of minimum area box
            box_area = rw * rh
            if box_area > 0 and (area / box_area) > 0.65:
                if area > best_area:
                    best_area = area
                    best_poly = cv2.boxPoints(rect)

    if best_poly is not None:
        orig_pts = best_poly / scale
        cropped_bgr = four_point_transform(image_bgr, orig_pts)
        ch, cw = cropped_bgr.shape[:2]
        if ch > 20 and cw > 20:
            # Ensure standard horizontal banknote orientation (width >= height)
            if ch > cw:
                cropped_bgr = cv2.rotate(cropped_bgr, cv2.ROTATE_90_CLOCKWISE)
            # Apply CLAHE lighting normalization
            enhanced_crop = enhance_lighting_clahe(cropped_bgr)
            return enhanced_crop, True

    # If no distinct note boundary detected, return lighting-normalized original image
    return enhance_lighting_clahe(image_bgr), False

def process_banknote_image(image_bytes: bytes, detector=None):
    """
    Takes image bytes, verifies whether the image is actually a banknote,
    isolates banknote from table background if present,
    prepares the PyTorch tensor, and returns base64 thumbnail of the cropped note.
    """
    nparr = np.frombuffer(image_bytes, np.uint8)
    img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if img_bgr is None:
        raise ValueError("Could not decode image.")

    cropped_bgr, was_cropped = detect_and_crop_banknote(img_bgr)

    # Verify that the image is actually a banknote
    if detector is not None:
        prob_crop = verify_is_banknote(detector, cropped_bgr)
        prob_orig = verify_is_banknote(detector, img_bgr)
        banknote_confidence = max(prob_crop, prob_orig)
        if banknote_confidence < 0.45:
            raise NotABanknoteError("Please upload a bank note")

    # Convert to RGB PIL Image
    img_rgb = cv2.cvtColor(cropped_bgr, cv2.COLOR_BGR2RGB)
    pil_image = Image.fromarray(img_rgb)

    # Model input tensor
    tensor = transform(pil_image).unsqueeze(0).to(DEVICE)

    # Convert cropped image to base64 for frontend preview
    _, buffer = cv2.imencode(".jpg", cropped_bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
    b64_str = base64.b64encode(buffer).decode("utf-8")
    data_url = f"data:image/jpeg;base64,{b64_str}"

    return tensor, data_url, was_cropped