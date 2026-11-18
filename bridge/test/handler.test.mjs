import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';
import { createGuardianHandler, hashToken } from '../src/handler.mjs';
import { PersistentStore } from '../src/store.mjs';

// HTTP exists only inside loopback test fixtures. The production entry point is
// HTTPS-only, requires certificate files and has no plaintext fallback.
async function fixture(t) {
  let time = 1_800_000_000_000;
  const parent = randomBytes(48).toString('base64url');
  const store = new PersistentStore({ schemaVersion: 1, companions: [] });
  const log = [];
  const server = createServer(createGuardianHandler({ store, parentTokenHash: hashToken(parent), now: () => time, log: entry => log.push(entry) }));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  async function request(path, { method = 'GET', token, body, headers = {} } = {}) {
    const response = await fetch(base + path, { method, headers: { ...(token ? { Authorization: 'Bearer ' + token } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await response.text(); return { status: response.status, data: text ? JSON.parse(text) : {}, headers: response.headers };
  }
  const open = () => request('/v1/pairing/open', { method: 'POST', token: parent, body: {} });
  const redeem = code => request('/v1/pairing/redeem', { method: 'POST', body: { code, name: 'Fixture TV', instanceID: randomBytes(16).toString('hex') } });
  async function pair() { const opened = await open(); assert.equal(opened.status, 201); const redeemed = await redeem(opened.data.code); assert.equal(redeemed.status, 201); return redeemed.data; }
  return { request, open, redeem, pair, parent, store, log, advance: milliseconds => { time += milliseconds; } };
}
const snapshot = () => ({ protocolVersion: 1, inventoryStatus: 'supported', complete: false,
  apps: [{ id: 'fixture.app', name: 'Fixture application', packageID: 'fixturepkg', iconPath: '/opt/apps/fixture/icon.png' }], errors: [] });

test('parent routes require authentication', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/v1/companions')).status, 401);
  assert.equal((await f.request('/v1/pairing/open', { method: 'POST', body: {} })).status, 401);
  assert.equal((await f.request('/v1/companions', { token: randomBytes(48).toString('hex') })).status, 401);
});
test('pairing code is single-use and TV credentials cannot read parent inventory', async t => {
  const f = await fixture(t); const opened = await f.open(); const redeemed = await f.redeem(opened.data.code);
  assert.match(opened.data.code, /^\d{12}$/); assert.equal(redeemed.status, 201);
  assert.equal((await f.redeem(opened.data.code)).status, 403);
  assert.equal((await f.request('/v1/companions', { token: redeemed.data.token })).status, 401);
  const state = f.store.read(); assert.notEqual(state.companions[0].tokenHash, redeemed.data.token);
  assert.equal(state.companions[0].tokenHash, hashToken(redeemed.data.token));
});
test('expired code is refused', async t => {
  const f = await fixture(t); const opened = await f.open(); f.advance(120_001);
  assert.equal((await f.redeem(opened.data.code)).status, 403);
});
test('opening a new code invalidates the previous code', async t => {
  const f = await fixture(t); const old = await f.open(); const current = await f.open();
  assert.equal((await f.redeem(old.data.code)).status, 403);
  assert.equal((await f.redeem(current.data.code)).status, 201);
});
test('simultaneous redemption commits at most one session', async t => {
  const f = await fixture(t); const opened = await f.open();
  const responses = await Promise.all([f.redeem(opened.data.code), f.redeem(opened.data.code)]);
  assert.deepEqual(responses.map(r => r.status).sort(), [201, 403]); assert.equal(f.store.read().companions.length, 1);
});
test('pairing guesses are rate limited', async t => {
  const f = await fixture(t); await f.open();
  for (let i = 0; i < 5; i++) assert.equal((await f.redeem('000000000000')).status, 403);
  assert.equal((await f.redeem('000000000000')).status, 429);
});
test('inventory upload is validated, authenticated, timestamped by server and scoped', async t => {
  const f = await fixture(t); const tv = await f.pair();
  assert.equal((await f.request('/v1/companion/report', { method: 'POST', token: f.parent, body: snapshot() })).status, 401);
  const result = await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body: snapshot() });
  assert.equal(result.status, 200); assert.equal(result.data.enforcement, 'none');
  const list = await f.request('/v1/companions', { token: f.parent });
  assert.equal(list.data.items[0].snapshot.apps[0].id, 'fixture.app'); assert.equal(list.data.items[0].stale, false);
  assert.equal(list.data.items[0].snapshot.complete, false);
  const serialized = JSON.stringify(list.data); assert.ok(!serialized.includes(tv.token)); assert.ok(!serialized.includes('tokenHash'));
  assert.equal(list.headers.get('cache-control'), 'no-store');
});
test('unverified inventory is preserved as unverified, not successful empty inventory', async t => {
  const f = await fixture(t); const tv = await f.pair();
  const data = { protocolVersion: 1, inventoryStatus: 'unverified', complete: false, apps: [], errors: ['Application inventory denied: SecurityError'] };
  assert.equal((await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body: data })).status, 200);
  const list = await f.request('/v1/companions', { token: f.parent }); assert.equal(list.data.items[0].snapshot.inventoryStatus, 'unverified');
});
test('stale reports and expired companion tokens do not imply enforcement', async t => {
  const f = await fixture(t); const tv = await f.pair();
  await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body: snapshot() });
  f.advance(90_001); assert.equal((await f.request('/v1/companions', { token: f.parent })).data.items[0].stale, true);
  f.advance(8 * 60 * 60_000); assert.equal((await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body: snapshot() })).status, 401);
});
test('revocation invalidates companion credentials immediately', async t => {
  const f = await fixture(t); const tv = await f.pair();
  assert.equal((await f.request('/v1/companions/' + tv.companionID, { method: 'DELETE', token: f.parent })).status, 200);
  assert.equal((await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body: snapshot() })).status, 401);
});
test('TV can revoke only its own session', async t => {
  const f = await fixture(t); const first = await f.pair(); const second = await f.pair();
  assert.equal((await f.request('/v1/companions/' + second.companionID, { method: 'DELETE', token: first.token })).status, 401);
  assert.equal((await f.request('/v1/companion/session', { method: 'DELETE', token: first.token })).status, 200);
  assert.equal(f.store.read().companions.length, 1); assert.equal(f.store.read().companions[0].companionID, second.companionID);
});
test('no uninstall, lock, shell or package-management endpoint exists', async t => {
  const f = await fixture(t);
  for (const route of ['/v1/uninstall', '/v1/apps/fixture.app', '/v1/lock', '/v1/shell', '/api/v2/applications/fixture.app']) {
    assert.equal((await f.request(route, { method: 'DELETE', token: f.parent })).status, 404);
  }
});
test('unsupported claims, duplicate IDs and system flags are rejected', async t => {
  const f = await fixture(t); const tv = await f.pair();
  for (const modify of [v => { v.complete = true; }, v => { v.uninstall = true; }, v => { v.apps[0].system = true; }, v => { v.apps.push(v.apps[0]); }, v => { v.inventoryStatus = 'unverified'; }, v => { v.apps[0].id = '../shell'; }]) {
    const body = snapshot(); modify(body);
    assert.equal((await f.request('/v1/companion/report', { method: 'POST', token: tv.token, body })).status, 400);
  }
  assert.equal(f.store.read().companions[0].snapshot, null);
});
test('cross-origin web requests cannot use arbitrary origins', async t => {
  const f = await fixture(t);
  assert.equal((await f.request('/v1/companions', { token: f.parent, headers: { Origin: 'https://untrusted.example' } })).status, 403);
  const allowed = await f.request('/v1/companions', { token: f.parent, headers: { Origin: 'null' } });
  assert.equal(allowed.status, 200); assert.equal(allowed.headers.get('access-control-allow-origin'), 'null');
});
test('URL tokens and query strings are refused and secrets are not logged', async t => {
  const f = await fixture(t); const tv = await f.pair();
  assert.equal((await f.request('/v1/companions?token=' + tv.token, { token: f.parent })).status, 400);
  const logs = JSON.stringify(f.log); assert.ok(!logs.includes(tv.token)); assert.ok(!logs.includes(f.parent));
});
