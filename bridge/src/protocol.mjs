export class HTTPError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const bad = message => { throw new HTTPError(400, 'invalid_request', message); };
export function text(value, max, field) {
  if (typeof value !== 'string' || value.length === 0 || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) bad('Invalid ' + field + '.');
  return value;
}
export function onlyKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k))) bad('Unexpected request fields.');
}
export function validateSnapshot(value) {
  onlyKeys(value, ['protocolVersion', 'inventoryStatus', 'complete', 'apps', 'errors']);
  if (value.protocolVersion !== 1 || value.complete !== false ||
      !['supported', 'unsupported', 'unverified'].includes(value.inventoryStatus) ||
      !Array.isArray(value.apps) || value.apps.length > 2000 || !Array.isArray(value.errors) || value.errors.length > 20) bad('Invalid inventory envelope.');
  if (value.inventoryStatus !== 'supported' && value.apps.length !== 0) bad('Unverified inventories cannot contain asserted app entries.');
  const seen = new Set();
  const apps = value.apps.map(app => {
    onlyKeys(app, ['id', 'name', 'packageID', 'iconPath']);
    const id = text(app.id, 256, 'app ID');
    if (!/^[A-Za-z0-9._-]+$/.test(id) || seen.has(id)) bad('Invalid or duplicate app ID.');
    seen.add(id);
    const result = { id, name: text(app.name, 160, 'app name') };
    if (app.packageID != null) result.packageID = text(app.packageID, 256, 'package ID');
    if (app.iconPath != null) result.iconPath = text(app.iconPath, 512, 'icon path');
    return result;
  });
  return { protocolVersion: 1, inventoryStatus: value.inventoryStatus, complete: false, apps,
    errors: value.errors.map(error => text(error, 300, 'API error')) };
}

export async function readJSON(request, maximum = 512_000) {
  if (!(request.headers['content-type'] ?? '').toLowerCase().startsWith('application/json')) throw new HTTPError(415, 'content_type', 'Use application/json.');
  let count = 0;
  const chunks = [];
  for await (const chunk of request) {
    count += chunk.length;
    if (count > maximum) throw new HTTPError(413, 'body_too_large', 'Request exceeds the size limit.');
    chunks.push(chunk);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new HTTPError(400, 'invalid_json', 'Malformed JSON.'); }
}
