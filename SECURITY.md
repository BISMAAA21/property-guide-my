# Security and privacy notes

Property Guide MY handles authentication data, private inspection images, verification/damage evidence, and tenancy-agreement PDFs. Treat these as sensitive user data.

## Never commit

- `.env` files or files containing live environment values
- Gemini, Firebase, Google Cloud, or other API keys
- Firebase Admin SDK JSON or service-account credentials
- Passwords, reset tokens, OAuth tokens, or App Check debug tokens
- Android signing properties, keystores, `.jks`, `.p12`, `.pfx`, `.pem`, or private keys
- Real tenancy agreements, participant records, private screenshots, or personal identifiers

Use `.env.example` for variable names and safe placeholders. The `.gitignore` intentionally excludes sensitive Firebase configuration, credentials, keys, and generated academic artifacts.

## Security boundaries

- Firebase Authentication establishes identity.
- Firestore and Storage rules enforce role, account status, ownership, lifecycle, path, metadata, type, size, and immutability constraints.
- FastAPI independently verifies Firebase tokens and requires an active Student role for AI endpoints.
- Uploaded content is checked by signature and decode, not only filename or MIME label.
- Provider output is treated as untrusted and must match the expected structured schema before persistence.

## Responsible claims

The AI features provide cautious guidance only. They do not prove property authenticity, detect fraud, diagnose building defects, certify safety, or provide legal advice. Evaluation evidence is controlled and limited; it must not be presented as production accuracy or real-world generalisation.

## Before publication

1. Run a secret scanner against the working tree and all Git history.
2. Review Firebase rules and public/private data boundaries.
3. Confirm that screenshots and sample documents contain no real personal data.
4. Verify that logs and error messages do not expose tokens, provider responses, paths, or private documents.
5. Confirm that all deployment secrets are supplied through a secret manager or private environment.

If a suspected vulnerability or accidental secret is found, revoke/rotate the affected credential first, then report the issue privately to the repository owner. Do not open a public issue containing the secret.
