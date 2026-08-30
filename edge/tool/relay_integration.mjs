import { Miniflare } from 'miniflare';
import { build } from 'esbuild';
import { createServer } from 'node:http';
import { generateKeyPairSync, createPrivateKey, createPublicKey, sign, randomUUID } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const seconds = Number(process.argv[2] ?? 20);
const faultMode = process.argv[3] === 'faults';
if (!Number.isInteger(seconds) || seconds < 10 || seconds > 86400)
  throw new Error('Duration must be 10..86400 seconds');
const signing = generateKeyPairSync('ed25519');
const jwk = signing.publicKey.export({ format: 'jwk' });
function identity(seed) {
  const privateKey = createPrivateKey({
    key: Buffer.concat([Buffer.from('302e020100300506032b656e04220420', 'hex'), Buffer.alloc(32, seed)]),
    type: 'pkcs8',
    format: 'der',
  });
  return createPublicKey(privateKey).export({ format: 'jwk' }).x;
}
let edgeUrl;
let done = false;
let runtimeGrants = 0;
let mobileGrants = 0;
let evictions = 0;
const firstGrant = new Set();
function grant(role, clientId) {
  const now = Math.floor(Date.now() / 1000);
  const key = `${role}:${clientId}`;
  const lifetime = firstGrant.has(key) ? 120 : 35;
  firstGrant.add(key);
  if (role === 'runtime') runtimeGrants++;
  else mobileGrants++;
  const claims = {
    iss: 'https://relay-fixture.test',
    aud: 'alera-relay',
    exp: now + lifetime,
    iat: now,
    nbf: now,
    jti: randomUUID(),
    accountId: 'fixture-account',
    runtimeId: 'fixture-runtime',
    clientId,
    role,
    keyVersion: 1,
    clientPublicKey: identity(role === 'runtime' ? 2 : 7),
    runtimePublicKey: identity(2),
  };
  const payload = [
    Buffer.from(JSON.stringify({ alg: 'EdDSA', typ: 'relay+jwt', kid: 'fixture' })).toString('base64url'),
    Buffer.from(JSON.stringify(claims)).toString('base64url'),
  ].join('.');
  return {
    grant: `${payload}.${sign(null, Buffer.from(payload), signing.privateKey).toString('base64url')}`,
    relayUrl: `${edgeUrl.replace('http:', 'ws:')}/v1/relay/fixture-runtime`,
    expiresIn: lifetime,
    accountId: claims.accountId,
    runtimeId: claims.runtimeId,
    clientId,
    clientKind: role,
    clientKeyVersion: 1,
    clientPublicKey: claims.clientPublicKey,
    runtimePublicKey: role === 'mobile' ? claims.runtimePublicKey : null,
  };
}
const origin = createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  response.setHeader('content-type', 'application/json');
  if (url.pathname === '/.well-known/jwks.json')
    response.end(JSON.stringify({ keys: [{ ...jwk, kid: 'fixture', alg: 'EdDSA' }] }));
  else if (url.pathname === '/fixture/grant')
    response.end(
      JSON.stringify(
        grant(url.searchParams.get('role') ?? 'mobile', url.searchParams.get('client') ?? 'phone-0'),
      ),
    );
  else if (url.pathname === '/fixture/done') {
    if (request.method === 'POST') done = true;
    response.end(JSON.stringify({ done }));
  } else if (url.pathname === '/fixture/hibernate' && request.method === 'POST') {
    try {
      await mf.unsafeEvictDurableObject('relay-fixture', 'RuntimeRelayDurableObject', {
        name: 'fixture-runtime',
        webSockets: 'hibernate',
      });
      evictions++;
      response.end(JSON.stringify({ evictions }));
    } catch {
      response.statusCode = 500;
      response.end('{"error":"fixture_eviction_failed"}');
    }
  } else if (url.pathname === '/fixture/stats')
    response.end(JSON.stringify({ runtimeGrants, mobileGrants, evictions }));
  else {
    response.statusCode = 404;
    response.end('{}');
  }
});
await new Promise((resolve) => origin.listen(0, '127.0.0.1', resolve));
const originUrl = `http://127.0.0.1:${origin.address().port}`;
const bundled = await build({
  entryPoints: [path.join(root, 'edge/src/index.ts')],
  bundle: true,
  write: false,
  format: 'esm',
  platform: 'browser',
});
const mf = new Miniflare({
  name: 'relay-fixture',
  modules: true,
  script: bundled.outputFiles[0].text,
  compatibilityDate: '2026-07-27',
  durableObjects: { RELAY_OBJECTS: 'RuntimeRelayDurableObject' },
  bindings: {
    RELAY_ENABLED: 'true',
    EDGE_ORIGIN_TOKEN: 'fixture-only',
    ORIGIN_BASE_URL: originUrl,
    RELAY_ISSUER: 'https://relay-fixture.test',
    RELAY_JWKS_URL: `${originUrl}/.well-known/jwks.json`,
  },
});
const children = [];
function launch(command, args, cwd) {
  const child = spawn(command, args, {
    cwd,
    env: {
      ...process.env,
      ALERA_RELAY_TEST_ORIGIN: originUrl,
      ALERA_RELAY_TEST_SECONDS: String(seconds),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  children.push(child);
  child.stdout.on('data', (data) => process.stdout.write(data));
  child.stderr.on('data', (data) => process.stderr.write(data));
  child.finished = new Promise((resolve, reject) => {
    child.on('error', reject);
    child.on('exit', (code, signal) =>
      code === 0 ? resolve() : reject(new Error(`${command} exited ${code ?? signal}`)),
    );
  });
  child.finished.catch(() => {});
  return child;
}
try {
  edgeUrl = (await mf.ready).origin;
  console.log(`Relay integration: Rust + Dart + workerd, ${seconds}s`);
  await launch(
    'cargo',
    [
      'test',
      '--manifest-path',
      'rust/Cargo.toml',
      '--locked',
      '-p',
      'alera-cli',
      '--bin',
      'alera',
      '--no-run',
    ],
    root,
  ).finished;
  const rust = launch(
    'cargo',
    [
      'test',
      '--manifest-path',
      'rust/Cargo.toml',
      '--locked',
      '-p',
      'alera-cli',
      '--bin',
      'alera',
      'relay_cross_language_fixture',
      '--',
      '--ignored',
      '--nocapture',
    ],
    root,
  );
  await Promise.race([
    new Promise((resolve) =>
      rust.stdout.on('data', (data) => {
        if (data.toString().includes('RELAY_FIXTURE_READY')) resolve();
      }),
    ),
    rust.finished.then(() => {
      throw new Error('Runtime fixture exited before readiness');
    }),
    new Promise((_, reject) => {
      const timer = setTimeout(() => reject(new Error('Runtime fixture readiness timed out')), 180000);
      timer.unref();
    }),
  ]);
  const flutter = launch(
    process.env.FLUTTER_BIN ?? 'flutter',
    [
      'test',
      '--reporter',
      'expanded',
      '--timeout',
      `${seconds + 90}s`,
      faultMode ? 'test/relay_adversarial_end_to_end_test.dart' : 'test/relay_end_to_end_test.dart',
    ],
    path.join(root, 'mobile'),
  );
  await flutter.finished;
  console.log(JSON.stringify({ runtimeGrants, mobileGrants, evictions }));
  done = true;
  await rust.finished;
} finally {
  done = true;
  await Promise.allSettled(children.map((child) => child.finished));
  await mf.dispose();
  await new Promise((resolve) => origin.close(resolve));
}
