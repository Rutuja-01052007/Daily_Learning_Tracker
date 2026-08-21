# Database Module — AI Investor Fraud & Impersonation Detection
**SIH Hackathon | PS13 Fintech / Smart Education**

---

## Architecture Overview

```
Frontend  (React / Next.js — Rutuja / Rohit)
    │  HTTP JSON
    ▼
Backend / FastAPI  (API gateway)
    │
    ├─── AI / ML Detection Layer
    │         ├── Deepfake Engine  (video / audio)
    │         ├── NLP / Scam Engine  (text / chat)
    │         └── Platform URL Engine  (url / app)
    │
    ▼
Supabase PostgreSQL  ◄── THIS MODULE
    │
    ├── users
    ├── detection_cases  ←  core table
    │     ├── evidence
    │     ├── alerts
    │     └── impersonation_checks
    ├── cases / signals / results / logs  ←  legacy (backwards compat)
    │
    ▼
Backend JSON Response → Frontend Dashboard
```

---

## Table Reference

### `users`
System users — investors who submit content and analysts who review it.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Auto-generated |
| `name` | TEXT | Display name |
| `email` | TEXT UNIQUE | Login identifier |
| `role` | TEXT | `investor` \| `analyst` \| `admin` |
| `created_at` | TIMESTAMPTZ | Auto-set |

---

### `detection_cases` ⭐ (primary table)
One row per fraud-detection request. Written by the backend immediately on submission, then updated after the ML engines return.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Auto-generated |
| `user_id` | UUID FK → users | Nullable |
| `source_type` | TEXT | `video` \| `audio` \| `text` \| `chat` \| `app` \| `url` |
| `prediction` | TEXT | `DEEPFAKE` \| `AUTHENTIC` \| `IMPERSONATION` \| `SUSPICIOUS` \| `SAFE` \| `PENDING` |
| `confidence_score` | NUMERIC(5,4) | 0.0 – 1.0 (ML model confidence) |
| `risk_score` | NUMERIC(5,2) | 0 – 100 (weighted composite) |
| `risk_level` | TEXT | `LOW` \| `MEDIUM` \| `HIGH` |
| `status` | TEXT | `pending` → `processing` → `flagged` \| `cleared` |
| `summary` | TEXT | Human-readable explanation |
| `created_at` | TIMESTAMPTZ | Auto-set |

---

### `evidence`
Evidence metadata. Stores Supabase Storage **paths** for files, raw text for chat/URL.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `detection_case_id` | UUID FK → detection_cases | Preferred |
| `case_id` | UUID FK → cases | Legacy only |
| `evidence_type` | TEXT | `video_file` \| `audio_file` \| `image_file` \| `chat_message` \| `text_document` \| `url` \| `app_url` |
| `file_path_or_content` | TEXT | Storage path **or** raw text |
| `filename` | TEXT | Display name |
| `uploaded_at` | TIMESTAMPTZ | |

---

### `alerts`
Auto-generated when `risk_level = 'HIGH'`. Drives the dashboard notification system.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `detection_case_id` | UUID FK → detection_cases | |
| `alert_type` | TEXT | `DEEPFAKE_DETECTED` \| `IMPERSONATION_DETECTED` \| etc. |
| `severity` | TEXT | `LOW` \| `MEDIUM` \| `HIGH` \| `CRITICAL` |
| `message` | TEXT | Alert description |
| `is_read` | BOOLEAN | Default FALSE |
| `created_at` | TIMESTAMPTZ | |

---

### `impersonation_checks`
NLP engine output for text/chat submissions — detailed impersonation analysis.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `detection_case_id` | UUID FK → detection_cases | |
| `claimed_name` | TEXT | Suspect's claimed identity |
| `claimed_registration_number` | TEXT | Claimed SEBI/AMFI reg no. |
| `urgency_score` | NUMERIC(4,3) | 0.0 – 1.0 |
| `impersonation_score` | NUMERIC(4,3) | 0.0 – 1.0 |
| `prediction` | TEXT | `IMPERSONATION` \| `SUSPICIOUS` \| `LEGITIMATE` |
| `flags` | JSONB | `{guaranteed_returns, urgency_language, …}` |
| `created_at` | TIMESTAMPTZ | |

---

### Legacy tables (backwards compatible)
`cases`, `signals`, `results`, `logs` — keep the existing `db.py` helpers working without any changes.

---

## Supabase Setup (Step-by-Step)

### 1. Create a free Supabase project
1. Go to [supabase.com](https://supabase.com) → **Sign in** → **New project**
2. Name it (e.g. `fraud-detect-sih`), set a DB password, pick nearest region
3. Wait ~2 minutes for provisioning

### 2. Run the schema
1. **SQL Editor** (left sidebar) → **New query**
2. Paste the entire contents of [`schema.sql`](./schema.sql)
3. Click **Run** — "Success. No rows returned."

### 3. Run the seed data
1. **New query** → paste [`seed.sql`](./seed.sql) → **Run**
2. Verify: `SELECT * FROM detection_cases;` — should return 5 rows

### 4. Create the Storage bucket for evidence files
1. **Storage** (left sidebar) → **New bucket**
2. Name: `evidence` | Public: **OFF**
3. The backend uploads files here; `evidence.file_path_or_content` stores the path

---

## Getting Your Credentials

1. **Project Settings** (gear icon) → **API**
2. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon / public** key → `SUPABASE_KEY` (safe for read-only frontend use)
   - **service_role** key → use this on the backend only — **never expose to browser**

---

## Local Python Setup

```bash
# 1. Navigate into the database module
cd database/

# 2. Create virtual environment
python -m venv .venv

# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Configure environment
copy .env.example .env    # Windows
cp .env.example .env      # macOS/Linux
# Edit .env — paste SUPABASE_URL and SUPABASE_KEY

# 5. Verify syntax
python -m py_compile db.py && echo "OK"

# 6. Run the smoke-test (creates real rows in Supabase)
python db.py
```

---

## Backend Integration Contract

### Expected Data Flow for `POST /detect`

```
1. FastAPI receives uploaded file + user metadata
2. Upload file to Supabase Storage  →  get storage_path
3. Call db.create_detection_case(source_type, user_id)  →  get case_id
4. Call db.add_evidence(detection_case_id=case_id, ...)
5. ML engines run (async)
6. Call db.update_detection_case(case_id, prediction, confidence_score, risk_score, ...)
7. If risk_level == 'HIGH': db.create_alert(case_id, ...)
8. If source_type in ('chat','text'): db.save_impersonation_check(case_id, ...)
9. Return JSON response
```

### Suggested JSON Response Format

```json
{
  "success": true,
  "case_id": "bbbbbbbb-0000-0000-0000-000000000001",
  "prediction": "DEEPFAKE",
  "confidence_score": 0.9440,
  "risk_score": 92.5,
  "risk_level": "HIGH",
  "alert_generated": true
}
```

### One-Call Helper (recommended for the backend)

```python
from database.db import run_detection_pipeline

result = run_detection_pipeline(
    source_type       = "video",
    evidence_type     = "video_file",
    file_path_or_content = storage_path,   # returned by Supabase Storage upload
    prediction        = deepfake_engine.predict(),
    confidence_score  = deepfake_engine.confidence,   # 0.0 – 1.0
    risk_score        = risk_engine.score,             # 0 – 100
    risk_level        = risk_engine.level,             # 'LOW'|'MEDIUM'|'HIGH'
    summary           = explanation_engine.summary,
    user_id           = current_user_id,
    filename          = upload.filename,
)
# result["case_id"], result["alert_generated"], etc.
return JSONResponse(result)
```

### Dashboard Endpoints

```python
from database.db import (
    list_detection_cases, get_detection_case_full,
    get_dashboard_stats, list_unread_alerts, mark_alert_read,
)

# GET /cases
cases = list_detection_cases(risk_level="HIGH", limit=50)

# GET /cases/:id
detail = get_detection_case_full(case_id)
# → {"case": {...}, "evidence": [...], "alerts": [...], "impersonation_check": {...}}

# GET /dashboard/stats
stats = get_dashboard_stats()
# → {"total_cases": 5, "high_risk": 3, "unread_alerts": 4, ...}

# GET /alerts?unread=true
alerts = list_unread_alerts()

# PATCH /alerts/:id/read
mark_alert_read(alert_id)
```

---

## Frontend (Rutuja / Rohit) — Direct JS Access

For read-only dashboard queries you can bypass the FastAPI backend entirely:

```js
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  'https://your-project-ref.supabase.co',
  'your-anon-key'   // anon key is safe to expose in the browser
)

// List high-risk flagged cases
const { data: cases } = await supabase
  .from('detection_cases')
  .select('*')
  .eq('risk_level', 'HIGH')
  .order('created_at', { ascending: false })

// Full case detail with nested data
const { data } = await supabase
  .from('detection_cases')
  .select('*, evidence(*), alerts(*), impersonation_checks(*)')
  .eq('id', caseId)
  .single()

// Unread alert count (notification badge)
const { count } = await supabase
  .from('alerts')
  .select('*', { count: 'exact', head: true })
  .eq('is_read', false)
```

> Enable RLS (see commented block in `schema.sql`) before any production deployment
> so the anon key cannot read all rows.

---

## Supabase Storage — Evidence Files

```python
from supabase import create_client
import os

client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])

# Upload a file
with open("local_video.mp4", "rb") as f:
    storage_path = f"case-{case_id}/video.mp4"
    client.storage.from_("evidence").upload(storage_path, f)

# Save path into evidence table
db.add_evidence(
    evidence_type="video_file",
    file_path_or_content=storage_path,
    detection_case_id=case_id,
    filename="video.mp4",
)

# Generate a 1-hour signed URL for playback in the dashboard
signed = client.storage.from_("evidence").create_signed_url(storage_path, 3600)
playback_url = signed["signedURL"]
```

---

## Dataset Recommendation (Deepfake Engine)

**Recommended: Celeb-DF v2** (subset)

- Full dataset: ~590 videos — **too large for 2 days**
- ✅ Use 20–50 real + 20–50 fake clips from the public test split
- Pretrained model: [timesformer-deepfake](https://huggingface.co/) or EfficientNet-B4 fine-tuned on FaceForensics++
- The database stores only **detection results** (confidence score, per-frame JSON), not raw video frames

| What to store in DB | What NOT to store |
|---------------------|-------------------|
| `confidence_score` (float) | Raw video frames |
| `prediction` label | Training dataset |
| `signals.raw_output` (JSON summary) | Model weights |
| Supabase Storage path | Full dataset |

---

## Git Workflow

```bash
# Create and switch to the database branch
git checkout -b database

# Stage all database files
git add database/

# Commit
git commit -m "feat(db): complete Supabase database layer

- schema.sql: users, detection_cases, evidence, alerts,
  impersonation_checks + legacy tables (backwards compat)
- seed.sql: 3 users, 5 cases, evidence, alerts, imp checks
- db.py: new helpers + all legacy functions preserved
- queries_and_transactions.sql: 9 named queries + BEGIN/COMMIT tx
- migrations/001_initial_schema.sql: idempotent migration
- README, .env.example, .gitignore, requirements.txt"

# Push to remote
git push -u origin database
```

---

## Commands Quick-Reference

```bash
# Install deps
pip install -r requirements.txt

# Syntax check
python -m py_compile db.py && echo "Syntax OK"

# Smoke-test (needs real .env)
python db.py

# Apply schema (psql alternative to SQL Editor)
psql $DATABASE_URL -f schema.sql
psql $DATABASE_URL -f seed.sql

# Apply migration
psql $DATABASE_URL -f migrations/001_initial_schema.sql
```

---

## File Reference

| File | Purpose |
|------|---------|
| [`schema.sql`](./schema.sql) | All tables, indexes, RLS stubs |
| [`seed.sql`](./seed.sql) | Demo data — 5 cases, 3 users, alerts |
| [`db.py`](./db.py) | Python helpers (new + legacy) |
| [`queries_and_transactions.sql`](./queries_and_transactions.sql) | Named queries + safe transaction |
| [`migrations/001_initial_schema.sql`](./migrations/001_initial_schema.sql) | Idempotent versioned migration |
| [`.env.example`](./.env.example) | Credential template |
| [`.gitignore`](./.gitignore) | Ignores `.env`, `__pycache__`, etc. |
| [`requirements.txt`](./requirements.txt) | Pinned Python deps |
