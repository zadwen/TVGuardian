import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const { collect } = createRequire(import.meta.url)('../src/inventory.js');
const app = { id: 'fixture.app', name: 'Fixture app', packageId: 'fixturepkg', iconPath: '/opt/fixture/icon.png' };
test('missing hardware never produces a simulated success', async () => {
  const result = await collect(undefined); assert.equal(result.inventoryStatus, 'unsupported'); assert.deepEqual(result.apps, []); assert.equal(result.complete, false);
});
test('authorized application data preserves identifiers without system-status inference', async () => {
  const result = await collect({ application: { getAppsInfo: success => success([app]) }, package: { getPackagesInfo: success => success([]) } });
  assert.equal(result.inventoryStatus, 'supported'); assert.equal(result.apps[0].id, 'fixture.app'); assert.equal(result.apps[0].packageID, 'fixturepkg');
  assert.equal(result.apps[0].system, undefined); assert.equal(result.complete, false); assert.deepEqual(result.errors, []);
});
test('permission denial stays unverified with a useful error', async () => {
  const result = await collect({ application: { getAppsInfo: (_, failure) => failure({ name: 'SecurityError' }) } });
  assert.equal(result.inventoryStatus, 'unverified'); assert.match(result.errors[0], /SecurityError/); assert.deepEqual(result.apps, []);
});
test('NotSupportedError is distinct from permission denial', async () => {
  const result = await collect({ application: { getAppsInfo: () => { throw { name: 'NotSupportedError' }; } } });
  assert.equal(result.inventoryStatus, 'unsupported');
});
test('package-information denial preserves successful public app inventory as partial', async () => {
  const result = await collect({ application: { getAppsInfo: success => success([app]) }, package: { getPackagesInfo: (_, failure) => failure({ name: 'SecurityError' }) } });
  assert.equal(result.inventoryStatus, 'supported'); assert.equal(result.apps.length, 1); assert.match(result.errors[0], /Package information.*SecurityError/); assert.equal(result.complete, false);
});
test('timeouts do not fabricate an empty supported inventory', async () => {
  const result = await collect({ application: { getAppsInfo: () => {} } }, 10); assert.equal(result.inventoryStatus, 'unverified'); assert.match(result.errors[0], /TimeoutError/);
});
test('malformed callbacks are rejected and duplicate identifiers are omitted', async () => {
  const bad = await collect({ application: { getAppsInfo: success => success({}) } }); assert.equal(bad.inventoryStatus, 'unverified');
  const good = await collect({ application: { getAppsInfo: success => success([app, app, { id: '../x', name: 'Bad' }]) } }); assert.equal(good.apps.length, 1);
});
test('sensitive getters may be denied without inventing metadata', async () => {
  const guarded = { ...app }; Object.defineProperty(guarded, 'packageId', { get() { throw { name: 'SecurityError' }; } });
  const result = await collect({ application: { getAppsInfo: success => success([guarded]) } }); assert.equal(result.apps[0].packageID, undefined);
});
test('inventory never invokes privileged package-management functions', async () => {
  const forbidden = () => assert.fail('A privileged operation was called');
  await collect({ application: { getAppsInfo: success => success([app]), kill: forbidden, launch: forbidden }, package: { getPackagesInfo: success => success([]), uninstall: forbidden, install: forbidden } });
});
