import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const escapeXml = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const source = file => escapeXml(fs.readFileSync(path.join(root, 'src', file), 'utf8'));
const child = name => `<Item class="ModuleScript" referent="${name}"><Properties><string name="Name">${name}</string><ProtectedString name="Source">${source(`${name}.luau`)}</ProtectedString></Properties></Item>`;
const xml = `<?xml version="1.0" encoding="utf-8"?>
<roblox version="4"><Item class="ModuleScript" referent="RemoteGuard"><Properties><string name="Name">RemoteGuard</string><ProtectedString name="Source">${source('init.luau')}</ProtectedString></Properties>${child('Validate')}${child('RateLimiter')}</Item></roblox>\n`;
fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
fs.writeFileSync(path.join(root, 'dist', 'RemoteGuard.rbxmx'), xml, 'utf8');
console.log('Built dist/RemoteGuard.rbxmx from the current source files.');
