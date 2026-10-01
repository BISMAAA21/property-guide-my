import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';

const self = 'scripts/security/check-tracked-secrets.mjs';
const ignoredExtensions = new Set([
  '.jpg', '.jpeg', '.png', '.webp', '.gif', '.pdf', '.apk', '.jar', '.lock',
]);
const checks = [
  ['private key block', /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/],
  ['Google-style API key', /AIza[0-9A-Za-z_-]{35}/],
  ['service-account private key field', /["']private_key["']\s*:/],
  ['service-account credential object', /["']type["']\s*:\s*["']service_account["']/],
  ['provider secret token', /sk-[0-9A-Za-z_-]{20,}/],
];

const files = execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
  .split('\0')
  .filter(Boolean)
  .filter((file) => file !== self)
  .filter((file) => !ignoredExtensions.has(file.slice(file.lastIndexOf('.')).toLowerCase()))
  .filter((file) => statSync(file).size <= 2 * 1024 * 1024);

const findings = [];
for (const file of files) {
  let content;
  try {
    content = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  for (const [label, pattern] of checks) {
    if (pattern.test(content)) findings.push(`${file}: ${label}`);
  }
}

if (findings.length > 0) {
  process.stderr.write(`Potential tracked secrets found:\n${findings.join('\n')}\n`);
  process.exit(1);
}

process.stdout.write(`Checked ${files.length} tracked text files; no secret patterns found.\n`);
