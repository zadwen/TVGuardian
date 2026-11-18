import test from 'node:test';
import assert from 'node:assert/strict';
import { readdir, readFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, relative } from 'node:path';
const root = fileURLToPath(new URL('../../', import.meta.url));
async function swiftFiles(directory) {
  const result = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    const path = resolve(directory, item.name);
    if (item.isDirectory()) result.push(...await swiftFiles(path)); else if (item.name.endsWith('.swift')) result.push(path);
  }
  return result;
}
test('structural check: generated project references every Swift source and a shared test scheme', async () => {
  const project = await readFile(resolve(root, 'ios/TVGuardian.xcodeproj/project.pbxproj'), 'utf8');
  for (const file of await swiftFiles(resolve(root, 'ios'))) {
    const path = relative(resolve(root, 'ios'), file).replaceAll('\\', '/'); assert.ok(project.includes(JSON.stringify(path)), path);
  }
  assert.ok(project.includes('com.apple.product-type.application')); assert.ok(project.includes('com.apple.product-type.bundle.unit-test'));
  assert.ok(project.includes('com.apple.product-type.bundle.ui-testing'));
  const scheme = await readFile(resolve(root, 'ios/TVGuardian.xcodeproj/xcshareddata/xcschemes/TVGuardian.xcscheme'), 'utf8');
  assert.ok(scheme.includes('TVGuardianUITests.xctest'));
  await access(resolve(root, 'ios/TVGuardian.xcodeproj/xcshareddata/xcschemes/TVGuardian.xcscheme'));
});
test('structural check: companion requests only public inventory and internet privileges', async () => {
  const xml = await readFile(resolve(root, 'companion/config.xml'), 'utf8');
  const privileges = [...xml.matchAll(/<tizen:privilege name="([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(privileges.sort(), ['application.info', 'internet', 'package.info'].map(p => 'http://tizen.org/privilege/' + p).sort());
  assert.match(xml, /background-support="disable"/);
});
test('structural check: production bridge has TLS requirements and no plaintext listener', async () => {
  const source = await readFile(resolve(root, 'bridge/src/server.mjs'), 'utf8');
  assert.match(source, /node:https/); assert.match(source, /minVersion: 'TLSv1.2'/); assert.ok(!source.includes('node:http\''));
});
test('structural check: opaque icons have correct iOS/Tizen sizes', async () => {
  for (const [path, size] of [['ios/TVGuardian/Assets.xcassets/AppIcon.appiconset/AppIcon.png', 1024], ['companion/icon.png',512]]) {
    const png = await readFile(resolve(root, path)); assert.equal(png.readUInt32BE(16), size); assert.equal(png.readUInt32BE(20), size); assert.equal(png[25],2);
  }
});
