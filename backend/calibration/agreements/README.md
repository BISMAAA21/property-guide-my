# Controlled Agreement Demonstration Evidence

Keep all demonstration PDFs and generated responses local and untracked. Do not
use a participant's or student's real tenancy agreement.

Prepare two synthetic English agreements containing the same numbered clauses:

- `documents/native-text.pdf`: selectable embedded text.
- `documents/scanned.pdf`: page images with no selectable text.

Each sample should contain at least rent, deposit, maintenance, and termination
clauses with invented names, addresses, and amounts. After installing the AI
dependencies and Tesseract, configure an ignored `GEMINI_API_KEY`, start the API,
and submit both documents through the authenticated Android workflow.

The repository can generate a deterministic privacy-safe pair locally:

```powershell
cd backend
.\.venv\Scripts\python.exe -m scripts.create_controlled_agreements
```

The generator refuses to replace existing samples unless `--force` is supplied.
Both PDFs remain ignored. The native sample contains selectable text; the scanned
sample contains only a rendered page image for the OCR path.

After configuring the ignored provider key, run the privacy-safe evaluator. Its
report contains hashes and schema/order checks but no clause text:

```powershell
.\.venv\Scripts\python.exe -m scripts.evaluate_controlled_agreements `
  --output calibration/agreements/provider-report.local.json
```

Create and manage the key through the official Google AI Studio API Keys page.
Treat the API preflight as authoritative; current auth keys need not use a legacy
standard-key prefix.

Record the following in an ignored `evidence.local.md` file:

- sample identifier and controlled-data provenance;
- extraction method (`embedded_text` for native and `ocr` for scanned);
- preserved clause count and order;
- whether every result contains original wording, a different simplified
  explanation, one to five important points, the model identifier, and the
  mandatory not-legal-advice disclaimer;
- any explicit failure code and request identifier.

Successful evidence requires both samples to produce ordered results. An OCR or
provider failure must be recorded as a failure and must not be counted as a
successful explanation.

As of 26 August 2026, the configured key and `gemini-3.5-flash-lite` model pass
read-only discovery, but generation returns HTTP 429 before content is produced.
A separate secret-safe diagnostic identified depleted prepayment credits and
supplied no retry delay or timed reset condition. Keep the ignored key and
implementation unchanged, do not treat discovery or safe failure as generation
evidence, and rerun the evaluator only after the owner legitimately changes the
provider billing/prepayment state.
