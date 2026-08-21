# TrustFusion AI — Proposed AI Models

We can use **three pretrained AI models** for the core multimodal analysis of TrustFusion AI.

| Modality | Model | What it does | Why we can use it |
|---|---|---|---|
| 📝 Text | **SCAMBERT (DistilBERT)** | Detects scam/fraud/phishing language | Lightweight and specifically suited for scam-related text classification |
| 🎙️ Voice | **AASIST / AASIST-L** | Detects potentially synthetic/spoofed speech | Specifically designed for audio anti-spoofing |
| 🎥 Video | **Xception** | Detects potential deepfake/manipulation patterns | Established deepfake-detection architecture and suitable for pretrained inference |

## How They Work Together

```mermaid
flowchart LR
    A["Investment Communication"] --> B["Text"]
    A --> C["Voice"]
    A --> D["Video"]

    B --> E["SCAMBERT"]
    C --> F["AASIST-L"]
    D --> G["Xception"]

    E --> H["Text Risk"]
    F --> I["Voice Risk"]
    G --> J["Video Risk"]

    H --> K["Evidence Fusion"]
    I --> K
    J --> K

    K --> L["Overall Risk"]
    L --> M["Explainable Result"]
