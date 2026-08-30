import fs from 'node:fs/promises';
import assert from 'node:assert/strict';

for (const key of Object.keys(process.env)) {
  if (key.startsWith('ALERA_')) delete process.env[key];
}
Object.assign(process.env, {
  ALERA_AGENT_HOOK_PORT: '1', ALERA_AGENT_HOOK_TOKEN: 'fixture',
  ALERA_TERMINAL_SESSION_ID: 'fixture', ALERA_WORKSPACE_ID: 'fixture', ALERA_TAB_ID: 'fixture',
});
let emitted = [];
globalThis.fetch = async (_url, options) => {
  emitted.push(JSON.parse(options.body).payload);
  return {};
};

for (const kind of ['opencode', 'opencode2', 'pi']) {
  for (const implementation of ['rust', 'dart']) {
    const file = implementation === 'rust'
      ? `rust/alera-cli/src/agent_status/integration_plugins/${kind}.${kind === 'pi' ? 'ts' : 'js'}`
      : `lib/src/features/agent_status/infra/managed_hooks/${kind}_managed_agent_hook.dart`;
    let source = await fs.readFile(file, 'utf8');
    if (implementation === 'dart') source = source.match(/r'''([\s\S]*?)'''/)[1];
    const module = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
    emitted = [];
    if (kind === 'pi') {
      const callbacks = {};
      module.default({ on: (name, callback) => { callbacks[name] = callback; } });
      const context = { sessionManager: { getSessionId: () => 'one' } };
      await callbacks.session_start({}, context);
      await callbacks.before_agent_start({ prompt: 'Fix login' }, context);
      await callbacks.session_shutdown({}, context);
      assert.equal(emitted.length, 3);
      assert(emitted.every(e => e.sessionId === 'one'));
      assert(emitted.some(e => e.prompt === 'Fix login'));
    } else {
      const lookups = new Map();
      const get = async id => {
        lookups.set(id, (lookups.get(id) ?? 0) + 1);
        if (id === 'failure') throw new Error('Unavailable');
        if (id === 'slow') return new Promise(() => {});
        if (id === 'unknown') return undefined;
        if (id === 'retry' && lookups.get(id) === 1) return undefined;
        return { id, ...(id === 'child' ? { parentID: 'one' } : {}) };
      };
      const sessions = ['one', 'child', 'unknown', 'failure', 'slow', 'retry', 'retry', 'one', 'two'];
      if (kind === 'opencode') {
        const plugin = await module.AleraOpenCodeStatusPlugin({
          client: { session: { get: async ({ path }) => ({ data: await get(path.id) }) } },
        });
        for (const id of sessions) {
          await plugin.event({ event: { type: 'message.updated', properties: { info: { id: 'message', role: 'user' } } } });
          await plugin.event({ event: { type: 'message.part.updated', properties: { part: { messageID: 'message', type: 'text', text: 'Fix login', sessionID: id } } } });
          await plugin.event({ event: { type: 'session.status', properties: { sessionID: id, status: { type: 'busy' } } } });
        }
        await plugin.event({ event: { type: 'permission.asked', properties: { sessionID: 'child' } } });
      } else {
        await module.default.setup({
          session: { get: ({ sessionID }) => get(sessionID) },
          event: { subscribe: async function* () {
            for (const id of sessions) yield { type: 'session.input.admitted', sessionId: id, data: { input: { data: { text: 'Fix login' } } } };
            yield { type: 'permission.asked', data: { sessionID: 'child' } };
          } },
        });
      }
      assert(emitted.some(e => e.role === 'user' && e.sessionId === 'one' && !e.agentTitleIgnore));
      assert(emitted.some(e => e.hook_event_name === 'SessionBusy' && e.sessionId === 'two' && !e.agentTitleIgnore));
      assert(emitted.some(e => e.role === 'user' && e.sessionId === 'child' && e.parent_session_id === 'one'));
      assert(emitted.some(e => e.hook_event_name === 'PermissionRequest' && e.parent_session_id === 'one'));
      for (const id of ['unknown', 'failure', 'slow']) {
        assert(emitted.filter(e => e.sessionId === id).every(e => e.agentTitleIgnore === true));
      }
      assert(emitted.some(e => e.sessionId === 'retry' && e.agentTitleIgnore));
      assert(emitted.some(e => e.sessionId === 'retry' && !e.agentTitleIgnore));
      assert.equal(lookups.get('one'), 1);
      assert.equal(lookups.get('child'), 1);
    }
    console.log(`${kind} ${implementation}: identity, prompt, and hierarchy guards passed`);
  }
}
