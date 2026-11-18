// Ephemeral test-only X.509 fixture, generated in memory with Node crypto.
// No signing key or usable certificate is hardcoded or shipped in production.
import { generateKeyPairSync, randomBytes, sign } from 'node:crypto';
const concatenate = values => Buffer.concat(values);
function der(tag, bytes) {
  const value = Buffer.isBuffer(bytes) ? bytes : concatenate(bytes);
  let length;
  if (value.length < 128) length = Buffer.from([value.length]);
  else { const octets = []; let size = value.length; while (size) { octets.unshift(size & 255); size >>>= 8; } length = Buffer.from([0x80 | octets.length, ...octets]); }
  return concatenate([Buffer.from([tag]), length, value]);
}
const sequence = (...values) => der(0x30, values);
function oid(value) {
  const parts = value.split('.').map(Number), bytes = [40 * parts[0] + parts[1]];
  for (const part of parts.slice(2)) { let remaining = part; const encoded = [remaining & 127]; while ((remaining >>>= 7)) encoded.unshift((remaining & 127) | 128); bytes.push(...encoded); }
  return der(6, Buffer.from(bytes));
}
const pem = (label, bytes) => `-----BEGIN ${label}-----\n${bytes.toString('base64').match(/.{1,64}/g).join('\n')}\n-----END ${label}-----\n`;
function utc(date) { return der(0x17, Buffer.from(date.toISOString().replace(/[-:]/g, '').replace('T', '').slice(2, 14) + 'Z')); }
export function makeTLSFixture() {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const algorithm = sequence(oid('1.2.840.113549.1.1.11'), der(5, Buffer.alloc(0)));
  const name = sequence(der(0x31, [sequence(oid('2.5.4.3'), der(0x0c, Buffer.from('localhost')))]));
  const alternativeNames = sequence(der(0x82, Buffer.from('localhost')), der(0x87, Buffer.from([127,0,0,1])));
  const extensions = der(0xa3, [sequence(sequence(oid('2.5.29.17'), der(4, alternativeNames)))]);
  const serial = randomBytes(16); serial[0] = (serial[0] & 0x7f) | 1;
  const tbs = sequence(der(0xa0, [der(2, Buffer.from([2]))]), der(2, serial),
    algorithm, name, sequence(utc(new Date(Date.now() - 60_000)), utc(new Date(Date.now() + 86_400_000))), name,
    publicKey.export({ type: 'spki', format: 'der' }), extensions);
  const certificate = sequence(tbs, algorithm, der(3, Buffer.concat([Buffer.from([0]), sign('RSA-SHA256', tbs, privateKey)])));
  return { cert: pem('CERTIFICATE', certificate), key: privateKey.export({ type: 'pkcs8', format: 'pem' }) };
}
