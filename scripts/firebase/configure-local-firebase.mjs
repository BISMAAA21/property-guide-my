import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const androidConfigPath = resolve(
  repositoryRoot,
  'mobile',
  'android',
  'app',
  'google-services.json',
);
const environmentPath = resolve(repositoryRoot, '.env');
const environmentTemplatePath = resolve(repositoryRoot, '.env.example');
const temporaryPath = resolve(repositoryRoot, '.env.firebase-tmp');
const expectedPackage = 'com.bisma.propertyguidance';
const adminCredentialsPrefix = '--admin-credentials=';

function requiredString(value, label) {
  if (typeof value !== 'string' || value.trim() === '' || /[\r\n]/.test(value)) {
    throw new Error(`google-services.json is missing a valid ${label}.`);
  }
  return value.trim();
}

function replaceSetting(source, name, value) {
  const pattern = new RegExp(`^${name}=.*$`, 'm');
  if (!pattern.test(source)) {
    throw new Error(`The local environment template is missing ${name}.`);
  }
  return source.replace(pattern, () => `${name}=${value}`);
}

function readAdminCredentialsPath(projectId) {
  const argumentsList = process.argv.slice(2);
  if (
    argumentsList.length > 1 ||
    argumentsList.some((argument) => !argument.startsWith(adminCredentialsPrefix))
  ) {
    throw new Error(
      'Usage: node scripts/firebase/configure-local-firebase.mjs [--admin-credentials=<absolute-path>]',
    );
  }
  if (argumentsList.length === 0) {
    return null;
  }

  const suppliedPath = requiredString(
    argumentsList[0].slice(adminCredentialsPrefix.length),
    'Firebase Admin credential path',
  );
  if (!isAbsolute(suppliedPath)) {
    throw new Error('The Firebase Admin credential path must be absolute.');
  }

  const credentialsPath = resolve(suppliedPath);
  const repositoryRelativePath = relative(repositoryRoot, credentialsPath);
  const isInsideRepository =
    repositoryRelativePath === '' ||
    (!repositoryRelativePath.startsWith('..') &&
      !isAbsolute(repositoryRelativePath));
  if (isInsideRepository) {
    throw new Error(
      'The Firebase Admin credential file must be stored outside the repository.',
    );
  }
  if (!existsSync(credentialsPath)) {
    throw new Error('The Firebase Admin credential file does not exist.');
  }

  const credentialsFile = JSON.parse(readFileSync(credentialsPath, 'utf8'));
  const credentialsAreValid =
    credentialsFile?.type === 'service_account' &&
    credentialsFile?.project_id === projectId &&
    typeof credentialsFile?.client_email === 'string' &&
    credentialsFile.client_email.trim() !== '' &&
    typeof credentialsFile?.private_key === 'string' &&
    credentialsFile.private_key.trim() !== '' &&
    typeof credentialsFile?.token_uri === 'string' &&
    credentialsFile.token_uri.trim() !== '';
  if (!credentialsAreValid) {
    throw new Error(
      'The Firebase Admin credential file is invalid or belongs to another project.',
    );
  }
  return credentialsPath;
}

const firebaseConfig = JSON.parse(readFileSync(androidConfigPath, 'utf8'));
const clients = Array.isArray(firebaseConfig.client) ? firebaseConfig.client : [];
const androidClient = clients.find(
  (candidate) =>
    candidate?.client_info?.android_client_info?.package_name === expectedPackage,
);
if (!androidClient) {
  throw new Error(
    `google-services.json does not contain the expected Android package ${expectedPackage}.`,
  );
}

const settings = new Map([
  [
    'FIREBASE_PROJECT_ID',
    requiredString(firebaseConfig?.project_info?.project_id, 'project ID'),
  ],
  [
    'FIREBASE_API_KEY',
    requiredString(androidClient?.api_key?.[0]?.current_key, 'Android API key'),
  ],
  [
    'FIREBASE_APP_ID',
    requiredString(androidClient?.client_info?.mobilesdk_app_id, 'Android app ID'),
  ],
  [
    'FIREBASE_MESSAGING_SENDER_ID',
    requiredString(firebaseConfig?.project_info?.project_number, 'project number'),
  ],
  [
    'FIREBASE_STORAGE_BUCKET',
    requiredString(firebaseConfig?.project_info?.storage_bucket, 'Storage bucket'),
  ],
]);
const adminCredentialsPath = readAdminCredentialsPath(
  settings.get('FIREBASE_PROJECT_ID'),
);
if (adminCredentialsPath !== null) {
  settings.set('GOOGLE_APPLICATION_CREDENTIALS', adminCredentialsPath);
}

let environment = readFileSync(
  existsSync(environmentPath) ? environmentPath : environmentTemplatePath,
  'utf8',
);
for (const [name, value] of settings) {
  environment = replaceSetting(environment, name, value);
}

writeFileSync(temporaryPath, environment, { encoding: 'utf8', mode: 0o600 });
renameSync(temporaryPath, environmentPath);
const adminStatus =
  adminCredentialsPath === null ? '' : ' and the Firebase Admin credential path';
process.stdout.write(
  `Configured five Firebase client values${adminStatus} in the ignored root .env file.\n`,
);
