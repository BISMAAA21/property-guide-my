# Property Guide MY architecture

## Runtime boundary

```text
Student / Agent / Administrator
              │
              ▼
      Flutter Android client
       │       │        │
       │       │        └── Firebase Storage: private images and PDFs
       │       └─────────── Cloud Firestore: profiles, listings, reports
       └─────────────────── Firebase Auth: identity and tokens
              │
              │ Student AI requests with Firebase ID token
              ▼
          FastAPI backend
       ┌──────┼──────────────┐
       ▼      ▼              ▼
     CLIP   PDF/OCR       Gemini adapter
   vision  PyMuPDF +      strict schema
           Tesseract      validation
```

## Trust boundaries

The Flutter UI is not the security boundary. Firebase rules protect direct Firestore/Storage operations, while FastAPI verifies the Firebase token, account state, and Student role independently. Provider responses are untrusted until their schema, clause order, source text, and required fields are validated.

## Feature boundaries

- Image Verification uses pretrained CLIP embeddings and cosine similarity. It is similarity guidance, not authenticity proof.
- Damage Detection uses four reviewed whole-image prompts. It returns no bounding box and is not professional diagnosis.
- Guided Inspection is deterministic checklist logic, not machine learning.
- Agreement processing extracts and segments PDF clauses locally before sending structured content to Gemini. It is not a legal chatbot.

## Evidence boundary

The verified runtime was a debug Android build connected to a local/private-LAN backend. The project has no verified public HTTPS deployment, signed release, representative ML benchmark, or successful live Gemini generation in the recorded evidence.
