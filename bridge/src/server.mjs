import { readFile } from 'node:fs/promises';
import { createServer } from 'node:https';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createGuardianHandler } from './handler.mjs';
import { PersistentStore } from './store.mjs';

export async function start(configPath) {
  const absolute = resolve(configPath);
  const config = JSON.parse(await readFile(absolute, 'utf8'));
  if (config.version !== 1 || !config.tls?.cert || !config.tls?.key || !/^[a-f0-9]{64}$/.test(config.parentTokenHash ?? '') ||
      !Number.isInteger(config.port) || config.port < 1024 || config.port > 65535 || typeof config.host !== 'string' ||
      !Array.isArray(config.allowedOrigins) || config.allowedOrigins.some(origin => typeof origin !== 'string' || origin === '*')) {
    throw new Error('Invalid configuration. TLS, an explicit bind address, parent token hash and restricted CORS origins are required.');
  }
  const fromConfig = value => resolve(dirname(absolute), value);
  const store = await PersistentStore.open(fromConfig(config.stateFile));
  const [cert, key] = await Promise.all([readFile(fromConfig(config.tls.cert)), readFile(fromConfig(config.tls.key))]);
  const handler = createGuardianHandler({ store, parentTokenHash: config.parentTokenHash, allowedOrigins: config.allowedOrigins,
    log: event => process.stdout.write(JSON.stringify(event) + '\n') });
  const server = createServer({ cert, key, minVersion: 'TLSv1.2', maxHeaderSize: 8192 }, handler);
  server.requestTimeout = 15_000; server.headersTimeout = 10_000; server.keepAliveTimeout = 5_000; server.maxRequestsPerSocket = 200;
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(config.port, config.host, resolve); });
  process.stdout.write(`TV Guardian HTTPS inventory bridge listening on ${config.host}:${config.port}\n`);
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const defaultPath = fileURLToPath(new URL('../guardian.local.json', import.meta.url));
  start(process.argv[2] ?? defaultPath).then(server => {
    for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { server.close(); server.closeAllConnections(); });
  }).catch(error => { process.stderr.write('Bridge startup failed: ' + error.message + '\n'); process.exitCode = 1; });
}
