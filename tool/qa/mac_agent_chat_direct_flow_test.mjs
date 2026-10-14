import assert from 'node:assert/strict';
import test from 'node:test';
import {inspectMacAgentChatDirectReply, runMacAgentChatDirectFlow} from './mac_agent_chat_direct_flow.mjs';

const BUNDLE = 'dev.leynier.alera.agentqa.mock';
const MARKER = 'DIRECT-CHAT-QA-MOCK';
const PROMPT = `Reply with ${MARKER}. Do not read files or execute tools.`;
const CHAT = 'QA Direct Chat';
const MODEL = 'Mock Model';

function fixture(context, options = {}) {
  context.mock.timers.enable({apis: ['Date', 'setTimeout'], now: 1000});
  let phase = options.entry === 'add-tab' ? 'tabs' : options.entry === 'existing-chat' ? 'existing' : 'empty';
  let snapshots = 0, offset = 0, focused = null, value = options.draft ?? '', query = '', sent = false, typed = false;
  let provider = options.alreadySelected ? 'QA Codex' : 'QA Grok';
  let model = options.alreadySelected ? MODEL : 'Provider Default';
  let sidebar = 'Existing filter', createdAt = null, replySample = 0;
  const calls = [], captures = [], reports = [], verifications = [];
  const id = number => offset + number;
  const line = (number, role, text, depth = 2) => ' '.repeat(depth) + `${id(number)} ${role} (settable) ${text}`;
  function state() {
    const tree = ['Window: Mock QA', '0 standard window Mock QA', line(10, 'text', options.workspace ?? 'QA Sandbox'), line(11, 'text field', sidebar)];
    if (phase === 'empty') tree.push(line(20, 'text', 'Panel is empty'), line(21, 'text', 'Agent Chat'));
    if (phase === 'tabs') tree.push(line(21, 'button', 'Add Tab'));
    if (phase === 'add-menu') tree.push(line(22, 'menu', 'Add Tab Menu'), line(23, 'menu item', 'Agent Chat', 4), line(24, 'text', 'Dismiss menu'));
    if (phase === 'existing') tree.push(line(21, 'tab', CHAT), line(25, 'text', CHAT));
    if (phase === 'modal') tree.push(line(22, 'dialog', 'New Agent Chat'), line(23, 'button', 'Start Chat'));
    if (phase === 'chat' || phase === 'picker') {
      tree.push(line(26, 'tab', options.chatLabel ?? CHAT));
      if (Date.now() - createdAt >= (options.readyDelayMs ?? 0)) {
        if (options.previousPrompt) tree.push(line(27, 'text', PROMPT));
        if (!sent) tree.push(line(30, 'text', `${options.observedProvider ?? provider} · ${model}`), line(31, 'text', 'Send a message to start.'));
        if (sent) {
          tree.push(line(32, 'text', PROMPT));
          const answer = options.reply ?? MARKER;
          if (options.userEcho) tree.push(line(33, 'text', 'User'), line(34, 'text', MARKER));
          else if (options.mergedEcho) tree[tree.length - 1] += '\n' + MARKER;
          else if (!options.noReply) {
            tree.push(line(33, 'text', 'Worked for 1s'));
            tree.push(line(34, 'text', options.unstableReply ? answer + ++replySample : answer));
          }
        }
        tree.push(line(40, 'text field', value), line(41, 'text', model));
        if (!options.noSemanticSend) tree.push(line(42, 'button', options.sendLabel ?? 'Send Message'));
        else tree.push(line(42, 'button', ''));
        if (options.error && (sent || options.startupError)) tree.push(line(43, 'text', options.error));
        if (phase === 'picker') {
          tree.push(line(50, 'search field', query));
          tree.push(line(51, options.flatPicker ? 'text' : 'container', 'QA Grok'), line(52, 'text', MODEL, options.flatPicker ? 2 : 4));
          if (!options.missingProvider) tree.push(line(53, options.flatPicker ? 'text' : 'container', 'QA Codex'), line(54, 'text', MODEL, options.flatPicker ? 2 : 4));
        }
      }
    }
    if (focused !== null && options.focusMetadata !== 'absent') {
      const focusNumber = options.focusMetadata === 'sidebar' ? 11 : options.focusMetadata === 'generic' ? 0 : focused;
      tree.push(`The focused UI element is ${focusNumber === 0 ? 0 : id(focusNumber)} ${focusNumber === 0 ? 'standard window' : 'text field'} (settable)`);
    }
    const visibleComposer = options.visualMismatch && typed ? 'Residual mock prefix ' + value : value;
    return {text: tree.join('\n'), screenshot: options.noScreenshot ? null : {url: 'file:///private-mock-screen.png', visibleComposer}};
  }
  const sky = {
    async get_app_state(input) {
      assert.deepEqual(input, {app: BUNDLE, disableDiff: true});
      calls.push({kind: 'snapshot', phase, at: Date.now()});
      snapshots++;
      offset = options.stableIndices ? 100 : snapshots * 100;
      if (options.staleRead && snapshots === 1) throw new Error('snapshot stale');
      if (options.diff && snapshots === 1) return {text: 'The following is a diff', screenshot: {url: 'mock'}};
      if (options.hangReadiness && phase === 'chat') return new Promise(() => {});
      if (options.sidebarDrift && typed && !sent) sidebar = 'Changed filter';
      return state();
    },
    async click(input) {
      assert.equal(input.app, BUNDLE);
      const index = input.element_index === undefined ? 42 : input.element_index - offset;
      if (input.element_index !== undefined) assert.ok(index >= 0 && index < 100, 'The action uses the newest AX indices');
      calls.push({kind: 'click', index, coordinates: input.element_index === undefined, phase, at: Date.now()});
      if (options.staleSelector && phase === 'picker' && index === 54) throw new Error('app changed since snapshot');
      if (phase === 'empty' && index === 21) { phase = options.modal ? 'modal' : 'chat'; createdAt = Date.now(); }
      else if (phase === 'tabs' && index === 21) phase = 'add-menu';
      else if (phase === 'add-menu' && index === 23) { phase = 'chat'; createdAt = Date.now(); }
      else if (phase === 'existing' && index === 21) { phase = 'chat'; createdAt = Date.now(); }
      else if (phase === 'chat' && index === 41) { phase = 'picker'; focused = options.searchWrongFocus ? 40 : 50; }
      else if (phase === 'picker' && index === 54) { provider = 'QA Codex'; model = MODEL; phase = 'chat'; focused = null; }
      else if (phase === 'chat' && index === 40) focused = 40;
      else if (phase === 'chat' && index === 42) {
        assert.equal(value, PROMPT);
        if (!options.noopSend) { sent = true; value = ''; }
        if (options.staleSend) throw new Error('snapshot stale after applying send');
        if (options.hangSend) return new Promise(() => {});
      } else assert.fail(`Unexpected click ${index} in ${phase}`);
    },
    async type_text(input) {
      assert.equal(input.app, BUNDLE);
      calls.push({kind: 'type', text: input.text, phase, at: Date.now()});
      if (phase === 'picker') { assert.equal(focused, 50); query = input.text; }
      else {
        assert.equal(focused, 40);
        assert.equal(value, '');
        typed = true;
        if (options.typingTarget === 'sidebar') sidebar = input.text;
        else if (!options.noopType) value = input.text;
        if (options.staleType) throw new Error('snapshot stale after typing');
      }
    },
  };
  const args = {
    sky, entry: options.entry ?? 'empty-panel', appBundleId: BUNDLE, workspaceLabel: 'QA Sandbox', chatLabel: CHAT,
    providerLabel: 'QA Codex', modelLabel: MODEL, pickerLabel: options.alreadySelected ? MODEL : 'Provider Default', prompt: PROMPT, replyMarker: MARKER, observeSeconds: 2,
    pause: async milliseconds => { calls.push({kind: 'pause'}); context.mock.timers.tick(milliseconds); },
    capture: async evidence => { captures.push(evidence); return {axPath: '/private/mock.ax.txt', screenshotPath: '/private/mock.png'}; },
    verifyComposer: async (state, expected) => {
      assert.deepEqual(expected, {prompt: PROMPT, providerLabel: 'QA Codex', modelLabel: MODEL});
      assert.equal(captures.at(-1).state, state, 'Verification assesses the newest captured screenshot');
      assert.equal(calls.some(call => call.kind === 'click' && call.index === 42), false);
      verifications.push(state);
      return {screenshotVerified: Boolean(state.screenshot), exactPrompt: state.screenshot?.visibleComposer === expected.prompt};
    },
    write: async report => reports.push(structuredClone(report)),
  };
  return {args, calls, captures, reports, verifications, currentIndex: () => id(42), changeSelection: () => { model = 'Changed Model'; }};
}
const mutations = fake => fake.calls.filter(call => ['click', 'type'].includes(call.kind));
const sends = fake => fake.calls.filter(call => call.kind === 'click' && call.index === 42);

test('empty-panel direct replay uses fresh AX around each action and a single semantic send', async context => {
  const fake = fixture(context);
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.selectionVerified, true);
  assert.equal(result.composerVisualVerified, true);
  assert.equal(fake.verifications.length, 1);
  assert.equal(result.replyValidated, true);
  assert.equal(result.turnTerminalStatusVerified, false);
  assert.equal(result.sendTargetSource, 'semantic');
  assert.equal(sends(fake).length, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  for (const [index, call] of fake.calls.entries()) if (['click', 'type'].includes(call.kind)) {
    assert.equal(fake.calls[index - 1].kind, 'snapshot');
    assert.equal(fake.calls[index + 1].kind, 'snapshot');
  }
  assert.equal(fake.reports.length, 1);
  assert.equal(JSON.stringify(result).includes(PROMPT), false);
  assert.equal(fake.captures[0].label, 'initial');
  assert.equal(fake.captures.at(-1).label, 'completed');
  assert.deepEqual(fake.captures.map(item => item.sequence), fake.captures.map((_, index) => index));
});

test('Add Tab menu entry opens directly without modal or keys', async context => {
  const fake = fixture(context, {entry: 'add-tab'});
  assert.equal((await runMacAgentChatDirectFlow(fake.args)).ok, true);
  assert.deepEqual(mutations(fake).slice(0, 2).map(call => call.index), [21, 23]);
});

test('existing chat entry prefers the tab over duplicate title text and reuses verified selection', async context => {
  const fake = fixture(context, {entry: 'existing-chat', alreadySelected: true});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.actions.some(action => action.label === 'open-model-picker'), false);
  assert.equal(sends(fake).length, 1);
});

test('delayed direct composer readiness is bounded without a second creation click', async context => {
  const fake = fixture(context, {readyDelayMs: 2000});
  assert.equal((await runMacAgentChatDirectFlow(fake.args)).ok, true);
  assert.equal(mutations(fake).filter(call => call.index === 21).length, 1);
  assert.equal(fake.calls.find(call => call.kind === 'type').at, 3000);
});

test('an existing transcript containing the exact prompt is never resent across macro invocations', async context => {
  const fake = fixture(context, {entry: 'existing-chat', alreadySelected: true, previousPrompt: true});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /never resend/);
  assert.equal(result.typingAttempted, false);
  assert.equal(result.sendAttempted, false);
  assert.equal(mutations(fake).length, 1);
});

test('explicit bundle and all exact labels are validated before any Sky read', async context => {
  for (const invalid of [{appBundleId: undefined}, {appBundleId: 'dev.leynier.alera'}, {workspaceLabel: 'Personal'}, {chatLabel: undefined}, {providerLabel: undefined}, {modelLabel: undefined}, {replyMarker: undefined}, {entry: 'shortcut'}]) {
    const fake = fixture(context);
    await assert.rejects(runMacAgentChatDirectFlow({...fake.args, ...invalid}));
    assert.deepEqual(fake.calls, []);
    context.mock.timers.reset();
  }
});

test('workspace mismatch, missing screenshots, diffs, and modal entry stop safely', async context => {
  for (const options of [{workspace: 'QA Sandbox Other'}, {noScreenshot: true}, {diff: true}, {modal: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.typingAttempted, false);
    assert.equal(result.sendAttempted, false);
    assert.ok(mutations(fake).length <= (options.modal ? 1 : 0));
    context.mock.timers.reset();
  }
});

test('a wrong composer focus refuses typing before sending', async context => {
  const fake = fixture(context, {focusMetadata: 'sidebar'});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /different editable field/);
  assert.equal(result.typingAttempted, false);
  assert.equal(sends(fake).length, 0);
});

test('optional picker search types only into the snapshot-focused search without clicking it', async context => {
  const fake = fixture(context);
  fake.args.modelSearch = MODEL;
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, true);
  assert.deepEqual(fake.calls.filter(call => call.kind === 'type').map(call => call.text), [MODEL, PROMPT]);
  assert.equal(mutations(fake).some(call => call.index === 50), false);
});

test('wrong or absent picker search focus refuses search instead of clicking the field', async context => {
  for (const options of [{searchWrongFocus: true}, {focusMetadata: 'absent'}]) {
    const fake = fixture(context, options);
    fake.args.modelSearch = MODEL;
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.match(result.error, /snapshot-focused/);
    assert.equal(fake.calls.some(call => call.kind === 'type'), false);
    assert.equal(mutations(fake).some(call => call.index === 50), false);
    context.mock.timers.reset();
  }
});

test('exact provider section disambiguates models and mismatched provider stops before typing', async context => {
  for (const options of [{observedProvider: 'QA Grok'}, {missingProvider: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.typingAttempted, false);
    assert.equal(sends(fake).length, 0);
    assert.equal(mutations(fake).some(call => call.index === 52), false);
    context.mock.timers.reset();
  }
});

test('drafts, misdirected or no-op typing, and sidebar drift never send', async context => {
  for (const options of [{draft: 'Existing mock draft'}, {typingTarget: 'sidebar'}, {noopType: true}, {sidebarDrift: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.sendAttempted, false);
    assert.equal(sends(fake).length, 0);
    assert.ok(fake.calls.filter(call => call.kind === 'type').length <= 1);
    context.mock.timers.reset();
  }
});

test('AX-exact prompt with a visually different composer preserves the draft without sending', async context => {
  const fake = fixture(context, {visualMismatch: true});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /visual confirmation failed/);
  assert.equal(result.composerVisualVerified, false);
  assert.equal(result.sendAttempted, false);
  assert.equal(fake.verifications.length, 1);
  assert.ok(fake.verifications[0].text.includes(`text field (settable) ${PROMPT}`));
  assert.equal(fake.captures.at(-1).state.screenshot.visibleComposer, 'Residual mock prefix ' + PROMPT);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(sends(fake).length, 0);
});

test('missing or invalid verifyComposer rejects before any read or mutation', async context => {
  for (const verifyComposer of [undefined, false, {screenshotVerified: true, exactPrompt: true}]) {
    const fake = fixture(context);
    await assert.rejects(runMacAgentChatDirectFlow({...fake.args, verifyComposer}), /Inject verifyComposer/);
    assert.deepEqual(fake.calls, []);
    context.mock.timers.reset();
  }
});

test('both visual confirmation flags must be explicit true for semantic and screenshot Send', async context => {
  for (const noSemanticSend of [false, true]) for (const proof of [undefined, false, {screenshotVerified: true}, {screenshotVerified: false, exactPrompt: true}, {screenshotVerified: true, exactPrompt: 'true'}]) {
    const fake = fixture(context, {noSemanticSend, stableIndices: true});
    fake.args.selectSendTarget = () => ({screenshotVerified: true, element_index: fake.currentIndex()});
    fake.args.verifyComposer = async () => proof;
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.match(result.error, /visual confirmation failed/);
    assert.equal(result.sendAttempted, false);
    assert.equal(sends(fake).length, 0);
    context.mock.timers.reset();
  }
});

test('visual verifier timeout preserves the draft and late success cannot trigger Send', async context => {
  const fake = fixture(context);
  let release;
  fake.args.verifyComposer = () => new Promise(resolve => { release = resolve; });
  const running = runMacAgentChatDirectFlow(fake.args);
  for (let round = 0; round < 1000 && !release; round++) await Promise.resolve();
  assert.equal(typeof release, 'function');
  context.mock.timers.tick(30_000);
  const result = await running;
  assert.equal(result.ok, false);
  assert.match(result.error, /deadline/);
  assert.equal(result.sendAttempted, false);
  assert.equal(fake.captures.at(-1).state.screenshot.visibleComposer, PROMPT);
  release({screenshotVerified: true, exactPrompt: true});
  for (let round = 0; round < 20; round++) await Promise.resolve();
  assert.equal(result.composerVisualVerified, false);
  assert.equal(sends(fake).length, 0);
});

test('only read-only stale snapshots may retry; stale selectors and typing cannot replay mutations', async context => {
  for (const options of [{staleRead: true}, {staleSelector: true}, {staleType: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, Boolean(options.staleRead));
    assert.equal(result.staleSnapshots, options.staleRead ? 1 : 0);
    assert.equal(mutations(fake).filter(call => call.index === 54).length, 1);
    assert.ok(fake.calls.filter(call => call.kind === 'type').length <= 1);
    if (!options.staleRead) assert.equal(sends(fake).length, 0);
    context.mock.timers.reset();
  }
});

test('stale send after mutation is captured and never duplicates the send', async context => {
  const fake = fixture(context, {staleSend: true});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.sendAttempted, true);
  assert.equal(result.actionUncertain, true);
  assert.equal(sends(fake).length, 1);
  assert.ok(fake.captures.some(capture => capture.label === 'send-exact-prompt-after-error'));
});

test('missing semantic Send requires explicit fresh screenshot verification', async context => {
  const fake = fixture(context, {noSemanticSend: true});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /inject selectSendTarget/);
  assert.equal(result.sendAttempted, false);
});

test('screenshot fallback accepts verified coordinates and fresh indices', async context => {
  for (const target of ['coordinates', 'index']) {
    const fake = fixture(context, {noSemanticSend: true, stableIndices: true});
    fake.args.selectSendTarget = state => {
      assert.ok(state.screenshot);
      assert.ok(state.text.includes(PROMPT));
      return target === 'coordinates' ? {screenshotVerified: true, x: 123, y: 456} : {screenshotVerified: true, element_index: fake.currentIndex()};
    };
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, true);
    assert.equal(result.sendTargetSource, 'screenshot');
    assert.equal(sends(fake).length, 1);
    context.mock.timers.reset();
  }
});

test('unverified, absent, mixed, and stale screenshot selectors refuse Send without retry', async context => {
  for (const [selectSendTarget, stableIndices] of [
    [() => ({x: 1, y: 2}), true],
    [() => ({screenshotVerified: true, element_index: -1}), true],
    [() => ({screenshotVerified: true, element_index: 9999}), true],
    [() => ({screenshotVerified: true, element_index: 140}), true],
    [() => ({screenshotVerified: true, x: 1, y: 2, element_index: 1}), true],
    [() => ({screenshotVerified: true, x: 1, y: 2}), false],
  ]) {
    const fake = fixture(context, {noSemanticSend: true, stableIndices});
    fake.args.selectSendTarget = selectSendTarget;
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.sendAttempted, false);
    assert.equal(sends(fake).length, 0);
    context.mock.timers.reset();
  }
});

test('semantic Send is preferred and a flat QA provider section is selected exactly', async context => {
  const fake = fixture(context, {flatPicker: true, sendLabel: 'Send'});
  fake.args.selectSendTarget = () => assert.fail('The semantic button needs no fallback');
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.sendTargetSource, 'semantic');
  assert.equal(sends(fake).length, 1);
});

test('composer readiness times out within thirty seconds without typing or another entry click', async context => {
  const fake = fixture(context, {readyDelayMs: 31_000});
  const result = await runMacAgentChatDirectFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.elapsedMs, 30_000);
  assert.equal(result.typingAttempted, false);
  assert.equal(mutations(fake).length, 1);
});

test('a hung readiness snapshot shares its phase deadline and bounds the stopped capture', async context => {
  const fake = fixture(context, {hangReadiness: true});
  const running = runMacAgentChatDirectFlow(fake.args);
  for (let round = 0; round < 1000 && !fake.calls.some(call => call.kind === 'snapshot' && call.phase === 'chat'); round++) await Promise.resolve();
  assert.ok(fake.calls.some(call => call.kind === 'snapshot' && call.phase === 'chat'));
  context.mock.timers.tick(30_000);
  for (let round = 0; round < 1000 && fake.calls.filter(call => call.kind === 'snapshot' && call.phase === 'chat').length < 2; round++) await Promise.resolve();
  context.mock.timers.tick(5000);
  const result = await running;
  assert.equal(result.ok, false);
  assert.equal(result.elapsedMs, 35_000);
  assert.equal(result.finalCaptureFailed, true);
  assert.equal(result.typingAttempted, false);
});

test('no-op send, false user echoes, and unstable replies time out with one send', async context => {
  for (const options of [{noopSend: true}, {userEcho: true}, {mergedEcho: true}, {unstableReply: true}, {noReply: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.replyValidated, false);
    assert.match(result.error, /timeout|deadline/);
    assert.equal(sends(fake).length, 1);
    assert.equal(result.elapsedMs, 2000);
    context.mock.timers.reset();
  }
});

test('visible provider startup and reply errors stop immediately with private evidence', async context => {
  for (const startupError of [true, false]) {
    const fake = fixture(context, {error: 'Authentication failed', startupError});
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.providerErrorVisible, true);
    assert.equal(result.elapsedMs, 0);
    assert.equal(sends(fake).length, startupError ? 0 : 1);
    assert.equal(fake.captures.at(-1).label, 'stopped');
    context.mock.timers.reset();
  }
});

test('a hung send expires and cannot retry or manufacture reply success', async context => {
  const fake = fixture(context, {hangSend: true});
  const running = runMacAgentChatDirectFlow(fake.args);
  for (let round = 0; round < 1000 && !sends(fake).length; round++) await Promise.resolve();
  assert.equal(sends(fake).length, 1);
  context.mock.timers.tick(30_000);
  const result = await running;
  assert.equal(result.ok, false);
  assert.equal(result.actionUncertain, true);
  assert.equal(result.replyValidated, false);
  assert.equal(sends(fake).length, 1);
});

test('runtime confirmation is optional, separate, bounded, and never leaks callback errors', async context => {
  for (const confirmation of [{confirmed: true, status: 'succeeded'}, {confirmed: true, status: 'failed'}, {confirmed: false, status: 'succeeded'}, new Error('private mock detail')]) {
    const fake = fixture(context);
    fake.args.confirmRuntime = async input => {
      assert.equal(input.replyMarker, MARKER);
      if (confirmation instanceof Error) throw confirmation;
      return confirmation;
    };
    const result = await runMacAgentChatDirectFlow(fake.args);
    assert.equal(result.replyValidated, true);
    assert.equal(result.turnTerminalStatusVerified, confirmation.confirmed === true);
    assert.equal(result.ok, confirmation.status !== 'failed');
    assert.equal(JSON.stringify(result).includes('private mock detail'), false);
    assert.equal(sends(fake).length, 1);
    context.mock.timers.reset();
  }
});

function replyState(lines, composer = '') {
  return {text: ['0 standard window Mock', '  1 text field ', ...lines, `  9 text field ${composer}`].join('\n')};
}
test('pure reply evidence needs an assistant boundary after the exact prompt', () => {
  const cases = [
    {lines: [`  2 text ${PROMPT}`, '  3 text Worked for 1s', `  4 text ${MARKER}`], valid: true},
    {lines: [`  2 text ${PROMPT}\nWorked for 1s\n${MARKER}`], valid: true},
    {lines: [`  2 text ${PROMPT}`, `  3 text Assistant: ${MARKER}`], valid: true},
    {lines: [`  2 text ${PROMPT}`, `  3 text ${MARKER}`]},
    {lines: [`  2 text ${PROMPT}\n${MARKER}`]},
    {lines: [`  2 text ${MARKER}`, `  3 text ${PROMPT}`]},
    {lines: [`  2 text ${PROMPT}`, '  3 text Worked for 1s', `  4 text ${PROMPT}`]},
    {lines: [`  2 text ${PROMPT}`, '  3 text Worked for 1s', '  4 text User', `  5 text ${MARKER}`]},
    {lines: [`  2 text ${PROMPT}`, '  3 text Worked for 1s', `  4 text ${MARKER}-WRONG`]},
    {lines: [`  2 text ${PROMPT}`, '  3 text Worked for 1s', `  4 text ${MARKER}`], composer: MARKER},
  ];
  for (const {lines, composer, valid} of cases) {
    const state = Object.freeze(replyState(lines, composer));
    const before = structuredClone(state);
    assert.equal(Boolean(inspectMacAgentChatDirectReply({state, prompt: PROMPT, replyMarker: MARKER})), Boolean(valid));
    assert.deepEqual(state, before);
  }
});
