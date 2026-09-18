# Deploying NoteCheck to Render 🚀

This guide provides step-by-step instructions to deploy **NoteCheck** (both FastAPI backend and React frontend) to [Render](https://render.com).

---

## 🌟 Method 1: One-Click Blueprint Deployment (Recommended)

Render can automatically read the [`render.yaml`](../render.yaml) file in this repository to configure both the Backend and Frontend with the correct Python version, build commands, and routing rules.

### Steps:
1. Push this repository to GitHub (or use your existing repo: `https://github.com/CUET-Synesis-IT/NoteCheck`).
2. Log in to [Render Dashboard](https://dashboard.render.com).
3. Click **New +** in the top navigation and select **Blueprint**.
4. Connect your GitHub account and select the **NoteCheck** repository.
5. Render will automatically detect the two services declared in `render.yaml`:
   * **`notecheck-backend`** (Python Web Service)
   * **`notecheck-frontend`** (Static Site)
6. Click **Apply**.
7. Once `notecheck-backend` finishes deploying, copy its URL (e.g., `https://notecheck-backend.onrender.com`).
8. Go to `notecheck-frontend` -> **Environment** tab:
   * Set `VITE_API_BASE` = `https://notecheck-backend.onrender.com` (your backend URL).
   * Click **Save Changes** (this triggers an automatic rebuild of the frontend with the live backend URL).

---

## 🛠️ Method 2: Manual Deployment

If you prefer to configure services manually in the Render dashboard:

### Step A: Deploy Backend (FastAPI)
1. In Render Dashboard, click **New +** -> **Web Service**.
2. Select your repository.
3. Configure settings:
   * **Name**: `notecheck-backend`
   * **Region**: Choose closest to you (e.g., Oregon or Frankfurt)
   * **Branch**: `main`
   * **Root Directory**: `backend`
   * **Runtime**: `Python 3`
   * **Build Command**:
     ```bash
     pip install --upgrade pip && pip install --extra-index-url https://download.pytorch.org/whl/cpu torch torchvision && pip install -r requirements.txt
     ```
   * **Start Command**:
     ```bash
     uvicorn main:app --host 0.0.0.0 --port $PORT
     ```
   * **Plan**: `Free`
4. Expand **Advanced**:
   * **Health Check Path**: `/health`
   * **Add Environment Variable**:
     * `PYTHON_VERSION`: `3.10.12`
5. Click **Create Web Service**.
6. Wait for the build to finish. Verify by opening `https://<your-backend-url>.onrender.com/health`. It should return:
   ```json
   {"status": "online", "model_loaded": true, "model_path": "..."}
   ```

---

### Step B: Deploy Frontend (React + Vite)
1. In Render Dashboard, click **New +** -> **Static Site**.
2. Select your repository.
3. Configure settings:
   * **Name**: `notecheck-frontend`
   * **Branch**: `main`
   * **Root Directory**: `frontend`
   * **Build Command**:
     ```bash
     npm install && npm run build
     ```
   * **Publish Directory**: `dist`
4. Under **Environment Variables**, add:
   * **Key**: `VITE_API_BASE`
   * **Value**: `https://<your-backend-url>.onrender.com` (from Step A)
5. Under **Redirects/Rewrites**, add:
   * **Source**: `/*`
   * **Destination**: `/index.html`
   * **Action**: `Rewrite`
6. Click **Create Static Site**.

---

## ⚡ Important Notes for Render Free Tier

1. **CPU PyTorch Optimization**:
   * Standard PyTorch with CUDA is over 2.5 GB and will exceed Render Free Tier build memory and time limits.
   * The build command uses `--extra-index-url https://download.pytorch.org/whl/cpu` to install the lightweight ~170MB CPU build, running comfortably within Render's 512MB RAM free tier.

2. **Free Tier Cold Starts**:
   * Render Free Web Services sleep after 15 minutes of inactivity.
   * The first scan after sleep may take ~30–50 seconds to wake up the backend server. Subsequent scans will be sub-second (~100–300 ms).

3. **Default Admin Login**:
   * **Email**: `admin@jaaltaka.com`
   * **Password**: `Admin123!`
