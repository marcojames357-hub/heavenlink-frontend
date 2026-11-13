'use strict';
// Run after building with the API and demo flags documented below.
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn, spawnSync } = require('child_process');
const frontend = path.resolve(__dirname, '..');
const bundledBackend = path.join(frontend, 'heavenlink-backend');
const backend = fs.existsSync(path.join(bundledBackend, 'node_modules'))
  ? bundledBackend : path.resolve(frontend, '../heavenlink-backend');
const logs = path.resolve(frontend, '../migration-backups/backend-demo-audit');
fs.mkdirSync(logs, { recursive: true });
function request(port, route) {
  return new Promise(resolve => {
    const req = http.get({ hostname: '127.0.0.1', port, path: route, timeout: 1500 }, res => {
      let body = ''; res.on('data', chunk => body += chunk);
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', () => resolve(null)); req.on('timeout', () => req.destroy());
  });
}
function start(file, cwd, name) {
  const descriptor = fs.openSync(path.join(logs, name), 'a');
  const child = spawn(process.execPath, [file], {
    cwd, detached: true, windowsHide: true, stdio: ['ignore', descriptor, descriptor]
  });
  child.unref(); fs.closeSync(descriptor); return child.pid;
}
async function ready(port, route) {
  for (let i = 0; i < 30; i++) {
    const response = await request(port, route);
    if (response?.status === 200) return response;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error(`Port ${port} did not become ready. See ${logs}`);
}
(async () => {
  const buildFile = path.join(frontend, 'build/web/main.dart.js');
  if (!fs.existsSync(buildFile) || !fs.readFileSync(buildFile, 'utf8').includes('http://localhost:3001')) {
    throw new Error('Build the connected demo first: flutter build web --no-wasm-dry-run --dart-define=HAVEN_API_BASE_URL=http://localhost:3001 --dart-define=HAVEN_DEMO_MODE=true');
  }
  const { validateRuntimeTarget } = require(path.join(backend, 'src/seedDemo'));
  const database = path.join(backend, 'data/havenlink-demo.sqlite');
  if (!fs.existsSync(database)) {
    const seeded = spawnSync(process.execPath, [path.join(backend, 'src/seedDemo.js')], { cwd: backend, stdio: 'inherit', windowsHide: true });
    if (seeded.status !== 0) throw new Error('The isolated demo seed did not complete.');
  }
  await validateRuntimeTarget();
  let api = await request(3001, '/health');
  if (api && (api.status !== 200 || JSON.parse(api.body).mode !== 'local-demo')) throw new Error('Port 3001 is occupied by another service. No process was changed.');
  if (!api) { start(path.join(backend, 'src/demoServer.js'), backend, 'demo-api.log'); api = await ready(3001, '/health'); }
  if (JSON.parse(api.body).mode !== 'local-demo') throw new Error('The API is not the isolated demo runtime.');
  let web = await request(8080, '/');
  if (web && !web.body.includes('Haven Link')) throw new Error('Port 8080 is occupied by another service. No process was changed.');
  if (!web) { start(path.join(__dirname, 'serve_web_build.js'), frontend, 'demo-web.log'); await ready(8080, '/'); }
  console.log('Haven Link connected local demo: http://localhost:8080');
  console.log('Demo API health: http://localhost:3001/health');
  console.log('Demo accounts: heavenlink-backend/docs/LOCAL_DEMO.md');
  console.log('Your original havenlink.sqlite and .env are not modified.');
})().catch(error => { console.error(error.message); process.exitCode = 1; });
