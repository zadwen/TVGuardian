import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import { dirname } from 'node:path';
import { randomUUID } from 'node:crypto';

export function validateState(value) {
  if (!value || value.schemaVersion !== 1 || !Array.isArray(value.companions) || value.companions.length > 20) {
    throw new Error('Unsupported or corrupt bridge state. Preserve the data; it will not be reset automatically.');
  }
  for (const record of value.companions) {
    if (!record || typeof record.companionID !== 'string' || !/^[a-f0-9-]{36}$/.test(record.companionID) ||
        typeof record.tokenHash !== 'string' || !/^[a-f0-9]{64}$/.test(record.tokenHash) ||
        !Number.isFinite(record.expiresAt) || typeof record.name !== 'string' || !Number.isFinite(record.receivedAt)) {
      throw new Error('Invalid companion record in bridge state.');
    }
  }
  return value;
}

export class PersistentStore {
  #state;
  #queue = Promise.resolve();
  constructor(state, persist = async () => {}) { this.#state = validateState(structuredClone(state)); this.persist = persist; }
  read() { return structuredClone(this.#state); }
  transaction(change) {
    const result = this.#queue.then(async () => {
      const next = structuredClone(this.#state);
      const value = await change(next);
      validateState(next);
      await this.persist(next);
      this.#state = next;
      return value;
    });
    this.#queue = result.catch(() => {});
    return result;
  }
  static async open(file) {
    let initial;
    try {
      const data = await readFile(file);
      if (data.length > 16_000_000) throw new Error('Bridge state is too large.');
      initial = JSON.parse(data.toString('utf8'));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      initial = { schemaVersion: 1, companions: [] };
    }
    await mkdir(dirname(file), { recursive: true, mode: 0o700 });
    return new PersistentStore(initial, async state => {
      const temporary = file + '.' + randomUUID() + '.tmp';
      await writeFile(temporary, JSON.stringify(state), { mode: 0o600, flag: 'wx' });
      await rename(temporary, file);
    });
  }
}
