# Damage Detection Evidence Set

Use this folder for the controlled evidence set covering exactly wall crack,
water/damp stain, mold, and no visible damage. Only use project-owned images or
images whose licence permits this academic use. Record the source and licence
for every example before running the model; do not add participant/private
photos to Git.

1. Copy `manifest.example.json` to ignored `manifest.local.json`.
2. Put licensed/project-owned photos beneath ignored `images/` and add several
   representative examples for every class.
3. Set the expected class before inference and run:

   ```powershell
   .\.venv\Scripts\python.exe -m scripts.evaluate_damage_detection calibration/damage_detection/manifest.local.json --output calibration/damage_detection/report.local.json
   ```

4. Review misclassifications and unclear results. The report explicitly sets
   `fineTuningFallbackRecommended` when any supported class has no correct
   demonstrable example. If activated, place a lightweight classifier behind
   the existing `DamageClassifier` interface without changing the API/mobile
   contract.

This controlled evaluation demonstrates the project workflow only. It is not
a medical, structural, or building-safety validation.
