// Rasterizes the project's own simple geometric icon. No external images/fonts.
import { deflateSync } from 'node:zlib';
import { writeFile, mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
function chunk(type, bytes) { const tag = Buffer.from(type); const size = Buffer.alloc(4); size.writeUInt32BE(bytes.length); const checksum = Buffer.alloc(4); checksum.writeUInt32BE(crc32(Buffer.concat([tag, bytes]))); return Buffer.concat([size, tag, bytes, checksum]); }
function inside(x, y, polygon) { let yes = false; for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) { const a = polygon[i], b = polygon[j]; if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) yes = !yes; } return yes; }
const shield = [[.5,.15],[.78,.26],[.78,.47],[.75,.61],[.68,.72],[.59,.80],[.5,.86],[.41,.80],[.32,.72],[.25,.61],[.22,.47],[.22,.26]];
const tick = [[.35,.48],[.43,.56],[.64,.35],[.69,.40],[.43,.67],[.30,.53]];
function render(size) {
  const bytes = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y++) {
    const row = y * (size * 3 + 1); bytes[row] = 0;
    for (let x = 0; x < size; x++) {
      const sum = [0,0,0];
      for (const sx of [.25,.75]) for (const sy of [.25,.75]) {
        const px = (x + sx) / size, py = (y + sy) / size;
        let color = [6, 35 + 22 * (1 - py), 49 + 16 * (1 - px)];
        if (inside(px, py, shield)) color = px < .5 ? [67,214,197] : [16,133,143];
        if (inside(px, py, tick)) color = [255,255,255];
        for (let c = 0; c < 3; c++) sum[c] += color[c];
      }
      for (let c = 0; c < 3; c++) bytes[row + 1 + x * 3 + c] = Math.round(sum[c] / 4);
    }
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(size,0); header.writeUInt32BE(size,4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk('IHDR',header), chunk('IDAT',deflateSync(bytes)), chunk('IEND',Buffer.alloc(0))]);
}
await mkdir(resolve(root, 'ios/TVGuardian/Assets.xcassets/AppIcon.appiconset'), { recursive:true });
await writeFile(resolve(root, 'ios/TVGuardian/Assets.xcassets/AppIcon.appiconset/AppIcon.png'),render(1024));
await writeFile(resolve(root,'companion/icon.png'),render(512));
console.log('Generated opaque iOS and Tizen app icons.');
