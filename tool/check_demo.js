'use strict';
// Real HTTP smoke checks against the explicitly isolated local demo runtime.
const assert = require('assert/strict');
const fs = require('fs');
const path = require('path');
const origin = 'http://127.0.0.1:3001';
async function api(route, token, body) {
  const response = await fetch(origin + route, { method: body ? 'POST' : 'GET',
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body ? { 'content-type': 'application/json' } : {}), origin: 'http://localhost:8080' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(10000) });
  return { response, body: await response.json() };
}
(async () => {
  const health = await api('/health'); assert.equal(health.body.mode, 'local-demo');
  const publicListings = await api('/api/v1/properties'); assert.equal(publicListings.response.status, 200);
  assert.equal(publicListings.response.headers.get('access-control-allow-origin'), 'http://localhost:8080');
  assert.equal(publicListings.body.properties.length, 10);
  const rentals = publicListings.body.properties.filter(p => p.businessModel === 'contactUnlock');
  assert.equal(rentals.length, 3);
  for (const p of rentals) { assert.ok(!p.latitude && !p.longitude); assert.ok(!p.formattedAddress); assert.ok(!p.ownerContact); }
  const summary = { health: 'ok', publicListings: 10, protectedRentalLocations: 'locked', accounts: [] };
  for (const [name, role, expectedListings] of [['customer','CUSTOMER',0],['rental','RENTAL_AGENT',3],['apartment','STAY_AGENT',3],['hotel','STAY_AGENT',4],['admin','ADMIN',10]]) {
    const login = await api('/api/v1/auth/sign-in', null, { email: `${name}@demo.havenlink.test`, password: 'HavenDemo!2026' });
    assert.equal(login.response.status, 200, `${name} sign-in`); assert.equal(login.body.user.role, role); assert.ok(login.body.token);
    const token = login.body.token;
    if (name === 'customer') {
      const bookings = await api('/api/v1/bookings', token); assert.equal(bookings.response.status, 200);
      const contact = await api(`/api/v1/properties/${rentals[0].id}/contact`, token); assert.equal(contact.response.status, 403);
      const admin = await api('/api/v1/admin/dashboard', token); assert.equal(admin.response.status, 403);
    } else if (name === 'admin') {
      const dashboard = await api('/api/v1/admin/dashboard', token); assert.equal(dashboard.response.status, 200);
      assert.equal(dashboard.body.stats.users.total, 5); assert.equal(dashboard.body.stats.properties.total, 10);
    } else {
      const listings = await api('/api/v1/agents/listings', token); assert.equal(listings.response.status, 200);
      assert.equal(listings.body.listings.length, expectedListings, `${name} listing count`);
      if (name === 'hotel') {
        const rooms = await api(`/api/v1/agents/rooms/${listings.body.listings[0].id}`, token); assert.equal(rooms.response.status, 200);
      }
    }
    summary.accounts.push({ workspace: name, login: 'ok', role });
  }
  const sms = await api('/api/v1/otp/request', null, {phoneE164:'+255700900099',sessionId:'local-demo-smoke-no-sms'});
  assert.equal(sms.response.status, 503); summary.sms = 'unconfigured; verification guard retained';
  if (!process.argv.includes('--api-only')) {
    const web = await fetch('http://127.0.0.1:8080/'); assert.equal(web.status, 200);
    const code = await fetch('http://127.0.0.1:8080/main.dart.js').then(r => r.text());
    assert.ok(code.includes('http://localhost:3001'), 'The served release must include the API URL.');
    assert.ok(code.includes('LOCAL DEMO'), 'The served release must show the demo label.');
    summary.servedFrontend = 'backend-connected demo build';
  }
  const result = JSON.stringify(summary, null, 2);
  fs.writeFileSync(path.resolve(__dirname, '../../migration-backups/backend-demo-audit/live-smoke.json'), result + '\n');
  console.log(result);
})().catch(error => { console.error('Local demo verification failed:', error.message); process.exitCode = 1; });
