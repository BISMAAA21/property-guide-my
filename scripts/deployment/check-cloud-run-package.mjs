import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..', '..');
const dockerfile = readFileSync(resolve(root, 'backend', 'Dockerfile'), 'utf8');
const dockerignore = readFileSync(resolve(root, 'backend', '.dockerignore'), 'utf8');
const environment = readFileSync(
  resolve(root, 'backend', 'deploy', 'cloud-run.env.yaml.example'),
  'utf8',
);

const requiredDockerTokens = [
  'python:3.11-slim-bookworm',
  'tesseract-ocr-eng',
  'HF_HUB_OFFLINE=1',
  'TRANSFORMERS_OFFLINE=1',
  'USER appuser',
  '${PORT:-8080}',
];
const missingDockerTokens = requiredDockerTokens.filter(
  (token) => !dockerfile.includes(token),
);
if (missingDockerTokens.length > 0) {
  throw new Error(`Dockerfile is missing: ${missingDockerTokens.join(', ')}`);
}
if (/^COPY\s+\.\s+/mu.test(dockerfile)) {
  throw new Error('Dockerfile must not copy the complete backend context.');
}

for (const token of ['**', '!app/**', '!scripts/cache_clip_model.py']) {
  if (!dockerignore.includes(token)) {
    throw new Error(`.dockerignore is missing: ${token}`);
  }
}

const requiredEnvironmentKeys = [
  'APP_ENV',
  'FIREBASE_PROJECT_ID',
  'IMAGE_SIMILARITY_HIGH_THRESHOLD',
  'IMAGE_SIMILARITY_MODERATE_THRESHOLD',
  'DAMAGE_MIN_CONFIDENCE',
  'GEMINI_MODEL',
];
for (const key of requiredEnvironmentKeys) {
  if (!new RegExp(`^${key}:`, 'mu').test(environment)) {
    throw new Error(`Cloud Run environment template is missing ${key}.`);
  }
}
for (const secret of [
  'GEMINI_API_KEY',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'SEED_USER_PASSWORD',
  'FIREBASE_API_KEY',
]) {
  if (new RegExp(`^${secret}:`, 'mu').test(environment)) {
    throw new Error(`Secret ${secret} must not appear in the environment template.`);
  }
}

console.log('Cloud Run package structure is safe and complete.');
