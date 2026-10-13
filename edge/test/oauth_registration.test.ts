import { expect, test } from 'bun:test';
import { handleRequest } from '../src/index';
import { environment } from './relay_fixture';

test('registration has a separate ten-per-minute limiter keyed only by address', async () => {
  const config = JSON.parse(await Bun.file(new URL('../wrangler.jsonc', import.meta.url)).text());
  const binding = config.ratelimits.find((entry: { name: string }) => entry.name === 'OAUTH_REGISTRATION_LIMITER');
  expect(binding.simple).toEqual({ limit: 10, period: 60 });
  const counts = new Map<string, number>();
  const forwarded: string[] = [];
  const env = {
    ...environment(),
    OAUTH_REGISTRATION_LIMITER: {
      async limit({ key }: { key: string }) {
        const count = (counts.get(key) ?? 0) + 1;
        counts.set(key, count);
        return { success: count <= binding.simple.limit };
      },
    },
    OAUTH_LIMITER: {
      async limit() { return { success: true }; },
    },
  };
  const send = (path: string, address = '203.0.113.9', method = 'POST', authorization = '') => handleRequest(
    new Request(`https://api.alera.build${path}`, {
      method,
      headers: { 'cf-connecting-ip': address, authorization },
    }),
    env,
    async (request) => {
      forwarded.push(new URL(request.url).pathname);
      return new Response('ok');
    },
  );
  expect((await send('/oauth/register', undefined, 'OPTIONS')).status).toBe(204);
  expect(counts.size).toBe(0);
  for (let i = 0; i < 10; i++) {
    expect((await send('/oauth/register', undefined, 'POST', `Bearer forged-${i}`)).status).toBe(200);
  }
  const limited = await send('/oauth/register');
  expect(limited.status).toBe(429);
  expect(limited.headers.get('retry-after')).toBe('60');
  expect(limited.headers.get('access-control-allow-origin')).toBe('*');
  expect(forwarded).toHaveLength(10);
  expect([...counts.keys()]).toEqual(['address:203.0.113.9:/oauth/register']);
  expect((await send('/oauth/register', '203.0.113.10')).status).toBe(200);
  expect((await send('/oauth/token')).status).toBe(200);
  expect((await send('/oauth/revoke')).status).toBe(200);
  expect(counts.get('address:203.0.113.9:/oauth/register')).toBe(11);
});

test('registration without the dedicated binding still limits by address', async () => {
  const keys: string[] = [];
  const response = await handleRequest(
    new Request('https://api.alera.build/oauth/register', {
      method: 'POST',
      headers: { 'cf-connecting-ip': '203.0.113.9', authorization: 'Bearer forged' },
    }),
    {
      ...environment(),
      EDGE_BURST_LIMITER: {
        async limit({ key }: { key: string }) {
          keys.push(key);
          return { success: false };
        },
      },
    },
    async () => { throw new Error('Limited registration must not reach the origin'); },
  );
  expect(response.status).toBe(429);
  expect(response.headers.get('access-control-allow-origin')).toBe('*');
  expect(keys).toEqual(['address:203.0.113.9:/oauth/register']);
});
