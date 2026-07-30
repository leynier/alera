import { describe, expect, test } from 'bun:test';
import { handleRequest, type EdgeEnvironment } from '../src/index';

function environment(success = true): EdgeEnvironment {
  return {
    EDGE_BURST_LIMITER: {
      async limit() {
        return { success };
      },
    },
    EDGE_ORIGIN_TOKEN: 'edge-secret',
    ORIGIN_BASE_URL: 'https://alera-cloud.example.run.app',
  };
}

describe('Alera API edge', () => {
  test('rejects paths outside the public API', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/admin'),
      environment(),
    );
    expect(response.status).toBe(404);
  });

  test('rejects unsupported methods', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/account', { method: 'PATCH' }),
      environment(),
    );
    expect(response.status).toBe(405);
  });

  test('overwrites the origin credential and routes to Cloud Run', async () => {
    const request = new Request('https://api.alera.build/v1/account?view=full', {
      headers: {
        authorization: 'Bearer account-token',
        cookie: 'must-not-cross-the-edge=1',
        'x-alera-origin-auth': 'attacker-value',
      },
      method: 'POST',
    });

    const response = await handleRequest(request, environment(), async (originRequest) => {
      const proxied = originRequest as Request;
      expect(proxied.url).toBe(
        'https://alera-cloud.example.run.app/v1/account?view=full',
      );
      expect(proxied.headers.get('x-alera-origin-auth')).toBe('edge-secret');
      expect(proxied.headers.get('authorization')).toBe(
        'Bearer account-token',
      );
      expect(proxied.headers.get('cookie')).toBeNull();
      return new Response('ok');
    });

    expect(response.status).toBe(200);
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
  });

  test('rate limits mutating requests before reaching the origin', async () => {
    let originCalled = false;
    const response = await handleRequest(
      new Request('https://api.alera.build/v1/auth/exchange', {
        method: 'POST',
      }),
      environment(false),
      async () => {
        originCalled = true;
        return new Response('unexpected');
      },
    );

    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect(originCalled).toBeFalse();
  });

  test('maps an unreachable origin to a bounded error', async () => {
    const response = await handleRequest(
      new Request('https://api.alera.build/health'),
      environment(),
      async () => {
        throw new Error('network unavailable');
      },
    );
    expect(response.status).toBe(502);
  });
});
