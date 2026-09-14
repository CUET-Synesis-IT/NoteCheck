@echo off
echo ========================================================
echo Starting Banknote Counterfeit Detection Web Application
echo ========================================================
echo [1/2] Launching FastAPI Backend on http://127.0.0.1:8000 ...
start "FastAPI Backend" cmd /k "cd /d %~dp0backend & call venv\Scripts\activate & uvicorn main:app --reload --host 127.0.0.1 --port 8000"
echo [2/2] Launching React Frontend on http://localhost:5173 ...
start "React Frontend" cmd /k "cd /d %~dp0frontend & npm run dev"
echo.
echo Both servers have been launched in separate windows!
echo Frontend UI: http://localhost:5173
echo Backend API Docs: http://127.0.0.1:8000/docs
echo ========================================================
pause
