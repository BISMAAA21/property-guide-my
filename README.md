# Property Guide MY

AI-assisted Android application helping international students in Malaysia make more informed rental decisions.

> Sanitized recruiter-facing source copy — prepared locally before publication. Secrets, machine-local configuration, generated calibration outputs, synthetic agreement PDFs, and academic-only artifacts have been excluded.

The original source ZIP did not include Git history or a CI workflow. Test counts and evaluation results below are project evidence recorded in the handover, not a fresh execution of this sanitized copy.

## Sanitized publication boundary

The public copy intentionally excludes the real Firebase Android configuration, local Android SDK paths, IDE metadata, local calibration manifests/reports, raw synthetic agreement PDFs, generated calibration image fixtures, and other private or academic-only artifacts. Use the safe example files and add real configuration only in ignored local files.

## Problem

International students often need to evaluate a property, record what they observe during a visit, understand possible visual concerns, and interpret an English tenancy agreement using separate tools. Property Guide MY brings those workflows into one Android application while keeping the system deliberately cautious: it provides guidance and similarity signals, not authenticity proof, defect diagnosis, building-safety certification, or legal advice.

## Project overview

Property Guide MY is a Flutter Android prototype with three role-based experiences:

- **Students** discover approved properties, read reviews, conduct a structured inspection, upload evidence, receive cautious AI-assisted guidance, and review private reports.
- **Property Agents** create and manage property listings through a controlled approval lifecycle.
- **Administrators** manage account status, moderate listings, and remove reviews or property records within the implemented rules.

The application uses controlled project-owned property data rather than a live national property feed. The verified runtime was a debug engineering build using an emulator host address or trusted private-LAN backend; it was not a public production deployment.

## Features

### Property discovery

- Browse approved properties
- Search and filter by text, location, rent, and rating
- View property details, images, facilities, agent information, and reviews
- Create or edit one review per property

### Guided inspection

- Six inspection areas and 18 deterministic checks
- Auto-save progress and completion summaries
- Record observations and private concern photos
- Explicit handoff from an inspection concern to Damage Detection

### AI-assisted guidance

- **Image Verification:** compares a visit image with approved listing images using pretrained CLIP embeddings and cosine similarity
- **Damage Detection:** performs cautious four-label, whole-image zero-shot classification
- **Agreement processing:** extracts English PDF clauses, applies selective OCR when necessary, and requests structured simplification from Gemini

These features include fixed disclaimers and explicit failure handling. They do not prove authenticity, diagnose defects, provide legal advice, or guarantee provider availability.

### Backend and security boundaries

- FastAPI endpoints require a Firebase ID token and active Student role
- Firebase Authentication provides identity
- Cloud Firestore stores profiles, listings, reviews, inspections, and report metadata
- Firebase Storage stores controlled private images and PDFs
- Firestore and Storage rules enforce role, ownership, lifecycle, path, metadata, type, size, and immutability constraints
- The client validates structured AI responses before private persistence

## Architecture

```text
Flutter Android app
  ├─ Riverpod state and typed repositories
  ├─ Firebase Auth / Firestore / Storage
  └─ Authenticated multipart requests for Student AI features
        │ Firebase ID token
        ▼
FastAPI backend
  ├─ token, account-status, and role verification via Firebase Admin
  ├─ CLIP runtime for image similarity and damage prompts
  ├─ PyMuPDF + selective Tesseract OCR for PDFs
  └─ strict Gemini adapter for structured clause simplification
        │ validated result
        ▼
Flutter validates the response, then writes owner-private evidence/reports
```

The UI improves navigation but is not the security boundary. Firebase rules and FastAPI independently re-check identity, role, status, ownership, and input constraints.

See [the architecture notes](docs/ARCHITECTURE.md) for the component boundaries and evidence limitations.

## Technology stack

| Layer | Technology |
|---|---|
| Mobile | Flutter, Dart, Material UI |
| State/navigation | Riverpod, go_router |
| Backend | Python 3.11, FastAPI, Uvicorn, Pydantic |
| Identity/data | Firebase Authentication, Cloud Firestore, Firebase Storage |
| Vision | PyTorch, Transformers, Pillow, pretrained `openai/clip-vit-base-patch32` |
| Documents | PyMuPDF, Tesseract via pytesseract |
| External generation | Google Gemini via `google-genai` |
| Testing | pytest, Flutter test, Firebase Emulator Suite, Node-based UAT analysis |
| CI | Workflow not included in the source ZIP; add and verify GitHub Actions before claiming CI support |

## Repository structure

The intended source repository is expected to follow this high-level structure. Confirm the final tree after source import.

```text
.
├── mobile/                 # Flutter Android application
├── backend/                # FastAPI service and AI/document processing
├── firebase/               # Firestore/Storage rules, indexes, emulator tests
├── scripts/                # Local setup, verification, and demo utilities
├── docs/                   # Architecture, screenshots, and demo references
├── .env.example            # Safe configuration names only
├── .gitignore
└── README.md
```

## Local setup

### Prerequisites

- Flutter SDK compatible with the project Dart constraint (`^3.13.0`)
- Android SDK and an emulator or Android device
- Python 3.11
- Node.js 22 and Firebase CLI for emulator/rules testing
- Java 21 for the documented CI toolchain
- A Firebase project for a real connected run
- Tesseract English language data for OCR paths
- Gemini credentials only in a private local environment

### 1. Configure private values locally

Copy the safe templates and provide local values outside Git:

```text
.env.example → .env
mobile/android/app/google-services.json.example → mobile/android/app/google-services.json
```

The final source setup also requires an external Firebase Admin credential path for backend-connected workflows. Keep the generated `google-services.json`, Admin SDK JSON, Gemini keys, App Check tokens, passwords, and signing material outside commits and public artifacts.

### 2. Install mobile dependencies

```bash
cd mobile
flutter pub get
flutter test
flutter run
```

For an Android emulator, the documented local backend address is typically `http://10.0.2.2:8000`. Release mode requires HTTPS.

### 3. Run the backend

```bash
cd backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Before publication, confirm the dependency file name and production configuration against the imported source tree.

### 4. Run Firebase emulator tests

```bash
firebase emulators:start
node firebase/tests/firestore.rules.test.mjs
node firebase/tests/storage.rules.test.mjs
```

## Testing and evaluation

The project handover records the following evidence baseline:

- 109 backend pytest tests
- 64 Flutter domain, repository, widget, and routing tests
- 41 Firestore/Storage emulator rule tests
- 4 Node tests for the UAT analysis utility
- Five-participant UAT aggregate with mean SUS score of 78.00
- Controlled Image Verification result at 98.8/100
- Controlled Damage Detection fixtures including accepted low-confidence rejections and one documented misclassification

These figures are project evidence recorded in the handover, not an independent rerun performed during this documentation pass. The project does not claim a representative ML benchmark: there is no confusion matrix, precision/recall/F1 study, legal expert validation, or real-world generalisation study.

The live Gemini success path remains unverified because controlled attempts returned HTTP 429. The README must preserve that limitation rather than presenting the feature as fully validated.

## Screenshots and demo

The following assets should be added before the repository is presented to recruiters:

- Authentication and role routing
- Student property discovery and details
- Guided Inspection checklist
- Image Verification result
- Damage Detection result
- Agreement extraction/simplification flow
- Architecture diagram
- Short demo video or hosted walkthrough

See [the asset checklist](docs/demo-assets/PLACEHOLDER.md). Do not publish screenshots containing real credentials, private user data, tenancy documents, Firebase identifiers that are not intended for public release, or local network details.

## Security and privacy

See [SECURITY.md](SECURITY.md). In summary:

- Never commit `.env` files, live API keys, Firebase Admin credentials, passwords, App Check debug tokens, Android keystores, or signing properties.
- Keep `google-services.json` and external Admin SDK JSON out of public artifacts unless the final security review explicitly approves a redacted/public-safe variant.
- Use `.env.example` with names and safe placeholder values only.
- Treat tenancy agreements, inspection images, and verification/damage reports as private user data.
- Do not describe similarity guidance as fraud detection or authenticity proof.
- Do not describe damage labels as professional diagnosis or safety certification.
- Do not describe agreement simplification as legal advice.
- Review Firebase rules, deployment configuration, logging, retention, and deletion behaviour before any production use.

## Known limitations

- Android prototype scope; no iOS or web client
- Controlled project-owned property data; no live property-portal integration
- No booking, payments, landlord portal, or legal chatbot
- Damage Detection returns whole-image labels and no bounding boxes
- No trained project-owned deep model; CLIP is used as a pretrained baseline
- Live Gemini generation was blocked by provider rate/billing limits in the recorded evidence
- No public HTTPS deployment or signed Android release was verified
- Small controlled datasets and UAT sample limit generalisation claims

## License

License decision pending. Add a license before inviting external reuse or accepting contributions.
