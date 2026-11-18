import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { join, resolve, relative, basename } from 'node:path';
import { tmpdir } from 'node:os';
import { createServer as createProbe } from 'node:net';
import { request as httpsRequest } from 'node:https';
import { randomBytes } from 'node:crypto';
import { makeTLSFixture } from './tls-fixture.mjs';
import { hashToken } from '../src/handler.mjs';
import { start } from '../src/server.mjs';

async function directory(t) {
  const path = await mkdtemp(join(tmpdir(), 'tvguardian-tls-'));
  t.after(async () => {
    const absolute = resolve(path), within = relative(resolve(tmpdir()), absolute);
    assert.ok(within && !within.startsWith('..') && !within.includes(':') && basename(absolute).startsWith('tvguardian-tls-'));
    await rm(absolute, { recursive: true, force: true });
  });
  return path;
}
async function freePort() {
  const probe = createProbe(); await new Promise(resolve => probe.listen(0,'127.0.0.1',resolve));
  const port = probe.address().port; await new Promise(resolve => probe.close(resolve)); return port;
}
function read(port, options = {}) {
  return new Promise((resolve, reject) => {
    const request = httpsRequest({ host:'127.0.0.1', port, path:'/v1/companions', method:'GET', ...options }, response => {
      const protocol = response.socket.getProtocol();
      const chunks = []; response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({ status:response.statusCode, body:JSON.parse(Buffer.concat(chunks).toString('utf8')), protocol }));
    });
    request.on('error', reject); request.end();
  });
}
test('production server negotiates validated TLS and enforces bearer authentication', async t => {
  const folder = await directory(t), fixture = makeTLSFixture(), token = randomBytes(48).toString('base64url'), port = await freePort();
  await writeFile(join(folder,'cert.pem'),fixture.cert); await writeFile(join(folder,'key.pem'),fixture.key,{ mode:0o600 });
  const config = { version:1, host:'127.0.0.1', port, parentTokenHash:hashToken(token), stateFile:'state.json', tls:{cert:'cert.pem',key:'key.pem'},allowedOrigins:['null'] };
  const path = join(folder,'config.json'); await writeFile(path,JSON.stringify(config));
  const server = await start(path);
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  await assert.rejects(read(port), /self-signed|certificate/i);
  const authenticated = await read(port,{ ca:fixture.cert,headers:{Authorization:'Bearer '+token}, minVersion:'TLSv1.2' });
  assert.equal(authenticated.status,200); assert.deepEqual(authenticated.body,{items:[]});
  assert.ok(['TLSv1.2','TLSv1.3'].includes(authenticated.protocol));
  const denied = await read(port,{ca:fixture.cert}); assert.equal(denied.status,401);
});
test('production startup rejects a configuration that omits TLS', async t => {
  const folder = await directory(t), path = join(folder,'config.json');
  await writeFile(path,JSON.stringify({version:1,host:'127.0.0.1',port:8443,parentTokenHash:hashToken(randomBytes(48).toString('hex')),allowedOrigins:['null']}));
  await assert.rejects(start(path), /TLS/);
});
