# NoteCheck 💵🔍

> **AI-Powered Banknote Counterfeit Detection System**  
> An end-to-end deep learning and computer vision platform designed to detect genuine vs. counterfeit currency using Vision Transformers (DeiT), automated perspective rectification, a FastAPI REST service, and an interactive React web dashboard.

---

## 📌 Overview

**NoteCheck** leverages state-of-the-art Vision Transformers (DeiT) to analyze visual patterns, micro-printing, and security textures on banknotes. The system includes an automated computer vision pipeline that isolates banknotes from busy backgrounds, rectifies their angle via 4-point perspective warping, and delivers real-time counterfeit verification with ~97.88% accuracy.

![Methodology](final_methodology_figure.png)

---

## ✨ Key Features

- 🧠 **DeiT Transformer Backbone**: Utilizes `deit_tiny_patch16_224` fine-tuned for high-precision banknote authentication.
- 📐 **Automated Note Localization & Crop**: Built-in OpenCV pipeline applying Canny edge detection, Otsu thresholding, and 4-point perspective transformation to isolate banknotes from desk or background clutter.
- ⚡ **FastAPI High-Performance Backend**: RESTful API endpoints for instant single and batch inference, scan history, and statistics.
- 🔐 **Authentication & Security**: Integrated JWT token-based authentication and role-based access control (Admin / User) with hashed passwords.
- 💻 **Modern React Dashboard**: Built with React 18, Vite, and Tailwind CSS featuring drag-and-drop image uploads, live cropped note previews, and confidence scoring.
- 📊 **Research & Reproducibility**: Includes full training notebooks (`counterfeit-detection-accuracy-97-88.ipynb`), confusion matrix, and ROC curve evaluations.

---

## 🏗️ System Architecture

```text
User Image ────────► OpenCV Preprocessing ────────► DeiT Vision Transformer
 (Upload)             • Edge & Contour Detection         • Patch Extraction
                      • Perspective Warping              • Transformer Blocks
                      • Horizontal Auto-rotation         • Binary Classification
                                                                │
                                                                ▼
                     React Web Dashboard  ◄──────────── FastAPI Server
                     • Real-time Result                 • Prediction & Confidence
                     • Cropped Preview                  • Database Scan History
                     • Security Analysis                • JWT Auth Endpoints
```

---

## 📁 Repository Structure

```text
NoteCheck/
├── backend/
│   ├── models/
│   │   └── best_deit.pth          # Pretrained DeiT PyTorch model weights
│   ├── auth.py                    # JWT authentication & password hashing
│   ├── database.py                # SQLAlchemy ORM models & database setup
│   ├── main.py                    # FastAPI application & REST endpoints
│   ├── model_loader.py            # OpenCV preprocessing & DeiT inference engine
│   └── requirements.txt           # Python dependencies
├── frontend/
│   ├── src/                       # React frontend source code (App.jsx, main.jsx)
│   ├── public/                    # Static assets & icons
│   ├── index.html                 # Vite HTML entry point
│   ├── package.json               # Node.js dependencies & scripts
│   └── vite.config.js             # Vite build configuration
├── counterfeit-detection-accuracy-97-88.ipynb  # Model training & evaluation notebook
├── Counterfeit_Banknote_Detection_1.pdf        # Research paper documentation
├── IEEE_Counterfeit_Detection_Paper.docx       # Publication draft
├── CM.png                         # Confusion Matrix
├── ROC.png                        # ROC Curve
├── final_methodology_figure.png   # Architectural methodology diagram
├── run_app.bat                    # One-click Windows launch script
└── README.md                      # Project documentation
```

---

## 🚀 Quick Start Guide

### Prerequisites
- **Python** 3.10+
- **Node.js** 18+ and **npm**
- **Git**

---

### Option 1: One-Click Windows Launch
If you are on Windows, simply double-click:
```cmd
run_app.bat
```
This activates the backend and launches the React development server concurrently.

---

### Option 2: Manual Setup

#### 1. Backend Setup
```bash
cd backend

# Create and activate a virtual environment
python -m venv venv
# On Windows:
venv\Scripts\activate
# On Linux/macOS:
# source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run the FastAPI server
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```
API Documentation will be live at `http://127.0.0.1:8000/docs`.

#### 2. Frontend Setup
```bash
cd frontend

# Install Node dependencies
npm install

# Start Vite development server
npm run dev
```
The React UI will be live at `http://localhost:5173`.

---

## 📊 Model Performance

| Metric | Score |
| :--- | :--- |
| **Model Architecture** | Data-efficient Image Transformer (`deit_tiny_patch16_224`) |
| **Validation Accuracy** | **97.88%** |
| **Input Resolution** | 224 x 224 px |
| **Classes** | Genuine / Counterfeit |

---

## 🛡️ License

This project is licensed under the MIT License. Feel free to use and adapt for academic and practical applications.
