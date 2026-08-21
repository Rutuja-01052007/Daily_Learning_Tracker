-- =============================================================================
-- AI Investor Fraud & Impersonation Detection Platform — SEED DATA
-- SIH Hackathon | PS13 Fintech / Smart Education
--
-- Run AFTER schema.sql.
-- Uses fixed UUIDs so the frontend team can hard-code them in test fixtures.
-- =============================================================================

-- =============================================================================
-- USERS  (3 realistic users: 2 investors + 1 analyst)
-- =============================================================================
INSERT INTO users (id, name, email, role) VALUES
(
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Rajesh Mehra',
    'rajesh.mehra@example.com',
    'investor'
),
(
    'aaaaaaaa-0000-0000-0000-000000000002',
    'Priya Singh',
    'priya.singh@example.com',
    'investor'
),
(
    'aaaaaaaa-0000-0000-0000-000000000003',
    'Amit Verma',
    'amit.verma.analyst@example.com',
    'analyst'
)
ON CONFLICT (email) DO NOTHING;

-- =============================================================================
-- DETECTION CASES
-- Case 1: HIGH RISK — deepfake video of a fake SEBI official
-- Case 2: HIGH RISK — WhatsApp scam chat with impersonation
-- Case 3: MEDIUM RISK — suspicious trading app URL
-- Case 4: LOW RISK — legitimate advisor video (control case)
-- Case 5: HIGH RISK — audio deepfake phone call
-- =============================================================================

INSERT INTO detection_cases (
    id, user_id, source_type, prediction,
    confidence_score, risk_score, risk_level, status, summary
) VALUES

-- Case 1: Deepfake video
(
    'bbbbbbbb-0000-0000-0000-000000000001',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'video',
    'DEEPFAKE',
    0.9440,
    92.50,
    'HIGH',
    'flagged',
    'Submitted video shows strong deepfake artifacts including face-swap (94.4% confidence) and spoofed SEBI branding. High probability of AI-generated impersonation content targeting retail investors.'
),

-- Case 2: Chat text scam
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'chat',
    'SUSPICIOUS',
    0.8920,
    85.30,
    'HIGH',
    'flagged',
    'WhatsApp message exhibits multiple scam NLP patterns: guaranteed return claims (97%), urgency manipulation (89%), unverified SEBI registration claim, and direct UPI payment request outside regulated channels.'
),

-- Case 3: Suspicious app URL
(
    'bbbbbbbb-0000-0000-0000-000000000003',
    'aaaaaaaa-0000-0000-0000-000000000001',
    'url',
    'SUSPICIOUS',
    0.6250,
    58.00,
    'MEDIUM',
    'processed',
    'Domain sebi-invest-portal.xyz is 14 days old, uses WHOIS privacy, and has 71% typographic similarity to sebi.gov.in. Suspicious but not yet confirmed as malicious.'
),

-- Case 4: Authentic video (control / green case)
(
    'bbbbbbbb-0000-0000-0000-000000000004',
    'aaaaaaaa-0000-0000-0000-000000000003',
    'video',
    'AUTHENTIC',
    0.9710,
    8.20,
    'LOW',
    'cleared',
    'Submitted video is an official SEBI investor awareness clip. No deepfake artifacts detected. Identity verified against known reference. Content is safe.'
),

-- Case 5: Audio deepfake
(
    'bbbbbbbb-0000-0000-0000-000000000005',
    'aaaaaaaa-0000-0000-0000-000000000002',
    'audio',
    'DEEPFAKE',
    0.8770,
    80.10,
    'HIGH',
    'flagged',
    'Audio recording of a phone call shows voice-synthesis artifacts consistent with AI-generated speech (87.7% confidence). Caller impersonated a Zerodha support executive and requested OTP and UPI PIN.'
);

-- =============================================================================
-- EVIDENCE
-- =============================================================================

INSERT INTO evidence (detection_case_id, evidence_type, file_path_or_content, filename) VALUES

-- Case 1: video file in Supabase Storage
(
    'bbbbbbbb-0000-0000-0000-000000000001',
    'video_file',
    'evidence/bbbbbbbb-0000-0000-0000-000000000001/sebi_impersonation.mp4',
    'sebi_impersonation.mp4'
),

-- Case 2: chat messages (raw text stored directly)
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'chat_message',
    'Namaste! I am Rakesh Sharma from Motilal Oswal Securities. Our exclusive AI fund guarantees 40% returns in 3 months. Limited slots — invest Rs 50,000 today via UPI. No risk, fully SEBI-registered. WhatsApp me now!',
    'whatsapp_message_1.txt'
),
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'chat_message',
    'Sir, your slot is reserved. Send amount to UPI: invest.profits2024@ybl — your guaranteed profit certificate emailed in 24h.',
    'whatsapp_message_2.txt'
),

-- Case 3: URL
(
    'bbbbbbbb-0000-0000-0000-000000000003',
    'url',
    'https://sebi-invest-portal.xyz/register?ref=VIP2024',
    'suspicious_url.txt'
),

-- Case 4: authentic video
(
    'bbbbbbbb-0000-0000-0000-000000000004',
    'video_file',
    'evidence/bbbbbbbb-0000-0000-0000-000000000004/sebi_awareness_official.mp4',
    'sebi_awareness_official.mp4'
),

-- Case 5: audio file
(
    'bbbbbbbb-0000-0000-0000-000000000005',
    'audio_file',
    'evidence/bbbbbbbb-0000-0000-0000-000000000005/fake_zerodha_call.wav',
    'fake_zerodha_call.wav'
);

-- =============================================================================
-- ALERTS  (generated only for HIGH risk cases)
-- =============================================================================

INSERT INTO alerts (detection_case_id, alert_type, severity, message, is_read) VALUES

-- Case 1 alert
(
    'bbbbbbbb-0000-0000-0000-000000000001',
    'DEEPFAKE_DETECTED',
    'HIGH',
    'A submitted video has been flagged as a deepfake with 94.4% confidence. The video impersonates a SEBI official and promotes fraudulent investment schemes. Investor: Rajesh Mehra.',
    FALSE
),

-- Case 2 alert
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'SCAM_NLP_DETECTED',
    'HIGH',
    'WhatsApp messages submitted by Priya Singh contain high-confidence scam NLP patterns: guaranteed returns, urgency manipulation, and direct UPI payment request. Risk score: 85.3.',
    FALSE
),

-- Case 2 secondary alert (impersonation)
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'IMPERSONATION_DETECTED',
    'HIGH',
    'Sender claims to be a SEBI-registered advisor (Motilal Oswal). Registration number not found in SEBI database. Potential impersonation of a financial intermediary.',
    TRUE    -- already read by analyst
),

-- Case 5 alert
(
    'bbbbbbbb-0000-0000-0000-000000000005',
    'DEEPFAKE_DETECTED',
    'CRITICAL',
    'Audio deepfake detected in phone call recording submitted by Priya Singh. Caller impersonated Zerodha support and solicited OTP and UPI PIN. Confidence: 87.7%. Immediate action required.',
    FALSE
);

-- =============================================================================
-- IMPERSONATION CHECKS  (for Cases 2 and 3 which involve text/URL)
-- =============================================================================

INSERT INTO impersonation_checks (
    detection_case_id,
    claimed_name,
    claimed_registration_number,
    urgency_score,
    impersonation_score,
    prediction,
    flags
) VALUES

-- Case 2: scam chat
(
    'bbbbbbbb-0000-0000-0000-000000000002',
    'Rakesh Sharma, Motilal Oswal Securities',
    'INH000012345',
    0.890,
    0.921,
    'IMPERSONATION',
    '{
        "guaranteed_returns": true,
        "urgency_language": true,
        "unverified_sebi_claim": true,
        "direct_payment_request": true,
        "registered_advisor_verified": false,
        "official_channel_used": false
    }'
),

-- Case 3: suspicious URL — basic impersonation check on domain
(
    'bbbbbbbb-0000-0000-0000-000000000003',
    NULL,
    NULL,
    0.420,
    0.580,
    'SUSPICIOUS',
    '{
        "guaranteed_returns": false,
        "urgency_language": false,
        "unverified_sebi_claim": true,
        "direct_payment_request": false,
        "typosquat_detected": true,
        "domain_age_suspicious": true
    }'
);

-- =============================================================================
-- LEGACY TABLES  (seed for backwards-compatible db.py helpers)
-- =============================================================================

-- Legacy cases
INSERT INTO cases (id, submitted_by, source_type, status) VALUES
(
    '11111111-0000-0000-0000-000000000001',
    'rajesh.mehra@example.com',
    'video',
    'flagged'
),
(
    '22222222-0000-0000-0000-000000000002',
    'priya.singh@example.com',
    'chat_text',
    'flagged'
),
(
    '33333333-0000-0000-0000-000000000003',
    'rajesh.mehra@example.com',
    'url',
    'processed'
)
ON CONFLICT (id) DO NOTHING;

-- Legacy signals
INSERT INTO signals (case_id, signal_type, signal_score, raw_output) VALUES
(
    '11111111-0000-0000-0000-000000000001',
    'deepfake',
    87.40,
    '{"model":"EfficientNet-B4-FaceForensics","frames_analysed":240,"flagged_frames":198,"face_swap_detected":true,"lip_sync_anomaly":true}'
),
(
    '22222222-0000-0000-0000-000000000002',
    'scam_nlp',
    91.20,
    '{"model":"FinancialScamBERT-v2","overall_toxicity":0.912,"urgency_score":0.85,"flagged_phrases":["guarantees 40% returns","Limited slots","No risk"]}'
),
(
    '33333333-0000-0000-0000-000000000003',
    'platform_url',
    62.50,
    '{"domain_age_days":14,"ssl_valid":true,"whois_privacy":true,"typosquat_match":{"official_domain":"sebi.gov.in","similarity":0.71}}'
);

-- Legacy results
INSERT INTO results (case_id, fraud_risk_score, verdict, explanation) VALUES
(
    '11111111-0000-0000-0000-000000000001',
    87.40,
    'high_risk',
    '{"why_flagged":"Strong deepfake artifacts — face-swap + lip-sync anomaly","what_evidence":["Deepfake signal: 87.40/100"],"what_action":"Report to SEBI Investor Helpline 1800-266-7575"}'
),
(
    '22222222-0000-0000-0000-000000000002',
    91.20,
    'high_risk',
    '{"why_flagged":"Multiple high-confidence scam NLP patterns","what_evidence":["Scam NLP: 91.20/100"],"what_action":"Block contact. Verify advisor at sebi.gov.in"}'
),
(
    '33333333-0000-0000-0000-000000000003',
    62.50,
    'suspicious',
    '{"why_flagged":"14-day-old domain with 71% typosquat similarity to sebi.gov.in","what_evidence":["Platform URL: 62.50/100"],"what_action":"Do not submit personal info. Report at cybercrime.gov.in"}'
)
ON CONFLICT (case_id) DO NOTHING;

-- =============================================================================
-- End of seed.sql
-- =============================================================================
