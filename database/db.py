"""
db.py — Supabase database layer
AI Investor Fraud & Impersonation Detection Platform
SIH Hackathon | PS13 Fintech / Smart Education

Provides:
  • get_client()                      — singleton Supabase client
  ─── detection_cases (new) ───────────────────────────────────
  • create_detection_case()           — create a case row
  • update_detection_case()           — update ML results & status
  • list_detection_cases()            — list/filter cases
  • get_detection_case_full()         — case + evidence + alerts + impersonation
  • get_dashboard_stats()             — aggregate counts for the dashboard
  ─── alerts ──────────────────────────────────────────────────
  • create_alert()                    — insert an alert for a case
  • list_unread_alerts()              — unread alerts (for notification badge)
  • mark_alert_read()                 — PATCH /alerts/:id/read
  ─── impersonation_checks ────────────────────────────────────
  • save_impersonation_check()        — save NLP engine output
  ─── users ───────────────────────────────────────────────────
  • get_or_create_user()              — upsert a user by email
  ─── evidence ────────────────────────────────────────────────
  • add_evidence()                    — attach evidence to a case (both table flavours)
  ─── LEGACY (kept for backwards compatibility) ───────────────
  • create_case()
  • update_case_status()
  • list_cases()
  • add_signal()
  • save_result()
  • add_log()
  • get_case_with_details()

Environment variables (see .env.example):
    SUPABASE_URL  — Supabase project URL
    SUPABASE_KEY  — anon/public key  (use service_role on the backend)
"""

from __future__ import annotations

import os
from typing import Any, Optional

from dotenv import load_dotenv
from supabase import create_client, Client

# ---------------------------------------------------------------------------
# Client initialisation
# ---------------------------------------------------------------------------

load_dotenv()  # reads .env from cwd or parent directories

SUPABASE_URL: str = os.environ["SUPABASE_URL"]
SUPABASE_KEY: str = os.environ["SUPABASE_KEY"]

_client: Optional[Client] = None


def get_client() -> Client:
    """Return a singleton Supabase client (created on first call)."""
    global _client
    if _client is None:
        _client = create_client(SUPABASE_URL, SUPABASE_KEY)
    return _client


# ===========================================================================
# USERS
# ===========================================================================

def get_or_create_user(
    email: str,
    name: str,
    role: str = "investor",
) -> dict[str, Any]:
    """
    Upsert a user by email address.

    Args:
        email: Unique user email.
        name:  Display name.
        role:  'investor' | 'analyst' | 'admin'

    Returns:
        The user row dict.
    """
    response = (
        get_client()
        .table("users")
        .upsert({"email": email, "name": name, "role": role}, on_conflict="email")
        .execute()
    )
    return response.data[0]


def get_user_by_email(email: str) -> Optional[dict[str, Any]]:
    """Return a user row by email, or None if not found."""
    resp = get_client().table("users").select("*").eq("email", email).execute()
    return resp.data[0] if resp.data else None


# ===========================================================================
# DETECTION CASES
# ===========================================================================

def create_detection_case(
    source_type: str,
    user_id: Optional[str] = None,
) -> dict[str, Any]:
    """
    Create a new detection case in 'pending' state.
    Call this as soon as a submission arrives; update it after ML runs.

    Args:
        source_type: 'video' | 'audio' | 'text' | 'chat' | 'app' | 'url'
        user_id:     Optional UUID of the submitting user.

    Returns:
        The created detection_cases row.
    """
    payload: dict[str, Any] = {"source_type": source_type, "status": "pending"}
    if user_id is not None:
        payload["user_id"] = user_id
    resp = get_client().table("detection_cases").insert(payload).execute()
    return resp.data[0]


def update_detection_case(
    case_id: str,
    prediction: str,
    confidence_score: float,
    risk_score: float,
    risk_level: str,
    status: str,
    summary: Optional[str] = None,
) -> dict[str, Any]:
    """
    Write ML engine results back into a detection case.
    Called by the backend after all engines have returned.

    Args:
        case_id:          UUID of the detection case.
        prediction:       'DEEPFAKE' | 'AUTHENTIC' | 'IMPERSONATION' | 'SUSPICIOUS' | 'SAFE'
        confidence_score: 0.0 – 1.0  (ML model confidence)
        risk_score:       0 – 100    (weighted composite score)
        risk_level:       'LOW' | 'MEDIUM' | 'HIGH'
        status:           'processed' | 'flagged' | 'cleared'
        summary:          Human-readable explanation string.

    Returns:
        The updated detection_cases row.
    """
    payload: dict[str, Any] = {
        "prediction":       prediction,
        "confidence_score": round(float(confidence_score), 4),
        "risk_score":       round(float(risk_score), 2),
        "risk_level":       risk_level,
        "status":           status,
    }
    if summary is not None:
        payload["summary"] = summary
    resp = (
        get_client()
        .table("detection_cases")
        .update(payload)
        .eq("id", case_id)
        .execute()
    )
    return resp.data[0]


def list_detection_cases(
    status: Optional[str] = None,
    risk_level: Optional[str] = None,
    prediction: Optional[str] = None,
    user_id: Optional[str] = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """
    List detection cases with optional filters. Most recent first.

    Args:
        status:     Filter by lifecycle status.
        risk_level: Filter by 'LOW' | 'MEDIUM' | 'HIGH'.
        prediction: Filter by prediction label.
        user_id:    Filter by submitting user.
        limit:      Max rows to return (default 50).

    Returns:
        List of detection_cases row dicts.
    """
    q = (
        get_client()
        .table("detection_cases")
        .select("*")
        .order("created_at", desc=True)
        .limit(limit)
    )
    if status is not None:
        q = q.eq("status", status)
    if risk_level is not None:
        q = q.eq("risk_level", risk_level)
    if prediction is not None:
        q = q.eq("prediction", prediction)
    if user_id is not None:
        q = q.eq("user_id", user_id)
    return q.execute().data


def get_detection_case_full(case_id: str) -> dict[str, Any]:
    """
    Fetch a detection case together with all related data.

    Returns:
        {
          "case":                 detection_cases row,
          "evidence":             [...],
          "alerts":               [...],
          "impersonation_check":  row | None
        }

    Raises:
        ValueError: if the case is not found.
    """
    client = get_client()

    case_resp = (
        client.table("detection_cases").select("*").eq("id", case_id).execute()
    )
    if not case_resp.data:
        raise ValueError(f"Detection case not found: {case_id}")

    evidence_resp = (
        client.table("evidence")
        .select("*")
        .eq("detection_case_id", case_id)
        .order("uploaded_at")
        .execute()
    )

    alerts_resp = (
        client.table("alerts")
        .select("*")
        .eq("detection_case_id", case_id)
        .order("created_at", desc=True)
        .execute()
    )

    imp_resp = (
        client.table("impersonation_checks")
        .select("*")
        .eq("detection_case_id", case_id)
        .execute()
    )

    return {
        "case":                case_resp.data[0],
        "evidence":            evidence_resp.data,
        "alerts":              alerts_resp.data,
        "impersonation_check": imp_resp.data[0] if imp_resp.data else None,
    }


def get_dashboard_stats() -> dict[str, Any]:
    """
    Return aggregate statistics for the dashboard.
    Runs four lightweight Supabase queries and merges the results.

    Returns:
        {
          "total_cases":     int,
          "high_risk":       int,
          "medium_risk":     int,
          "low_risk":        int,
          "flagged":         int,
          "cleared":         int,
          "pending":         int,
          "deepfake_count":  int,
          "suspicious_count":int,
          "unread_alerts":   int,
        }
    """
    client = get_client()
    cases = client.table("detection_cases").select("risk_level,status,prediction").execute().data

    total          = len(cases)
    high_risk      = sum(1 for c in cases if c["risk_level"] == "HIGH")
    medium_risk    = sum(1 for c in cases if c["risk_level"] == "MEDIUM")
    low_risk       = sum(1 for c in cases if c["risk_level"] == "LOW")
    flagged        = sum(1 for c in cases if c["status"] == "flagged")
    cleared        = sum(1 for c in cases if c["status"] == "cleared")
    pending        = sum(1 for c in cases if c["status"] == "pending")
    deepfake_count = sum(1 for c in cases if c["prediction"] == "DEEPFAKE")
    suspicious     = sum(1 for c in cases if c["prediction"] in ("SUSPICIOUS", "IMPERSONATION"))

    unread_resp    = (
        client.table("alerts").select("id").eq("is_read", False).execute()
    )
    unread_alerts  = len(unread_resp.data)

    return {
        "total_cases":      total,
        "high_risk":        high_risk,
        "medium_risk":      medium_risk,
        "low_risk":         low_risk,
        "flagged":          flagged,
        "cleared":          cleared,
        "pending":          pending,
        "deepfake_count":   deepfake_count,
        "suspicious_count": suspicious,
        "unread_alerts":    unread_alerts,
    }


# ===========================================================================
# EVIDENCE
# ===========================================================================

def add_evidence(
    evidence_type: str,
    file_path_or_content: str,
    detection_case_id: Optional[str] = None,
    case_id: Optional[str] = None,             # legacy
    filename: Optional[str] = None,
) -> dict[str, Any]:
    """
    Attach evidence to a detection case or a legacy case.

    Supply exactly one of detection_case_id or case_id.

    Args:
        evidence_type:        'video_file' | 'audio_file' | 'image_file' |
                              'chat_message' | 'text_document' | 'url' | 'app_url'
        file_path_or_content: Supabase Storage path for files; raw text for chat/URL.
        detection_case_id:    UUID of the new detection_cases row.
        case_id:              UUID of a legacy cases row.
        filename:             Display name shown in the UI.

    Returns:
        The created evidence row.
    """
    if detection_case_id is None and case_id is None:
        raise ValueError("Supply either detection_case_id or case_id.")

    payload: dict[str, Any] = {
        "evidence_type":        evidence_type,
        "file_path_or_content": file_path_or_content,
    }
    if detection_case_id is not None:
        payload["detection_case_id"] = detection_case_id
    if case_id is not None:
        payload["case_id"] = case_id
    if filename is not None:
        payload["filename"] = filename

    resp = get_client().table("evidence").insert(payload).execute()
    return resp.data[0]


# ===========================================================================
# ALERTS
# ===========================================================================

def create_alert(
    detection_case_id: str,
    alert_type: str,
    severity: str,
    message: str,
) -> dict[str, Any]:
    """
    Insert an alert for a high-risk detection case.

    Args:
        detection_case_id: UUID of the parent detection case.
        alert_type: 'DEEPFAKE_DETECTED' | 'IMPERSONATION_DETECTED' |
                    'HIGH_RISK_CONTENT' | 'SUSPICIOUS_ACTIVITY' |
                    'PLATFORM_URL_FLAGGED' | 'SCAM_NLP_DETECTED'
        severity:   'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL'
        message:    Human-readable alert description.

    Returns:
        The created alerts row.
    """
    payload = {
        "detection_case_id": detection_case_id,
        "alert_type":        alert_type,
        "severity":          severity,
        "message":           message,
        "is_read":           False,
    }
    resp = get_client().table("alerts").insert(payload).execute()
    return resp.data[0]


def list_unread_alerts(limit: int = 20) -> list[dict[str, Any]]:
    """Return unread alerts ordered by severity then recency."""
    resp = (
        get_client()
        .table("alerts")
        .select("*")
        .eq("is_read", False)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return resp.data


def mark_alert_read(alert_id: str) -> dict[str, Any]:
    """
    Mark a single alert as read. Corresponds to PATCH /alerts/:id/read.

    Args:
        alert_id: UUID of the alert row.

    Returns:
        The updated alert row.
    """
    resp = (
        get_client()
        .table("alerts")
        .update({"is_read": True})
        .eq("id", alert_id)
        .execute()
    )
    return resp.data[0]


# ===========================================================================
# IMPERSONATION CHECKS
# ===========================================================================

def save_impersonation_check(
    detection_case_id: str,
    impersonation_score: float,
    urgency_score: float,
    prediction: str,
    flags: dict[str, Any],
    claimed_name: Optional[str] = None,
    claimed_registration_number: Optional[str] = None,
) -> dict[str, Any]:
    """
    Persist NLP engine output for a text/chat/impersonation case.

    Args:
        detection_case_id:           UUID of the parent detection case.
        impersonation_score:         0.0 – 1.0
        urgency_score:               0.0 – 1.0
        prediction:                  'IMPERSONATION' | 'SUSPICIOUS' | 'LEGITIMATE' | 'PENDING'
        flags:                       Dict of boolean scam indicators.
        claimed_name:                Name the suspect claimed to be.
        claimed_registration_number: SEBI/AMFI reg number claimed.

    Returns:
        The created impersonation_checks row.
    """
    payload: dict[str, Any] = {
        "detection_case_id":  detection_case_id,
        "impersonation_score": round(float(impersonation_score), 3),
        "urgency_score":       round(float(urgency_score), 3),
        "prediction":          prediction,
        "flags":               flags,
    }
    if claimed_name is not None:
        payload["claimed_name"] = claimed_name
    if claimed_registration_number is not None:
        payload["claimed_registration_number"] = claimed_registration_number

    resp = get_client().table("impersonation_checks").insert(payload).execute()
    return resp.data[0]


# ===========================================================================
# CONVENIENCE: Full detection pipeline (backend helper)
# ===========================================================================

def run_detection_pipeline(
    source_type: str,
    evidence_type: str,
    file_path_or_content: str,
    prediction: str,
    confidence_score: float,
    risk_score: float,
    risk_level: str,
    summary: str,
    user_id: Optional[str] = None,
    filename: Optional[str] = None,
    impersonation_data: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """
    One-call helper that orchestrates the full DB write sequence:
      1. Create detection case (pending)
      2. Attach evidence
      3. Update case with ML results (processed / flagged)
      4. Auto-generate alert if HIGH risk
      5. Save impersonation check if provided

    Returns:
        {
          "case_id":        str,
          "prediction":     str,
          "confidence_score": float,
          "risk_score":     float,
          "risk_level":     str,
          "alert_generated": bool,
          "alert_id":       str | None,
          "success":        True
        }
    """
    # 1. Create case
    case = create_detection_case(source_type=source_type, user_id=user_id)
    case_id = case["id"]

    # 2. Attach evidence
    add_evidence(
        evidence_type=evidence_type,
        file_path_or_content=file_path_or_content,
        detection_case_id=case_id,
        filename=filename,
    )

    # 3. Set status based on risk
    status = "flagged" if risk_level == "HIGH" else "processed"

    # 4. Write ML results
    update_detection_case(
        case_id=case_id,
        prediction=prediction,
        confidence_score=confidence_score,
        risk_score=risk_score,
        risk_level=risk_level,
        status=status,
        summary=summary,
    )

    # 5. Alert if HIGH risk
    alert_id: Optional[str] = None
    alert_generated = False
    if risk_level == "HIGH":
        alert_type_map = {
            "DEEPFAKE":      "DEEPFAKE_DETECTED",
            "IMPERSONATION": "IMPERSONATION_DETECTED",
            "SUSPICIOUS":    "SUSPICIOUS_ACTIVITY",
        }
        alert_type  = alert_type_map.get(prediction, "HIGH_RISK_CONTENT")
        severity    = "CRITICAL" if risk_score >= 90 else "HIGH"
        alert       = create_alert(
            detection_case_id=case_id,
            alert_type=alert_type,
            severity=severity,
            message=summary,
        )
        alert_id        = alert["id"]
        alert_generated = True

    # 6. Optional impersonation data
    if impersonation_data is not None:
        save_impersonation_check(detection_case_id=case_id, **impersonation_data)

    return {
        "success":          True,
        "case_id":          case_id,
        "prediction":       prediction,
        "confidence_score": round(confidence_score, 4),
        "risk_score":       round(risk_score, 2),
        "risk_level":       risk_level,
        "alert_generated":  alert_generated,
        "alert_id":         alert_id,
    }


# ===========================================================================
# LEGACY HELPERS  — kept exactly as before for backwards compatibility
# ===========================================================================

def create_case(submitted_by: str, source_type: str) -> dict[str, Any]:
    """[LEGACY] Insert into old 'cases' table."""
    payload = {"submitted_by": submitted_by, "source_type": source_type}
    resp = get_client().table("cases").insert(payload).execute()
    return resp.data[0]


def update_case_status(case_id: str, status: str) -> dict[str, Any]:
    """[LEGACY] Update status in old 'cases' table."""
    resp = (
        get_client().table("cases").update({"status": status}).eq("id", case_id).execute()
    )
    return resp.data[0]


def list_cases(status: Optional[str] = None) -> list[dict[str, Any]]:
    """[LEGACY] List from old 'cases' table."""
    q = get_client().table("cases").select("*").order("created_at", desc=True)
    if status is not None:
        q = q.eq("status", status)
    return q.execute().data


def add_signal(
    case_id: str,
    signal_type: str,
    signal_score: float,
    raw_output: dict[str, Any],
) -> dict[str, Any]:
    """[LEGACY] Insert into 'signals' table."""
    payload = {
        "case_id":      case_id,
        "signal_type":  signal_type,
        "signal_score": round(float(signal_score), 2),
        "raw_output":   raw_output,
    }
    resp = get_client().table("signals").insert(payload).execute()
    return resp.data[0]


def save_result(
    case_id: str,
    fraud_risk_score: float,
    verdict: str,
    explanation: dict[str, Any],
) -> dict[str, Any]:
    """[LEGACY] Upsert into 'results' table."""
    payload = {
        "case_id":          case_id,
        "fraud_risk_score": round(float(fraud_risk_score), 2),
        "verdict":          verdict,
        "explanation":      explanation,
    }
    resp = (
        get_client()
        .table("results")
        .upsert(payload, on_conflict="case_id")
        .execute()
    )
    return resp.data[0]


def add_log(
    event_type: str,
    message: str,
    case_id: Optional[str] = None,
    detection_case_id: Optional[str] = None,
) -> dict[str, Any]:
    """[LEGACY-extended] Insert a log entry. Accepts both case ID flavours."""
    payload: dict[str, Any] = {"event_type": event_type, "message": message}
    if case_id is not None:
        payload["case_id"] = case_id
    if detection_case_id is not None:
        payload["detection_case_id"] = detection_case_id
    resp = get_client().table("logs").insert(payload).execute()
    return resp.data[0]


def get_case_with_details(case_id: str) -> dict[str, Any]:
    """[LEGACY] Fetch legacy case + evidence + signals + result."""
    client = get_client()

    case_resp = client.table("cases").select("*").eq("id", case_id).execute()
    if not case_resp.data:
        raise ValueError(f"Case not found: {case_id}")

    evidence_resp = (
        client.table("evidence")
        .select("*")
        .eq("case_id", case_id)
        .order("uploaded_at")
        .execute()
    )
    signals_resp = (
        client.table("signals")
        .select("*")
        .eq("case_id", case_id)
        .order("created_at")
        .execute()
    )
    result_resp = client.table("results").select("*").eq("case_id", case_id).execute()

    return {
        "case":     case_resp.data[0],
        "evidence": evidence_resp.data,
        "signals":  signals_resp.data,
        "result":   result_resp.data[0] if result_resp.data else None,
    }


# ===========================================================================
# Smoke-test  (python db.py)
# ===========================================================================

if __name__ == "__main__":
    print("=" * 65)
    print("Smoke-test: full detection pipeline  (db.py)")
    print("=" * 65)

    # ── New pipeline ──────────────────────────────────────────────
    print("\n[A] New detection pipeline (video deepfake)...")
    result = run_detection_pipeline(
        source_type="video",
        evidence_type="video_file",
        file_path_or_content="evidence/demo/sample_deepfake.mp4",
        prediction="DEEPFAKE",
        confidence_score=0.883,
        risk_score=88.3,
        risk_level="HIGH",
        summary="Face-swap deepfake detected with 88.3% confidence.",
        filename="sample_deepfake.mp4",
    )
    print(f"  case_id        : {result['case_id']}")
    print(f"  prediction     : {result['prediction']}")
    print(f"  risk_level     : {result['risk_level']}")
    print(f"  alert_generated: {result['alert_generated']}  (alert_id={result['alert_id']})")

    # ── Dashboard stats ───────────────────────────────────────────
    print("\n[B] Dashboard statistics...")
    stats = get_dashboard_stats()
    for k, v in stats.items():
        print(f"  {k:<20}: {v}")

    # ── Unread alerts ─────────────────────────────────────────────
    print("\n[C] Unread alerts...")
    unread = list_unread_alerts(limit=5)
    print(f"  Found {len(unread)} unread alert(s)")

    # ── Legacy flow (backwards compat) ────────────────────────────
    print("\n[D] Legacy create_case / add_signal flow...")
    case = create_case("legacy_user@example.com", "video")
    case_id = case["id"]
    ev = add_evidence(
        evidence_type="video_file",
        file_path_or_content="evidence/legacy/clip.mp4",
        case_id=case_id,
    )
    sig = add_signal(case_id, "deepfake", 72.5, {"frames": 100, "flagged": 72})
    res = save_result(case_id, 72.5, "high_risk", {
        "why_flagged":   "Deepfake detected",
        "what_evidence": [f"Signal {sig['id']}"],
        "what_action":   "Report to SEBI",
    })
    add_log("engine_called", "Legacy flow complete", case_id=case_id)
    details = get_case_with_details(case_id)
    print(f"  legacy case: {details['case']['id']}  signals={len(details['signals'])}  result={details['result']['verdict']}")

    print("\n" + "=" * 65)
    print("Smoke-test complete — check your Supabase Table Editor.")
    print("=" * 65)
