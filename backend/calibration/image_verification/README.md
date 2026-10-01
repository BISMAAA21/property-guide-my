# Image Verification Calibration Set

This folder defines the controlled, project-owned image pairs used to choose the
two similarity thresholds for the configured CLIP-compatible model. Do not add
participant photographs, private property images, model weights, or generated
reports containing personal data to Git.

1. Copy `manifest.example.json` to an ignored local manifest such as
   `manifest.local.json`.
2. Add project-owned JPEG, PNG, or WebP files beneath a local `images/` folder.
3. Include several clearly similar, partly changed/viewpoint-shifted, and
   unrelated pairs. Assign the expected level before running the model.
4. Install `requirements-ai.txt` and run:

   ```powershell
   .\.venv\Scripts\python.exe -m scripts.calibrate_image_verification calibration/image_verification/manifest.local.json --output calibration/image_verification/report.local.json
   ```

5. Review every result, record the model identifier and controlled-set
   limitations, then copy the recommended values into the ignored backend
   environment as `IMAGE_SIMILARITY_HIGH_THRESHOLD` and
   `IMAGE_SIMILARITY_MODERATE_THRESHOLD`.

The script maximizes macro accuracy across high, moderate, and low labels and
uses the widest deterministic boundary when several threshold pairs tie. This
is demonstration calibration, not proof of authenticity or population-level
accuracy.
