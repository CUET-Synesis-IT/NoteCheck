import React, { useState, useEffect, useRef } from "react";

const API_BASE = "http://127.0.0.1:8000";

export default function App() {
  const [selectedFile, setSelectedFile] = useState(null);
  const [previewUrl, setPreviewUrl] = useState(null);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [backendOnline, setBackendOnline] = useState(null);
  const [isDragging, setIsDragging] = useState(false);
  const [viewTab, setViewTab] = useState("cropped"); // "cropped" or "original"
  const fileInputRef = useRef(null);
  // --- auth state ---
  const [token, setToken] = useState(() => localStorage.getItem("jaaltaka_token") || "");
  const [refreshToken, setRefreshToken] = useState(() => localStorage.getItem("jaaltaka_refresh_token") || "");
  const [user, setUser] = useState(() => {
    try { return JSON.parse(localStorage.getItem("jaaltaka_user") || "null"); } catch { return null; }
  });
  const [authMode, setAuthMode] = useState("login"); // login | register
  const [authForm, setAuthForm] = useState({ name: "", email: "", password: "" });
  const [authLoading, setAuthLoading] = useState(false);
  const [history, setHistory] = useState([]);
  const [adminStats, setAdminStats] = useState(null);

  useEffect(() => {
    checkHealth();
    const interval = setInterval(checkHealth, 5000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (token) {
      fetchMe();
      fetchHistory();
    }
    // eslint-disable-next-line
  }, [token]);

  const authHeaders = (t = token) => ({ Authorization: `Bearer ${t}` });

  const refreshTokens = async () => {
    const curRefresh = localStorage.getItem("jaaltaka_refresh_token");
    if (!curRefresh) {
      logout();
      return null;
    }
    try {
      const res = await fetch(`${API_BASE}/auth/refresh`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: curRefresh }),
      });
      if (!res.ok) {
        logout();
        return null;
      }
      const data = await res.json();
      setToken(data.access_token);
      setRefreshToken(data.refresh_token);
      localStorage.setItem("jaaltaka_token", data.access_token);
      localStorage.setItem("jaaltaka_refresh_token", data.refresh_token);
      return data.access_token;
    } catch {
      logout();
      return null;
    }
  };

  const authFetch = async (url, options = {}) => {
    let currentTok = token || localStorage.getItem("jaaltaka_token");
    const headers = {
      ...(options.headers || {}),
      Authorization: `Bearer ${currentTok}`,
    };
    let res = await fetch(url, { ...options, headers });
    if (res.status === 401) {
      const newTok = await refreshTokens();
      if (newTok) {
        const retryHeaders = {
          ...(options.headers || {}),
          Authorization: `Bearer ${newTok}`,
        };
        res = await fetch(url, { ...options, headers: retryHeaders });
      }
    }
    return res;
  };

  const checkHealth = async () => {
    try {
      const res = await fetch(`${API_BASE}/health`);
      if (res.ok) {
        const data = await res.json();
        setBackendOnline(data.model_loaded ? "ready" : "no-model");
      } else {
        setBackendOnline("offline");
      }
    } catch {
      setBackendOnline("offline");
    }
  };

  const saveSession = (tok, refTok, usr) => {
    setToken(tok);
    if (refTok) {
      setRefreshToken(refTok);
      localStorage.setItem("jaaltaka_refresh_token", refTok);
    }
    setUser(usr);
    localStorage.setItem("jaaltaka_token", tok);
    localStorage.setItem("jaaltaka_user", JSON.stringify(usr));
  };

  const logout = () => {
    setToken("");
    setRefreshToken("");
    setUser(null);
    setHistory([]);
    setAdminStats(null);
    localStorage.removeItem("jaaltaka_token");
    localStorage.removeItem("jaaltaka_refresh_token");
    localStorage.removeItem("jaaltaka_user");
  };

  const fetchMe = async () => {
    try {
      const res = await authFetch(`${API_BASE}/auth/me`);
      if (res.status === 401) { logout(); return; }
      if (res.ok) {
        const me = await res.json();
        setUser(me);
        localStorage.setItem("jaaltaka_user", JSON.stringify(me));
        if (me.role === "admin") fetchAdminStats();
      }
    } catch { /* ignore */ }
  };

  const fetchHistory = async () => {
    try {
      const res = await authFetch(`${API_BASE}/history?limit=10`);
      if (res.ok) setHistory(await res.json());
    } catch { /* ignore */ }
  };

  const fetchAdminStats = async () => {
    try {
      const res = await authFetch(`${API_BASE}/admin/overview`);
      if (res.ok) setAdminStats(await res.json());
    } catch { /* ignore */ }
  };

  const handleAuth = async (e) => {
    e?.preventDefault();
    setAuthLoading(true);
    setError(null);
    try {
      const endpoint = authMode === "login" ? "/auth/login" : "/auth/register";
      const body = authMode === "login"
        ? { email: authForm.email, password: authForm.password }
        : { name: authForm.name, email: authForm.email, password: authForm.password };
      const res = await fetch(`${API_BASE}${endpoint}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.detail || "Authentication failed");
      saveSession(data.access_token, data.refresh_token, data.user);
      fetchHistory();
      if (data.user?.role === "admin") fetchAdminStats();
    } catch (err) {
      setError(err.message);
    } finally {
      setAuthLoading(false);
    }
  };

  const processFile = (file) => {
    if (!file || !file.type.startsWith("image/")) {
      setError("Please select a valid image file (JPG, PNG, WebP)");
      return;
    }
    setSelectedFile(file);
    setPreviewUrl(URL.createObjectURL(file));
    setResult(null);
    setError(null);
    setViewTab("cropped");
  };

  const handleFileChange = (e) => {
    if (e.target.files && e.target.files[0]) {
      processFile(e.target.files[0]);
    }
  };

  const handleDragOver = (e) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = () => {
    setIsDragging(false);
  };

  const handleDrop = (e) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      processFile(e.dataTransfer.files[0]);
    }
  };

  const handleAnalyze = async () => {
    if (!selectedFile) return;
    if (!token) { setError("Please login first."); return; }

    setLoading(true);
    setError(null);

    const formData = new FormData();
    formData.append("file", selectedFile);

    try {
      const response = await authFetch(`${API_BASE}/predict`, {
        method: "POST",
        body: formData,
      });

      if (response.status === 401) {
        logout();
        throw new Error("Session expired. Please login again.");
      }

      if (!response.ok) {
        const errData = await response.json().catch(() => ({}));
        throw new Error(errData.detail || `Server error (${response.status})`);
      }

      const data = await response.json();
      setResult(data);
      if (data.note_detected_and_cropped) {
        setViewTab("cropped");
      }
      fetchHistory();
      if (user?.role === "admin") fetchAdminStats();
    } catch (err) {
      setError(err.message || "Failed to analyze banknote image");
    } finally {
      setLoading(false);
    }
  };

  const resetAll = () => {
    setSelectedFile(null);
    setPreviewUrl(null);
    setResult(null);
    setError(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
  };

  const isGenuine = result?.prediction?.toLowerCase() === "genuine";

  return (
    <div style={styles.page}>
      {/* Header Bar */}
      <header style={styles.header}>
        <div style={styles.headerInner}>
          <div style={styles.brand}>
            <span style={styles.logoIcon}>🛡️</span>
            <div>
              <h1 style={styles.appTitle}>Banknote Authenticator</h1>
              <span style={styles.appBadge}>
                DeiT Vision Transformer • Background/Table Auto-Crop • 97.88% Accuracy
              </span>
            </div>
          </div>

          <div style={{ display: "flex", gap: "10px", alignItems: "center" }}>
          <div style={styles.statusIndicator}>
            <span
              style={{
                ...styles.statusDot,
                backgroundColor:
                  backendOnline === "ready"
                    ? "#10b981"
                    : backendOnline === "no-model"
                    ? "#f59e0b"
                    : "#ef4444",
              }}
            />
            <span style={styles.statusText}>
              {backendOnline === "ready"
                ? "Model Ready"
                : backendOnline === "no-model"
                ? "Loading Model..."
                : "FastAPI Offline"}
            </span>
          </div>
          {user && (
            <div style={styles.statusIndicator}>
              <span style={styles.statusText}>
                👤 {user.name} ({user.role})
              </span>
              <button onClick={logout} style={styles.logoutBtn}>Logout</button>
            </div>
          )}
          </div>
        </div>
      </header>

      {/* Auth gate */}
      {!user ? (
      <main style={styles.container}>
        <div style={{ ...styles.card, maxWidth: "420px", margin: "0 auto" }}>
          <h2 style={styles.cardTitle}>{authMode === "login" ? "Login to JaalTaka" : "Create account"}</h2>
          <p style={styles.cardDesc}>
            {authMode === "login"
              ? "Login to verify banknotes. Default admin: admin@jaaltaka.com / Admin123!"
              : "Register as user. Admin promotes to staff/admin."}
          </p>
          <form onSubmit={handleAuth} style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
            {authMode === "register" && (
              <input placeholder="Full name" value={authForm.name}
                onChange={(e) => setAuthForm({ ...authForm, name: e.target.value })}
                style={styles.input} required minLength={2} />
            )}
            <input placeholder="Email" type="email" value={authForm.email}
              onChange={(e) => setAuthForm({ ...authForm, email: e.target.value })}
              style={styles.input} required />
            <input placeholder="Password (min 6)" type="password" value={authForm.password}
              onChange={(e) => setAuthForm({ ...authForm, password: e.target.value })}
              style={styles.input} required minLength={6} />
            <button type="submit" disabled={authLoading || backendOnline !== "ready"}
              style={{ ...styles.btn, ...styles.btnPrimary, opacity: authLoading ? 0.6 : 1 }}>
              {authLoading ? "Please wait..." : authMode === "login" ? "Login" : "Register"}
            </button>
          </form>
          <button onClick={() => setAuthMode(authMode === "login" ? "register" : "login")}
            style={styles.linkBtn}>
            {authMode === "login" ? "No account? Register" : "Have account? Login"}
          </button>
          {error && <div style={styles.errorBox}>⚠️ {error}</div>}
        </div>
      </main>
      ) : (
      <main style={styles.container}>
        <div style={styles.grid}>
          {/* Upload & Preview Card */}
          <div style={styles.card}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <h2 style={styles.cardTitle}>Banknote Photo</h2>
              {result?.note_detected_and_cropped && (
                <span style={styles.cropBadge}>✂️ Background Removed</span>
              )}
            </div>
            <p style={styles.cardDesc}>
              Upload any photo—even on a table, desk, or floor. Background clutter is automatically cropped out.
            </p>

            <input
              type="file"
              ref={fileInputRef}
              accept="image/*"
              style={{ display: "none" }}
              onChange={handleFileChange}
            />

            {!previewUrl ? (
              <div
                style={{
                  ...styles.dropzone,
                  borderColor: isDragging ? "#38bdf8" : "#334155",
                  backgroundColor: isDragging ? "#0f2744" : "#1e293b",
                }}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
                onClick={() => fileInputRef.current?.click()}
              >
                <div style={styles.dropzoneContent}>
                  <div style={styles.uploadIcon}>💵</div>
                  <h3 style={styles.dropTitle}>Click to upload or drag & drop</h3>
                  <p style={styles.dropSub}>Phone photos with tables, floors, or scans accepted</p>
                </div>
              </div>
            ) : (
              <div style={styles.previewContainer}>
                {/* View Switcher if cropped */}
                {result?.note_detected_and_cropped && (
                  <div style={styles.tabContainer}>
                    <button
                      onClick={() => setViewTab("cropped")}
                      style={{
                        ...styles.tabBtn,
                        ...(viewTab === "cropped" ? styles.tabBtnActive : {}),
                      }}
                    >
                      ✂️ Isolated Banknote (Analyzed)
                    </button>
                    <button
                      onClick={() => setViewTab("original")}
                      style={{
                        ...styles.tabBtn,
                        ...(viewTab === "original" ? styles.tabBtnActive : {}),
                      }}
                    >
                      📷 Original Photo
                    </button>
                  </div>
                )}

                <div style={styles.imageWrapper}>
                  <img
                    src={
                      viewTab === "cropped" && result?.cropped_banknote_base64
                        ? result.cropped_banknote_base64
                        : previewUrl
                    }
                    alt="Banknote Preview"
                    style={styles.previewImg}
                  />
                  {loading && <div className="scan-line" />}
                </div>

                <div style={styles.actionButtons}>
                  <button
                    onClick={handleAnalyze}
                    disabled={loading || backendOnline !== "ready"}
                    style={{
                      ...styles.btn,
                      ...styles.btnPrimary,
                      opacity: loading || backendOnline !== "ready" ? 0.6 : 1,
                      cursor: loading || backendOnline !== "ready" ? "not-allowed" : "pointer",
                    }}
                  >
                    {loading ? "Detecting & Verifying Note..." : "Verify Authenticity"}
                  </button>
                  <button onClick={resetAll} disabled={loading} style={styles.btnSecondary}>
                    Replace Photo
                  </button>
                </div>
              </div>
            )}

            {error && (
              <div style={styles.errorBox}>
                <span>⚠️ {error}</span>
              </div>
            )}
          </div>

          {/* Analysis Result Card */}
          <div style={styles.card}>
            <h2 style={styles.cardTitle}>AI Inspection & Verdict</h2>
            <p style={styles.cardDesc}>
              DeiT classification performed on the isolated banknote features.
            </p>

            {!result && !loading && (
              <div style={styles.emptyState}>
                <div style={styles.emptyIcon}>🔍</div>
                <h3 style={styles.emptyTitle}>Awaiting Banknote</h3>
                <p style={styles.emptyText}>
                  Upload an image and click "Verify Authenticity" to automatically isolate the note and inspect.
                </p>
              </div>
            )}

            {loading && (
              <div style={styles.loadingState}>
                <div style={styles.spinner} />
                <p style={{ marginTop: "16px", color: "#94a3b8" }}>
                  Detecting banknote contours & extracting transformer patches...
                </p>
              </div>
            )}

            {result && !loading && (
              <div style={styles.resultContainer}>
                {/* Result Banner */}
                <div
                  style={{
                    ...styles.verdictBanner,
                    backgroundColor: isGenuine ? "rgba(16, 185, 129, 0.15)" : "rgba(239, 68, 68, 0.15)",
                    borderColor: isGenuine ? "#10b981" : "#ef4444",
                    color: isGenuine ? "#34d399" : "#f87171",
                  }}
                >
                  <span style={{ fontSize: "28px" }}>{isGenuine ? "✅" : "🚨"}</span>
                  <div>
                    <h3 style={styles.verdictTitle}>
                      {isGenuine ? "GENUINE BANKNOTE" : "COUNTERFEIT DETECTED"}
                    </h3>
                    <p style={styles.verdictSub}>
                      Confidence: {(result.confidence * 100).toFixed(2)}%
                    </p>
                  </div>
                </div>

                {/* Auto Crop Notice */}
                <div
                  style={{
                    ...styles.cropNotice,
                    backgroundColor: result.note_detected_and_cropped
                      ? "rgba(56, 189, 248, 0.1)"
                      : "rgba(100, 116, 139, 0.1)",
                    borderColor: result.note_detected_and_cropped ? "#0284c7" : "#475569",
                  }}
                >
                  <span style={{ fontSize: "18px" }}>
                    {result.note_detected_and_cropped ? "🎯" : "ℹ️"}
                  </span>
                  <span style={{ fontSize: "0.85rem", color: "#e2e8f0" }}>
                    {result.note_detected_and_cropped
                      ? "Banknote detected on surface: Table and background objects were automatically cropped out before analysis."
                      : "Direct close-up banknote analyzed."}
                  </span>
                </div>

                {/* Probability Breakdown */}
                <div style={styles.section}>
                  <h4 style={styles.sectionTitle}>Confidence Distribution</h4>

                  <div style={styles.metricRow}>
                    <div style={styles.metricHeader}>
                      <span>Genuine Confidence</span>
                      <strong>{(result.probabilities.genuine * 100).toFixed(2)}%</strong>
                    </div>
                    <div style={styles.barBackground}>
                      <div
                        style={{
                          ...styles.barFill,
                          width: `${result.probabilities.genuine * 100}%`,
                          backgroundColor: "#10b981",
                        }}
                      />
                    </div>
                  </div>

                  <div style={{ ...styles.metricRow, marginTop: "14px" }}>
                    <div style={styles.metricHeader}>
                      <span>Counterfeit Confidence</span>
                      <strong>{(result.probabilities.counterfeit * 100).toFixed(2)}%</strong>
                    </div>
                    <div style={styles.barBackground}>
                      <div
                        style={{
                          ...styles.barFill,
                          width: `${result.probabilities.counterfeit * 100}%`,
                          backgroundColor: "#ef4444",
                        }}
                      />
                    </div>
                  </div>
                </div>

                {/* Metadata details */}
                <div style={styles.metaGrid}>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Inference Latency</span>
                    <span style={styles.metaValue}>{result.inference_time_ms} ms</span>
                  </div>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>ROI Extraction</span>
                    <span style={styles.metaValue}>
                      {result.note_detected_and_cropped ? "Auto Cropped" : "Full Frame"}
                    </span>
                  </div>
                </div>
                {result.scan_id && (
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Saved Scan ID (DB)</span>
                    <span style={styles.metaValue}>#{result.scan_id} • {user?.email}</span>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* History + Admin */}
        <div style={{ ...styles.grid, marginTop: "24px" }}>
          <div style={styles.card}>
            <h2 style={styles.cardTitle}>My Recent Scans</h2>
            <p style={styles.cardDesc}>Stored in backend DB per user.</p>
            {history.length === 0 ? (
              <p style={styles.emptyText}>No scans yet.</p>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {history.map((h) => (
                  <div key={h.id} style={styles.historyRow}>
                    <span>#{h.id}</span>
                    <strong style={{ color: h.prediction === "genuine" ? "#34d399" : "#f87171" }}>
                      {h.prediction}
                    </strong>
                    <span>{(h.confidence * 100).toFixed(1)}%</span>
                    <span style={{ color: "#64748b", fontSize: "0.75rem" }}>
                      {new Date(h.created_at).toLocaleString()}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
          {user?.role === "admin" && (
            <div style={styles.card}>
              <h2 style={styles.cardTitle}>Admin Overview</h2>
              <p style={styles.cardDesc}>GET /admin/overview (admin only)</p>
              {!adminStats ? (
                <p style={styles.emptyText}>Loading stats...</p>
              ) : (
                <div style={styles.metaGrid}>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Total Scans</span>
                    <span style={styles.metaValue}>{adminStats.total_scans}</span>
                  </div>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Fake Rate</span>
                    <span style={styles.metaValue}>{(adminStats.fake_rate * 100).toFixed(1)}%</span>
                  </div>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Users</span>
                    <span style={styles.metaValue}>{adminStats.total_users}</span>
                  </div>
                  <div style={styles.metaBox}>
                    <span style={styles.metaLabel}>Fakes</span>
                    <span style={styles.metaValue}>{adminStats.fake_count}</span>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </main>
      )}
    </div>
  );
}

const styles = {
  page: { minHeight: "100vh", display: "flex", flexDirection: "column" },
  header: {
    backgroundColor: "rgba(15, 23, 42, 0.8)",
    backdropFilter: "blur(12px)",
    borderBottom: "1px solid #334155",
    padding: "16px 24px",
  },
  headerInner: {
    maxWidth: "1100px",
    margin: "0 auto",
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
  },
  brand: { display: "flex", alignItems: "center", gap: "14px" },
  logoIcon: { fontSize: "32px" },
  appTitle: { fontSize: "1.4rem", fontWeight: "700", color: "#f8fafc" },
  appBadge: { fontSize: "0.78rem", color: "#38bdf8", fontWeight: "500" },
  statusIndicator: {
    display: "flex",
    alignItems: "center",
    gap: "8px",
    backgroundColor: "#1e293b",
    padding: "6px 14px",
    borderRadius: "20px",
    border: "1px solid #334155",
  },
  statusDot: { width: "10px", height: "10px", borderRadius: "50%" },
  statusText: { fontSize: "0.82rem", color: "#cbd5e1" },
  container: { maxWidth: "1100px", margin: "40px auto", padding: "0 20px", flex: 1, width: "100%" },
  grid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(320px, 1fr))",
    gap: "24px",
  },
  card: {
    backgroundColor: "#1e293b",
    border: "1px solid #334155",
    borderRadius: "16px",
    padding: "24px",
    display: "flex",
    flexDirection: "column",
  },
  cardTitle: { fontSize: "1.2rem", color: "#f8fafc", marginBottom: "6px" },
  cardDesc: { fontSize: "0.88rem", color: "#94a3b8", marginBottom: "20px" },
  cropBadge: {
    backgroundColor: "#0284c7",
    color: "#e0f2fe",
    fontSize: "0.75rem",
    fontWeight: "600",
    padding: "3px 10px",
    borderRadius: "12px",
  },
  dropzone: {
    border: "2px dashed #334155",
    borderRadius: "12px",
    padding: "48px 20px",
    textAlign: "center",
    cursor: "pointer",
    transition: "all 0.2s ease",
  },
  dropzoneContent: { display: "flex", flexDirection: "column", alignItems: "center" },
  uploadIcon: { fontSize: "48px", marginBottom: "12px" },
  dropTitle: { fontSize: "1rem", color: "#f1f5f9", marginBottom: "4px" },
  dropSub: { fontSize: "0.8rem", color: "#64748b" },
  previewContainer: { display: "flex", flexDirection: "column", gap: "16px" },
  tabContainer: {
    display: "flex",
    gap: "8px",
    backgroundColor: "#0f172a",
    padding: "4px",
    borderRadius: "8px",
    border: "1px solid #334155",
  },
  tabBtn: {
    flex: 1,
    padding: "8px 12px",
    fontSize: "0.8rem",
    fontWeight: "600",
    border: "none",
    borderRadius: "6px",
    backgroundColor: "transparent",
    color: "#94a3b8",
    cursor: "pointer",
    transition: "all 0.2s",
  },
  tabBtnActive: {
    backgroundColor: "#1e293b",
    color: "#38bdf8",
    boxShadow: "0 2px 4px rgba(0,0,0,0.3)",
  },
  imageWrapper: {
    position: "relative",
    borderRadius: "10px",
    overflow: "hidden",
    border: "1px solid #334155",
    backgroundColor: "#0f172a",
    display: "flex",
    justifyContent: "center",
    minHeight: "180px",
    alignItems: "center",
  },
  previewImg: { width: "100%", maxHeight: "260px", objectFit: "contain" },
  actionButtons: { display: "flex", gap: "12px" },
  btn: {
    flex: 1,
    padding: "12px 20px",
    borderRadius: "8px",
    fontWeight: "600",
    fontSize: "0.95rem",
    border: "none",
    transition: "all 0.2s",
  },
  btnPrimary: { backgroundColor: "#2563eb", color: "#ffffff" },
  btnSecondary: {
    backgroundColor: "#334155",
    color: "#f1f5f9",
    border: "none",
    padding: "12px 20px",
    borderRadius: "8px",
    cursor: "pointer",
    fontWeight: "600",
  },
  errorBox: {
    marginTop: "16px",
    padding: "12px 16px",
    backgroundColor: "rgba(239, 68, 68, 0.15)",
    border: "1px solid #ef4444",
    borderRadius: "8px",
    color: "#fca5a5",
    fontSize: "0.88rem",
  },
  emptyState: {
    flex: 1,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: "40px 20px",
    textAlign: "center",
  },
  emptyIcon: { fontSize: "40px", marginBottom: "12px", opacity: 0.6 },
  emptyTitle: { fontSize: "1.1rem", color: "#cbd5e1", marginBottom: "6px" },
  emptyText: { fontSize: "0.85rem", color: "#64748b", maxWidth: "260px" },
  loadingState: {
    flex: 1,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: "40px 0",
  },
  spinner: {
    width: "44px",
    height: "44px",
    border: "3px solid #334155",
    borderTopColor: "#38bdf8",
    borderRadius: "50%",
    animation: "spin 1s linear infinite",
  },
  resultContainer: { display: "flex", flexDirection: "column", gap: "16px" },
  verdictBanner: {
    display: "flex",
    alignItems: "center",
    gap: "16px",
    padding: "16px 20px",
    borderRadius: "12px",
    border: "1px solid",
  },
  verdictTitle: { fontSize: "1.15rem", fontWeight: "700", margin: 0 },
  verdictSub: { fontSize: "0.88rem", margin: 0, opacity: 0.9 },
  cropNotice: {
    display: "flex",
    alignItems: "center",
    gap: "10px",
    padding: "10px 14px",
    borderRadius: "8px",
    border: "1px solid",
  },
  section: { marginTop: "4px" },
  sectionTitle: { fontSize: "0.92rem", color: "#cbd5e1", marginBottom: "12px" },
  metricRow: { display: "flex", flexDirection: "column", gap: "6px" },
  metricHeader: { display: "flex", justifyContent: "space-between", fontSize: "0.85rem", color: "#94a3b8" },
  barBackground: { height: "10px", backgroundColor: "#0f172a", borderRadius: "6px", overflow: "hidden" },
  barFill: { height: "100%", borderRadius: "6px", transition: "width 0.6s cubic-bezier(0.4, 0, 0.2, 1)" },
  metaGrid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", marginTop: "4px" },
  metaBox: {
    backgroundColor: "#0f172a",
    padding: "12px",
    borderRadius: "8px",
    border: "1px solid #334155",
    display: "flex",
    flexDirection: "column",
    gap: "4px",
  },
  metaLabel: { fontSize: "0.75rem", color: "#64748b" },
  metaValue: { fontSize: "0.95rem", fontWeight: "600", color: "#e2e8f0" },
  input: {
    backgroundColor: "#0f172a",
    border: "1px solid #334155",
    borderRadius: "8px",
    padding: "10px 14px",
    color: "#f1f5f9",
    fontSize: "0.9rem",
    outline: "none",
  },
  linkBtn: {
    marginTop: "10px",
    background: "none",
    border: "none",
    color: "#38bdf8",
    cursor: "pointer",
    fontSize: "0.85rem",
  },
  logoutBtn: {
    backgroundColor: "#334155",
    color: "#f1f5f9",
    border: "none",
    borderRadius: "12px",
    padding: "2px 10px",
    cursor: "pointer",
    fontSize: "0.75rem",
  },
  historyRow: {
    display: "flex",
    gap: "12px",
    alignItems: "center",
    backgroundColor: "#0f172a",
    border: "1px solid #334155",
    borderRadius: "8px",
    padding: "8px 12px",
    fontSize: "0.85rem",
    color: "#cbd5e1",
  },
};