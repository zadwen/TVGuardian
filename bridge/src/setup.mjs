import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { hashToken } from './handler.mjs';

const directory = fileURLToPath(new URL('../', import.meta.url));
const parentToken = randomBytes(48).toString('base64url');
await mkdir(resolve(directory, 'data/tls'), { recursive: true, mode: 0o700 });
const config = { version: 1, host: '127.0.0.1', port: 8443, parentTokenHash: hashToken(parentToken),
  stateFile: 'data/state.json', tls: { cert: 'data/tls/fullchain.pem', key: 'data/tls/privkey.pem' }, allowedOrigins: ['null'] };
// Refuse to overwrite an existing installation or credential.
await writeFile(resolve(directory, 'guardian.local.json'), JSON.stringify(config, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
await writeFile(resolve(directory, 'parent-token.local.txt'), parentToken + '\n', { flag: 'wx', mode: 0o600 });
process.stdout.write('Created guardian.local.json and parent-token.local.txt. Transfer the parent token privately into the iPhone Keychain form. Add trusted TLS files, review the bind IP/firewall and read docs/COMPANION.md before starting. No network listener was opened.\n');
