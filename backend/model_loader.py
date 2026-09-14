import io
import os
import base64
import cv2
import numpy as np
import torch
from torchvision import transforms
from PIL import Image
import timm

IMG_SIZE = 224
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

CLASS_NAMES = ["counterfeit", "genuine"]

# Transforms identical to notebook val_tfms
transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5])
])

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

def detect_and_crop_banknote(image_bgr: np.ndarray):
    """
    Detects the banknote within a scene (e.g. on a table) using edge/contour analysis.
    Returns: (cropped_bgr, was_cropped: bool)
    """
    h, w = image_bgr.shape[:2]
    total_area = h * w

    # Downscale for faster, noise-resistant contour search
    max_dim = 900
    scale = 1.0
    if max(h, w) > max_dim:
        scale = max_dim / max(h, w)
        small_bgr = cv2.resize(image_bgr, (int(w * scale), int(h * scale)))
    else:
        small_bgr = image_bgr.copy()

    gray = cv2.cvtColor(small_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)

    candidates = []

    # 1. Canny edge detector
    edges = cv2.Canny(blurred, 30, 120)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dilated = cv2.dilate(edges, kernel, iterations=2)
    contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates.extend(contours)

    # 2. Otsu threshold
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    closed = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel, iterations=2)
    contours_otsu, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    candidates.extend(contours_otsu)

    small_area = small_bgr.shape[0] * small_bgr.shape[1]
    best_poly = None
    best_area = 0

    for cnt in candidates:
        area = cv2.contourArea(cnt)
        # Banknote should be between 5% and 94% of the image
        if area < 0.05 * small_area or area > 0.94 * small_area:
            continue

        peri = cv2.arcLength(cnt, True)
        approx = cv2.approxPolyDP(cnt, 0.025 * peri, True)

        if len(approx) == 4 and cv2.isContourConvex(approx):
            if area > best_area:
                best_area = area
                best_poly = approx.reshape(4, 2)
        else:
            rect = cv2.minAreaRect(cnt)
            box_area = rect[1][0] * rect[1][1]
            if box_area > 0 and (area / box_area) > 0.60:
                if area > best_area:
                    best_area = area
                    best_poly = cv2.boxPoints(rect)

    if best_poly is not None:
        orig_pts = best_poly / scale
        cropped_bgr = four_point_transform(image_bgr, orig_pts)
        ch, cw = cropped_bgr.shape[:2]
        if ch > 20 and cw > 20:
            # Rotate if vertically oriented to standard horizontal banknote orientation
            if ch > cw:
                cropped_bgr = cv2.rotate(cropped_bgr, cv2.ROTATE_90_CLOCKWISE)
            return cropped_bgr, True

    return image_bgr, False

def process_banknote_image(image_bytes: bytes):
    """
    Takes image bytes, isolates banknote from table background if present,
    prepares the PyTorch tensor, and returns base64 thumbnail of the cropped note.
    """
    nparr = np.frombuffer(image_bytes, np.uint8)
    img_bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    if img_bgr is None:
        raise ValueError("Could not decode image.")

    cropped_bgr, was_cropped = detect_and_crop_banknote(img_bgr)

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