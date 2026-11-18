import { createHash, randomBytes, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { HTTPError, onlyKeys, readJSON, text, validateSnapshot } from './protocol.mjs';

export const hashToken = token => createHash('sha256').update(token).digest('hex');
function matches(token, expected) {
  return typeof token === 'string' && token.length >= 40 && typeof expected === 'string' && /^[a-f0-9]{64}$/.test(expected) &&
    timingSafeEqual(Buffer.from(hashToken(token), 'hex'), Buffer.from(expected, 'hex'));
}
export function createGuardianHandler({ store, parentTokenHash, allowedOrigins = ['null'], now = Date.now, log = () => {} }) {
  if (!/^[a-f0-9]{64}$/.test(parentTokenHash)) throw new Error('A hashed high-entropy parent token is required.');
  let pairing = null;
  const buckets = new Map();
  function limit(key, maximum, windowMS) {
    const time = now();
    if (buckets.size > 4096) for (const [k, b] of buckets) if (b.until <= time) buckets.delete(k);
    if (buckets.size >= 8192 && !buckets.has(key)) throw new HTTPError(429, 'rate_limited', 'Try again later.');
    const bucket = buckets.get(key);
    if (!bucket || bucket.until <= time) { buckets.set(key, { count: 1, until: time + windowMS }); return; }
    if (++bucket.count > maximum) throw new HTTPError(429, 'rate_limited', 'Try again later.');
  }
  function send(response, status, value) {
    const body = status === 204 ? '' : JSON.stringify(value);
    response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body),
      'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'",
      'Referrer-Policy': 'no-referrer' });
    response.end(body);
  }
  const event = name => log({ event: name, timestamp: new Date(now()).toISOString() });
  return async function handler(request, response) {
    try {
      const origin = request.headers.origin;
      if (origin !== undefined) {
        if (!allowedOrigins.includes(origin)) throw new HTTPError(403, 'origin_denied', 'Origin is not allowed.');
        response.setHeader('Access-Control-Allow-Origin', origin);
        response.setHeader('Vary', 'Origin');
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
        response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      }
      if (request.method === 'OPTIONS') { send(response, 204); return; }
      const ip = request.socket.remoteAddress ?? 'unknown'; // Never trust X-Forwarded-For.
      limit('all:' + ip, 180, 60_000);
      const url = new URL(request.url, 'https://guardian.invalid');
      if (url.search || url.hash) throw new HTTPError(400, 'query_denied', 'Tokens and query strings are not accepted in URLs.');
      const authorization = request.headers.authorization ?? '';
      const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
      const parent = matches(token, parentTokenHash);
      const parentOnly = () => {
        if (!parent) { limit('auth:' + ip, 20, 60_000); throw new HTTPError(401, 'unauthorized', 'Parent authentication is required.'); }
      };
      if (request.method === 'POST' && url.pathname === '/v1/pairing/open') {
        parentOnly(); onlyKeys(await readJSON(request), []);
        limit('open:' + ip, 10, 60_000);
        const code = Array.from({ length: 3 }, () => String(randomInt(0, 10000)).padStart(4, '0')).join('');
        pairing = { hash: hashToken(code), expiresAt: now() + 120_000 };
        event('pairing.opened'); send(response, 201, { code, expiresAt: new Date(pairing.expiresAt).toISOString() }); return;
      }
      if (request.method === 'POST' && url.pathname === '/v1/pairing/redeem') {
        limit('redeem:' + ip, 5, 120_000); limit('redeem:global', 50, 120_000);
        const body = await readJSON(request, 2048); onlyKeys(body, ['code', 'name', 'instanceID']);
        if (typeof body.code !== 'string' || !/^\d{12}$/.test(body.code) || !pairing || pairing.expiresAt <= now() ||
            !timingSafeEqual(Buffer.from(hashToken(body.code), 'hex'), Buffer.from(pairing.hash, 'hex'))) {
          throw new HTTPError(403, 'pairing_denied', 'Pairing code is invalid, expired or already used.');
        }
        const name = text(body.name, 80, 'companion name');
        const instanceID = text(body.instanceID, 64, 'instance ID');
        if (!/^[a-f0-9-]{32,64}$/.test(instanceID)) throw new HTTPError(400, 'invalid_instance', 'Invalid instance ID.');
        pairing = null; // Consume synchronously before any await, including persistence.
        const companionToken = randomBytes(48).toString('base64url');
        const record = { companionID: randomUUID(), instanceID, name, tokenHash: hashToken(companionToken),
          expiresAt: now() + 8 * 60 * 60_000, receivedAt: 0, snapshot: null };
        await store.transaction(state => {
          if (state.companions.length >= 20) throw new HTTPError(409, 'companion_limit', 'Revoke an old companion session before pairing another.');
          state.companions.push(record);
        });
        event('pairing.redeemed'); send(response, 201, { companionID: record.companionID, token: companionToken, expiresAt: new Date(record.expiresAt).toISOString() }); return;
      }
      if (url.pathname === '/v1/companion/report' && request.method === 'POST') {
        const found = store.read().companions.find(record => record.expiresAt > now() && matches(token, record.tokenHash));
        if (!found) throw new HTTPError(401, 'unauthorized', 'A valid companion session is required.');
        const snapshot = validateSnapshot(await readJSON(request));
        await store.transaction(state => {
          const record = state.companions.find(item => item.companionID === found.companionID && item.expiresAt > now() && matches(token, item.tokenHash));
          if (!record) throw new HTTPError(401, 'revoked', 'Companion session was revoked.');
          record.snapshot = snapshot; record.receivedAt = now();
        });
        event('inventory.received'); send(response, 200, { received: true, enforcement: 'none' }); return;
      }
      if (request.method === 'GET' && url.pathname === '/v1/companions') {
        parentOnly();
        const items = store.read().companions.map(record => ({ companionID: record.companionID, name: record.name,
          receivedAt: record.receivedAt ? new Date(record.receivedAt).toISOString() : '',
          stale: !record.receivedAt || now() - record.receivedAt > 90_000 || record.expiresAt <= now(), snapshot: record.snapshot }));
        send(response, 200, { items }); return;
      }
      const removal = url.pathname.match(/^\/v1\/companions\/([a-f0-9-]{36})$/);
      if (request.method === 'DELETE' && removal) {
        parentOnly(); await store.transaction(state => { state.companions = state.companions.filter(record => record.companionID !== removal[1]); });
        event('companion.revoked'); send(response, 200, { revoked: true }); return;
      }
      if (request.method === 'DELETE' && url.pathname === '/v1/companion/session') {
        await store.transaction(state => {
          const record = state.companions.find(record => matches(token, record.tokenHash));
          if (!record) throw new HTTPError(401, 'unauthorized', 'Companion session is unknown.');
          state.companions = state.companions.filter(item => item.companionID !== record.companionID);
        });
        event('companion.stopped'); send(response, 200, { revoked: true }); return;
      }
      parentOnly(); throw new HTTPError(404, 'unsupported_operation', 'This bridge provides inventory only. No application-management command exists at this route.');
    } catch (error) {
      if (response.destroyed || response.writableEnded) return;
      const known = error instanceof HTTPError;
      if (!known) event('storage_or_internal_error');
      send(response, known ? error.status : 500, { error: { code: known ? error.code : 'internal_error', message: known ? error.message : 'The operation was not committed. Check bridge storage and server diagnostics.' } });
    }
  };
}
