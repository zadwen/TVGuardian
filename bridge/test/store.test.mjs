import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { join, resolve, relative, basename } from 'node:path';
import { tmpdir } from 'node:os';
import { PersistentStore } from '../src/store.mjs';
async function cleanup(directory) {
  const absolute = resolve(directory), within = relative(resolve(tmpdir()), absolute);
  assert.ok(within && !within.startsWith('..') && !within.includes(':') && basename(absolute).startsWith('tvguardian-'));
  await rm(absolute, { recursive: true, force: true });
}
test('failed persistence cannot publish an in-memory success', async () => {
  const store = new PersistentStore({ schemaVersion: 1, companions: [] }, async () => { throw new Error('fixture disk failure'); });
  await assert.rejects(store.transaction(state => { state.fixture = true; })); assert.equal(store.read().fixture, undefined);
});
test('transactions serialize simultaneous changes without lost updates', async () => {
  const store = new PersistentStore({ schemaVersion: 1, companions: [] });
  await Promise.all(Array.from({ length: 20 }, (_, i) => store.transaction(async state => { await Promise.resolve(); state.counter = (state.counter ?? 0) + 1; })));
  assert.equal(store.read().counter, 20);
});
test('saved state survives restart and read results cannot mutate it', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'tvguardian-test-')); t.after(() => cleanup(directory));
  const file = join(directory, 'state.json'); const store = await PersistentStore.open(file);
  await store.transaction(state => { state.counter = 5; });
  const restored = await PersistentStore.open(file); assert.equal(restored.read().counter, 5);
  const copy = restored.read(); copy.counter = 10; assert.equal(restored.read().counter, 5);
});
test('corrupt data is never silently reset', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'tvguardian-corrupt-')); t.after(() => cleanup(directory));
  const file = join(directory, 'state.json'); await writeFile(file, 'broken fixture');
  await assert.rejects(PersistentStore.open(file)); assert.equal(await readFile(file, 'utf8'), 'broken fixture');
});
