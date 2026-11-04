import assert from 'node:assert/strict';
import test from 'node:test';

import {inspectMacAgentChatReply, runMacAgentChatFlow} from './mac_agent_chat_flow.mjs';

const BUNDLE = 'dev.leynier.alera.agentqa.20261013';
const PROMPT = 'Reply with GUI-CODEX-QA-20261013. Do not read files or execute tools.';
const MARKER = 'GUI-CODEX-QA-20261013';
const BETA_PROMPT = 'Reply with GUI-CODEX-QA-20261013-BETA. Do not read files or execute tools.';
const BETA_MARKER = 'GUI-CODEX-QA-20261013-BETA';

function fixture(context, options = {}) {
  context.mock.timers.enable({apis: ['Date', 'setTimeout'], now: 1000});
  let phase = options.initialPhase ?? 'dialog';
  let selected = 'QA Grok';
  let value = options.composerText ?? '';
  let sidebarValue = options.sidebarText ?? '';
  let focused = false;
  let typed = false;
  let sent = false;
  let createdAt = null;
  let staleRejected = false;
  let chatSnapshots = 0;
  let postTypingSnapshots = 0;
  let replyObservations = 0;
  const calls = [], captures = [], reports = [];
  const workspace = options.dialogWorkspace ?? 'QA Beta';
  const sidebarIndex = options.realAxShape ? 6 : 11;
  const composerIndex = options.realAxShape ? 53 : 60;
  const annotation = options.realAxShape ? '(settable) ' : '';

  function state() {
    const text = ['Window: Alera QA', '0 standard window Alera QA', '  10 text QA Beta', `\t\t\t${sidebarIndex} text field ${annotation}${sidebarValue}`];
    if (phase === 'dialog' || phase === 'menu' || phase === 'unrelated') {
      text.push(`  20 container ${phase === 'unrelated' ? 'Preferences' : 'New Agent Chat'}`);
      text.push(`    The chat runs on the Alera runtime of ${workspace} and keeps going when this window closes.`);
      text.push(`    21 button ${selected}`, '    22 button Ask For Approval', '    23 button Cancel', '    24 button Start Chat');
      if (phase === 'menu') text.push('  30 container Provider Menu', '    31 text QA Codex', '  32 text Dismiss menu');
    }
    if (phase === 'chat') {
      const elapsed = Date.now() - createdAt;
      const ready = elapsed >= (options.readyDelayMs ?? 0);
      const providerLine = `\t\t\t${options.realAxShape ? 54 : 40} text ${annotation}${options.chatProvider ?? 'QA Codex'}`;
      if (!options.realAxShape && elapsed >= (options.providerDelayMs ?? 0)) text.push(providerLine);
      if (options.providerError) text.push(`  41 text ${options.providerError}`);
      if (ready && !sent && !options.hideHint) text.push(`\t\t\t${options.realAxShape ? 52 : 42} text ${annotation}Send a message to start.`);
      if (sent) {
        const reply = options.changingReply ? MARKER + ' sample ' + ++replyObservations : options.reply ?? MARKER;
        if (options.mergedReply) text.push(`  50 text ${PROMPT}\n${reply}`);
        else text.push(`  50 text ${PROMPT}`, `  51 text ${reply}`);
      }
      if (!options.hideComposerDuringStartup || ready) text.push(`\t\t\t${composerIndex} text field ${annotation}${value}`);
      if (options.realAxShape && elapsed >= (options.providerDelayMs ?? 0)) text.push(providerLine);
      const metadata = options.focusMetadata ?? (options.realAxShape ? 'absent' : 'composer');
      if (focused && metadata !== 'absent') text.push(metadata === 'generic' ? 'The focused UI element is 0 standard window' : `The focused UI element is ${metadata === 'sidebar' ? sidebarIndex : composerIndex} text field`);
    }
    return {text: text.join('\n'), screenshot: options.noScreenshot || (options.noScreenshotAfterClick && focused) ? null : {url: 'file:///fixture-screen.png'}};
  }

  const sky = {
    async get_app_state(input) {
      assert.equal(input.app, BUNDLE);
      assert.equal(input.disableDiff, true);
      calls.push({kind: 'snapshot', at: Date.now()});
      if (phase === 'chat' && ++chatSnapshots === 2 && options.hangReadinessSnapshot) {
        calls.push({kind: 'hung-readiness', at: Date.now()});
        return new Promise(() => {});
      }
      if (phase === 'chat' && typed && ++postTypingSnapshots === 2 && options.sidebarDriftBeforeReturn) sidebarValue = 'Changed sidebar query';
      return state();
    },
    async click({app, element_index: index}) {
      assert.equal(app, BUNDLE);
      calls.push({kind: 'click', index, at: Date.now()});
      if (options.staleClickOnce && !staleRejected) {
        staleRejected = true;
        throw new Error('snapshot stale');
      }
      if (index === 10) assert.equal(phase, 'workspace');
      else if (index === 21) { assert.equal(phase, 'dialog'); phase = 'menu'; }
      else if (index === 31) { assert.equal(phase, 'menu'); selected = 'QA Codex'; phase = 'dialog'; }
      else if (index === 24) { assert.equal(selected, 'QA Codex'); phase = 'chat'; createdAt = Date.now(); }
      else if (index === composerIndex) { assert.equal(phase, 'chat'); focused = true; }
      else assert.fail('Unexpected AX index');
    },
    async press_key({app, key}) {
      assert.equal(app, BUNDLE);
      calls.push({kind: 'key', key, at: Date.now()});
      if (key === 'super+shift+t') {
        assert.equal(phase, 'workspace');
        if (!options.noopShortcut) phase = 'dialog';
      } else {
        assert.equal(key, 'Return');
        assert.equal(value, PROMPT);
        assert.equal(focused, true);
        if (options.staleBeforeReturn) throw new Error('snapshot stale');
        if (!options.noopReturn) { sent = true; value = ''; }
        if (options.staleReturn) throw new Error('snapshot stale');
      }
    },
    async type_text({app, text}) {
      assert.equal(app, BUNDLE);
      assert.equal(focused, true);
      assert.equal(value, '');
      calls.push({kind: 'type', text, at: Date.now()});
      if (options.staleBeforeTyping) throw new Error('snapshot stale');
      typed = true;
      if (options.typingTarget === 'sidebar' || options.typingTarget === 'both') sidebarValue = text;
      if (!options.typingTarget || options.typingTarget === 'both') value = text;
      if (options.staleAfterTyping) throw new Error('snapshot stale');
    },
  };
  const args = {
    sky, entry: 'dialog', appBundleId: BUNDLE, workspaceLabel: 'QA Beta', providerLabel: 'QA Codex', prompt: PROMPT, observeSeconds: 2,
    pause: async milliseconds => context.mock.timers.tick(milliseconds),
    capture: async evidence => {
      captures.push(evidence);
      return {axPath: `/fixture/${evidence.sequence}-${evidence.label}.ax.txt`, screenshotPath: `/fixture/${evidence.sequence}-${evidence.label}.png`};
    },
    write: async report => reports.push(structuredClone(report)),
  };
  return {args, calls, captures, reports};
}

function mutations(calls) {
  return calls.filter(call => call.kind !== 'snapshot');
}

test('dialog entry preserves fresh capture guards and sends exactly once', async context => {
  const fake = fixture(context);
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.entry, 'dialog');
  assert.equal(result.emptyChatReadyObserved, true);
  assert.equal(result.replyValidated, true);
  assert.equal(result.turnTerminalStatusVerified, false);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.deepEqual(fake.calls.filter(call => call.kind === 'key').map(call => call.key), ['Return']);
  assert.equal(fake.calls.some(call => call.kind === 'click' && call.index === 10), false);
  assert.equal(fake.captures[0].label, 'initial');
  assert.equal(fake.captures.at(-1).label, 'completed');
  assert.deepEqual(fake.captures.map(capture => capture.sequence), fake.captures.map((_, index) => index));
  assert.equal(fake.reports.length, 1);
  assert.equal(result.observations.every(observation => observation.axPath && observation.screenshotPath), true);
});

test('shortcut remains the default and opens its own new dialog', async context => {
  const fake = fixture(context, {initialPhase: 'workspace'});
  delete fake.args.entry;
  delete fake.args.appBundleId;
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.entry, 'shortcut');
  assert.deepEqual(fake.calls.filter(call => call.kind === 'key').map(call => call.key), ['super+shift+t', 'Return']);
});

test('default shortcut mode refuses an already-open dialog', async context => {
  const fake = fixture(context);
  delete fake.args.entry;
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /pre-existing/);
  assert.deepEqual(mutations(fake.calls), []);
});

test('dialog entry requires an explicit QA bundle before reading or acting', async context => {
  const fake = fixture(context);
  delete fake.args.appBundleId;
  await assert.rejects(runMacAgentChatFlow(fake.args), /explicit Agent QA app bundle/);
  assert.deepEqual(fake.calls, []);
  fake.args.appBundleId = 'dev.leynier.alera';
  await assert.rejects(runMacAgentChatFlow(fake.args), /Only an explicit Agent QA/);
  assert.deepEqual(fake.calls, []);
});

test('dialog entry rejects an exact-workspace mismatch including a shared prefix', async context => {
  const fake = fixture(context, {dialogWorkspace: 'QA Beta Other'});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /different workspace/);
  assert.deepEqual(mutations(fake.calls), []);
});

test('dialog entry rejects unrelated dialogs and missing initial screenshots', async context => {
  for (const options of [{initialPhase: 'unrelated'}, {noScreenshot: true}]) {
    const fake = fixture(context, options);
    const result = await runMacAgentChatFlow(fake.args);
    assert.equal(result.ok, false);
    assert.deepEqual(mutations(fake.calls), []);
    context.mock.timers.reset();
  }
});

test('a no-op injected shortcut stops without typing or sending', async context => {
  const fake = fixture(context, {initialPhase: 'workspace', noopShortcut: true});
  fake.args.entry = 'shortcut';
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.keyboardSendAttempted, false);
  assert.equal(fake.calls.some(call => call.kind === 'type'), false);
  assert.deepEqual(fake.calls.filter(call => call.kind === 'key').map(call => call.key), ['super+shift+t']);
});

test('native startup can hide the composer and hint until late readiness', async context => {
  const fake = fixture(context, {readyDelayMs: 5000, providerDelayMs: 3000, hideComposerDuringStartup: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(fake.calls.find(call => call.kind === 'type').at, 6000);
  assert.equal(result.observations.filter(observation => observation.label === 'await-empty-ready').length, 5);
  assert.equal(fake.calls.filter(call => call.kind === 'key' && call.key === 'Return').length, 1);
});

test('missing ready hint fails within thirty seconds without touching the composer', async context => {
  const fake = fixture(context, {hideHint: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.emptyChatReadyObserved, false);
  assert.equal(result.elapsedMs, 30000);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('a ready hint from another provider never permits typing', async context => {
  const fake = fixture(context, {chatProvider: 'QA Grok'});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.elapsedMs, 30000);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('a hanging readiness snapshot shares the thirty-second phase deadline', async context => {
  const fake = fixture(context, {hideHint: true, hangReadinessSnapshot: true});
  const running = runMacAgentChatFlow(fake.args);
  for (let step = 0; step < 200 && !fake.calls.some(call => call.kind === 'hung-readiness'); step++) await Promise.resolve();
  assert.equal(fake.calls.some(call => call.kind === 'hung-readiness'), true);
  context.mock.timers.tick(29000);
  const result = await running;
  assert.equal(result.ok, false);
  assert.equal(result.elapsedMs, 30000);
  assert.match(result.error, /deadline exceeded/);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('visible startup provider errors fail immediately and preserve evidence', async context => {
  const fake = fixture(context, {providerError: 'Authentication failed', readyDelayMs: 5000, hideComposerDuringStartup: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.providerErrorVisible, true);
  assert.equal(result.elapsedMs, 0);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
  assert.equal(fake.captures.at(-1).label, 'stopped');
});

test('a nonempty startup composer is preserved without waiting or typing', async context => {
  const fake = fixture(context, {composerText: 'Existing draft', readyDelayMs: 5000});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /preserve its text/);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('stale safe selection gets one fresh retry', async context => {
  const fake = fixture(context, {staleClickOnce: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.staleRetries, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
});

test('a stale rejection after typing cannot duplicate the prompt or send', async context => {
  const fake = fixture(context, {staleAfterTyping: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(fake.calls.some(call => call.kind === 'key'), false);
});

test('a stale Return result cannot cause a second send attempt', async context => {
  const fake = fixture(context, {staleReturn: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.keyboardSendAttempted, true);
  assert.equal(fake.calls.filter(call => call.kind === 'key' && call.key === 'Return').length, 1);
});

test('a no-op Return cannot pass on a marker still inside the composer', async context => {
  const fake = fixture(context, {noopReturn: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.replyValidated, false);
  assert.equal(fake.calls.filter(call => call.kind === 'key' && call.key === 'Return').length, 1);
  assert.equal(result.elapsedMs, 2000);
});

test('real background AX shape succeeds without focus metadata only after exact composer typing', async context => {
  const fake = fixture(context, {realAxShape: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.composerFocusMetadata, 'absent');
  assert.equal(result.typingAttempted, true);
  const before = fake.captures.find(capture => capture.label === 'type-exact-prompt-before').state;
  assert.match(before.text, /6 text field \(settable\)/);
  assert.match(before.text, /53 text field \(settable\)/);
  assert.equal(before.text.includes('The focused UI element'), false);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.deepEqual(fake.calls.filter(call => call.kind === 'key').map(call => call.key), ['Return']);
});

test('generic root focus permits exact typing after fresh composer click screenshots', async context => {
  const fake = fixture(context, {focusMetadata: 'generic', sidebarText: 'Existing filter'});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.composerFocusMetadata, 'generic');
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'key').length, 1);
});

test('explicit sidebar editable focus rejects before typing', async context => {
  const fake = fixture(context, {realAxShape: true, focusMetadata: 'sidebar'});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /different editable field/);
  assert.equal(result.typingAttempted, false);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('missing focus metadata cannot bypass the fresh clicked-composer screenshot requirement', async context => {
  const fake = fixture(context, {realAxShape: true, noScreenshotAfterClick: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /screenshot after/);
  assert.equal(fake.calls.some(call => call.kind === 'type' || call.kind === 'key'), false);
});

test('missing or generic focus does not permit misdirected, mirrored, or no-op typing to send', async context => {
  for (const focusMetadata of ['absent', 'generic']) {
    for (const typingTarget of ['sidebar', 'both', 'noop']) {
      const fake = fixture(context, {realAxShape: true, focusMetadata, typingTarget});
      const result = await runMacAgentChatFlow(fake.args);
      assert.equal(result.ok, false);
      assert.equal(result.typingAttempted, true);
      assert.equal(result.keyboardSendAttempted, false);
      assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
      assert.equal(fake.calls.some(call => call.kind === 'key'), false);
      context.mock.timers.reset();
    }
  }
});

test('sidebar drift after a correct typing postcondition still blocks Return', async context => {
  const fake = fixture(context, {realAxShape: true, sidebarDriftBeforeReturn: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.match(result.error, /Sidebar text changed before Return/);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(fake.calls.some(call => call.kind === 'key'), false);
});

test('typing and Return never retry even when rejected as stale before mutation', async context => {
  for (const failure of ['staleBeforeTyping', 'staleBeforeReturn']) {
    const fake = fixture(context, {[failure]: true});
    const result = await runMacAgentChatFlow(fake.args);
    assert.equal(result.ok, false);
    assert.equal(result.staleRetries, 0);
    assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
    assert.equal(fake.calls.filter(call => call.kind === 'key').length, failure === 'staleBeforeReturn' ? 1 : 0);
    context.mock.timers.reset();
  }
});

function savedReplyShape({merged = true, reply = BETA_MARKER, sidebar = '', composer = '', duplicate = false, working = null} = {}) {
  const text = ['Window: "Alera Dev", App: Alera Agent QA.', '0 standard window Alera Dev', '\t1 container Alera Agent QA', `\t\t\t6 text field (settable) ${sidebar}`, `\t\t\t49 text (settable) ${BETA_PROMPT}`];
  if (reply !== null) text.push(merged ? reply : `\t\t\t48 text (settable) ${reply}`);
  if (duplicate) text.push(`\t\t\t47 text (settable) ${BETA_PROMPT}`);
  if (working) text.push(working);
  text.push(`\t\t\t50 text field (settable) ${composer}`, '\t\t\t51 text (settable) QA Codex', 'The focused UI element is 50 text field (settable)');
  return {text: text.join('\n')};
}

test('pure detector accepts the real merged readonly row without mutating its snapshot', () => {
  const state = Object.freeze(savedReplyShape());
  const before = structuredClone(state);
  const answer = inspectMacAgentChatReply({state, prompt: BETA_PROMPT});
  assert.deepEqual(answer, {marker: BETA_MARKER, text: BETA_MARKER, indices: [49]});
  assert.deepEqual(state, before);
});

test('pure detector retains separated reply rows and exact marker boundaries', () => {
  assert.deepEqual(inspectMacAgentChatReply({state: savedReplyShape({merged: false}), prompt: BETA_PROMPT}), {marker: BETA_MARKER, text: BETA_MARKER, indices: [48]});
  for (const reply of ['A different reply', BETA_MARKER + '-WRONG', 'PREFIX-' + BETA_MARKER]) {
    assert.equal(inspectMacAgentChatReply({state: savedReplyShape({reply}), prompt: BETA_PROMPT}), null);
  }
});

test('marker only in the prompt, composer, or sidebar cannot count as a reply', () => {
  for (const options of [{reply: null}, {reply: null, composer: BETA_MARKER}, {reply: null, sidebar: BETA_MARKER}]) {
    assert.equal(inspectMacAgentChatReply({state: savedReplyShape(options), prompt: BETA_PROMPT}), null);
  }
});

test('duplicate or repeated prompts cannot establish a distinct merged reply suffix', () => {
  for (const options of [{duplicate: true}, {reply: BETA_PROMPT}, {reply: BETA_PROMPT + '\n' + BETA_MARKER}, {merged: false, reply: BETA_PROMPT + '\n' + BETA_MARKER}]) {
    assert.equal(inspectMacAgentChatReply({state: savedReplyShape(options), prompt: BETA_PROMPT}), null);
  }
});

test('working indicators in merged or separate rows block observational completion', () => {
  for (const working of ['Working', 'Writing', 'Working for 3 seconds', '\t\t\t48 text (settable) Working', '\t\t\t48 container (settable) Working']) {
    assert.equal(inspectMacAgentChatReply({state: savedReplyShape({working}), prompt: BETA_PROMPT}), null);
  }
});

test('pure inspection requires a bounded single-line prompt and full AX state', () => {
  assert.throws(() => inspectMacAgentChatReply({state: savedReplyShape(), prompt: BETA_PROMPT + '\nother'}), /single-line/);
  assert.throws(() => inspectMacAgentChatReply({state: {text: 'The following is a diff'}, prompt: BETA_PROMPT}), /full AX snapshot/);
});

test('merged replies still require two stable samples without another type or send', async context => {
  const fake = fixture(context, {mergedReply: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, true);
  assert.equal(result.replyValidated, true);
  assert.equal(fake.captures.filter(capture => capture.label === 'observe-reply').length, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'key' && call.key === 'Return').length, 1);
});

test('changing merged replies cannot pass a one-sample or unstable observation', async context => {
  const fake = fixture(context, {mergedReply: true, changingReply: true});
  const result = await runMacAgentChatFlow(fake.args);
  assert.equal(result.ok, false);
  assert.equal(result.replyValidated, false);
  assert.equal(fake.calls.filter(call => call.kind === 'type').length, 1);
  assert.equal(fake.calls.filter(call => call.kind === 'key' && call.key === 'Return').length, 1);
});
