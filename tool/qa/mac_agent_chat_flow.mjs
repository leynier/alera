// Caller imports Sky in node_repl and injects it; this module owns no plugin or filesystem globals.
const DEFAULT_QA_BUNDLE = 'dev.leynier.alera.agentqa.20261013';
const MAX_FLOW_MS = 5 * 60 * 1000;
const MAX_CALL_MS = 30 * 1000;
const AX_ROLES = 'standard window|text field|full screen button|minimize button|close button|menu item|scroll area|container|button|text|checkbox';

class FlowError extends Error {}

function require(condition, message) {
  if (!condition) throw new FlowError(message);
}

function rows(state) {
  require(typeof state?.text === 'string', 'Sky did not return AX text');
  require(!state.text.startsWith('The following is a diff'), 'A full AX snapshot is required; a diff cannot provide fresh selectors');
  const result = [];
  const pattern = new RegExp(`^([\\t ]*)(\\d+) (${AX_ROLES})\\b(.*)$`);
  for (const line of state.text.split('\n')) {
    const match = line.match(pattern);
    if (match) {
      const label = match[4].replace(/^\s*\([^)]*\)\s*/, '').trim();
      result.push({index: Number(match[2]), depth: match[1].length, role: match[3], label, fullLabel: label});
    } else if (result.length && line.trim() && !/^(?:Window:|The focused UI element|\d+ menu bar)/.test(line)) {
      result.at(-1).fullLabel += '\n' + line;
    }
  }
  return result;
}

function exact(tree, role, label) {
  const matches = tree.filter(row => row.role === role && row.label === label);
  require(matches.length === 1, `Expected one fresh AX ${role} with the exact requested label`);
  return matches[0];
}

function children(tree, parent) {
  const start = tree.indexOf(parent) + 1;
  let end = start;
  while (end < tree.length && tree[end].depth > parent.depth) end++;
  return tree.slice(start, end);
}

function dialog(tree) {
  return exact(tree, 'container', 'New Agent Chat');
}

function dialogTargetsWorkspace(tree, workspaceLabel) {
  const target = dialog(tree);
  const description = `The chat runs on the Alera runtime of ${workspaceLabel} and keeps going when this window closes.`;
  require([target, ...children(tree, target)].some(row => row.fullLabel.replace(/\s+/g, ' ').includes(description)), 'New Agent Chat targets a different workspace');
}

function agentSelector(tree) {
  const controls = children(tree, dialog(tree));
  // The documented form orders Agent, optional Model, Approvals, then its action buttons.
  const selector = controls.find(row => row.role === 'button' && row.label && !['Cancel', 'Start Chat', 'Ask For Approval'].includes(row.label));
  require(selector, 'The Agent dropdown has no named AX button');
  return selector;
}

function providerMenuEntry(tree, label) {
  const dismiss = exact(tree, 'text', 'Dismiss menu');
  const menu = tree.slice(0, tree.indexOf(dismiss)).findLast(row => row.role === 'container' && row.depth === dismiss.depth);
  require(menu, 'The provider dropdown menu AX container is absent');
  const options = children(tree, menu);
  const matches = options.filter(row => ['text', 'menu item'].includes(row.role) && row.label === label);
  require(matches.length === 1, 'Expected the explicit provider label once in the actual AX dropdown');
  require(!/unavailable|invalid provider|disabled/i.test(matches[0].fullLabel), 'The selected provider is unavailable in the QA dropdown');
  return matches[0];
}

function composer(tree) {
  const fields = tree.filter(row => row.role === 'text field');
  require(fields.length === 2, 'Expected only sidebar search and the new chat composer');
  return fields[1];
}

function providerError(tree) {
  const fields = tree.filter(row => row.role === 'text field');
  const end = fields.length === 2 ? tree.indexOf(fields[1]) : tree.length;
  return tree.slice(0, end).some(row => row.role !== 'text field' && /provider protocol error|provider unavailable|not logged in|authentication failed|auth required|failed after|the turn failed|the agent session stopped|failed to (?:start|spawn)/i.test(row.fullLabel));
}

function assistantEvidence(tree, prompt, marker) {
  const input = composer(tree);
  const end = tree.indexOf(input);
  const users = tree.slice(0, end).filter(row => row.role === 'text' && row.label === prompt);
  if (input.label !== '' || users.length !== 1) return null;
  const user = users[0];
  const suffix = user.fullLabel.startsWith(prompt + '\n') ? user.fullLabel.slice(prompt.length + 1).trim() : '';
  const transcript = tree.slice(tree.indexOf(user) + 1, end);
  if (suffix.includes(prompt) || transcript.some(row => row.fullLabel.includes(prompt))) return null;
  const lines = [suffix, ...transcript.map(row => row.fullLabel)].flatMap(text => text.split('\n'));
  if (lines.some(line => /^(?:Working(?: for .*)?|Writing)$/.test(line.trim()))) return null;
  const escapedMarker = marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const expectedMarker = new RegExp(`(?:^|[^A-Za-z0-9_-])${escapedMarker}(?=$|[^A-Za-z0-9_-])`);
  const answers = transcript.filter(row => row.role === 'text' && expectedMarker.test(row.fullLabel)).map(row => ({text: row.fullLabel, index: row.index}));
  if (suffix && expectedMarker.test(suffix)) answers.unshift({text: suffix, index: user.index});
  if (!answers.length) return null;
  return {text: answers.map(row => row.text).join('\n'), indices: answers.map(row => row.index)};
}

function markerFrom(prompt) {
  const markers = [...new Set(prompt.match(/\b(?:[A-Z][A-Z0-9]*(?:[-_][A-Z0-9]+)*[-_]QA(?:[-_][A-Z0-9]+)+|QA(?:[-_][A-Z0-9]+){2,})\b/g) ?? [])];
  require(markers.length === 1, 'Prompt must contain one explicit uppercase QA reply marker');
  return markers[0];
}

/** Inspect one full QA AX snapshot without calling Sky or mutating any state. */
export function inspectMacAgentChatReply({state, prompt} = {}) {
  require(typeof prompt === 'string' && prompt.length > 0 && prompt.length <= 4096 && !/[\r\n]/.test(prompt), 'Provide a bounded single-line exact QA prompt');
  const marker = markerFrom(prompt);
  const tree = rows(state);
  if (providerError(tree)) return null;
  const evidence = assistantEvidence(tree, prompt, marker);
  return evidence ? {marker, ...evidence} : null;
}

/**
 * capture({label,sequence,state,elapsedMs}) stores the AX/screenshot evidence and returns path metadata.
 * pause(milliseconds) and write(value) are caller-owned helpers. No user resources are closed.
 */
export async function runMacAgentChatFlow({sky, capture, write, pause, appBundleId, entry = 'shortcut', workspaceLabel = 'QA Alpha', providerLabel = 'QA Codex', prompt, observeSeconds = 60} = {}) {
  require(['shortcut', 'dialog'].includes(entry), 'Entry must be shortcut or dialog');
  require(entry !== 'dialog' || typeof appBundleId === 'string', 'Dialog entry requires an explicit Agent QA app bundle');
  if (appBundleId === undefined) appBundleId = DEFAULT_QA_BUNDLE;
  require(/^dev\.leynier\.alera\.agentqa(?:\.[A-Za-z0-9_-]+)*$/.test(appBundleId), 'Only an explicit Agent QA app bundle is permitted');
  require(/^QA\b/.test(workspaceLabel) && typeof providerLabel === 'string' && providerLabel.length > 0, 'Explicit QA workspace and provider labels are required');
  require(typeof prompt === 'string' && prompt.length > 0 && prompt.length <= 4096 && !/[\r\n]/.test(prompt), 'Provide a bounded single-line exact QA prompt');
  require(Number.isFinite(observeSeconds) && observeSeconds > 0 && observeSeconds <= 180, 'Observation must be between zero and 180 seconds');
  require(['get_app_state', 'click', 'press_key', 'type_text'].every(method => typeof sky?.[method] === 'function'), 'Inject the public Sky API from the caller');
  require([capture, write, pause].every(value => typeof value === 'function'), 'Inject capture, write, and pause helpers from the caller');
  const marker = markerFrom(prompt);
  const started = Date.now();
  const deadline = started + MAX_FLOW_MS;
  const report = {bundleId: appBundleId, entry, workspaceLabel, providerLabel, replyMarker: marker, observations: [], actions: [], staleRetries: 0, emptyChatReadyObserved: false, composerFocusMetadata: null, typingAttempted: false, keyboardSendAttempted: false, providerErrorVisible: false, replyValidated: false, turnTerminalStatusVerified: false, manualScreenshotReviewRequired: true};
  let sequence = 0;
  let sidebarBeforeTyping;

  async function bounded(operation, finishing = false, phaseDeadline = deadline) {
    const remaining = finishing ? 5000 : Math.min(deadline, phaseDeadline) - Date.now();
    require(remaining > 0, phaseDeadline === deadline ? 'Five minute Mac QA deadline exceeded' : 'Mac QA phase deadline exceeded');
    let timer;
    try {
      return await Promise.race([Promise.resolve().then(operation), new Promise((_, reject) => {
        timer = setTimeout(() => reject(new FlowError('Mac QA call deadline exceeded')), Math.min(MAX_CALL_MS, remaining));
      })]);
    } finally {
      clearTimeout(timer);
    }
  }

  async function snapshot(label, phaseDeadline = deadline) {
    const state = await bounded(() => sky.get_app_state({app: appBundleId, disableDiff: true}), false, phaseDeadline);
    const metadata = await bounded(() => capture({label, sequence: sequence++, state, elapsedMs: Date.now() - started}), false, phaseDeadline);
    report.observations.push({label, elapsedMs: Date.now() - started, screenshotAvailable: Boolean(state.screenshot), axPath: metadata?.axPath ?? null, screenshotPath: metadata?.screenshotPath ?? null});
    rows(state);
    return state;
  }

  async function action(label, select, operate, retryStale = true) {
    for (let attempt = 0; attempt < (retryStale ? 2 : 1); attempt++) {
      const before = await snapshot(`${label}-before${attempt ? '-retry' : ''}`);
      const selection = select(rows(before), before);
      try {
        await bounded(() => operate(selection));
      } catch (error) {
        const stale = /app.*changed.*snapshot|snapshot.*stale/i.test(String(error?.message ?? error));
        if (!retryStale || !stale || attempt === 1) throw error;
        report.staleRetries++;
        continue;
      }
      report.actions.push(label);
      return snapshot(`${label}-after`);
    }
    throw new FlowError('Fresh AX action retry exhausted');
  }

  function checkChat(tree) {
    if (providerError(tree)) {
      report.providerErrorVisible = true;
      throw new FlowError('Provider error is visible in the QA chat; inspect captured evidence');
    }
  }

  async function awaitChatCreated(state) {
    const createDeadline = Math.min(deadline, Date.now() + MAX_CALL_MS);
    while (rows(state).some(row => row.label === 'New Agent Chat') && Date.now() < createDeadline) {
      await bounded(() => pause(Math.min(1000, Math.max(1, createDeadline - Date.now()))), false, createDeadline);
      state = await snapshot('await-chat-created', createDeadline);
    }
    require(!rows(state).some(row => row.label === 'New Agent Chat'), 'Start Chat did not dismiss the creation dialog within 30 seconds');
    return state;
  }

  function hasEmptyReadyHint(tree) {
    return tree.some(row => row.role === 'text' && row.label === providerLabel) && tree.some(row => row.role === 'text' && row.label === 'Send a message to start.');
  }

  async function awaitEmptyReady(state) {
    const readyDeadline = Math.min(deadline, Date.now() + MAX_CALL_MS);
    while (Date.now() < readyDeadline) {
      const tree = rows(state);
      checkChat(tree);
      const fields = tree.filter(row => row.role === 'text field');
      require(fields.length === 1 || fields.length === 2, 'Unexpected text fields are visible during QA chat startup');
      if (fields.length === 2) require(composer(tree).label === '', 'Composer is not empty during startup; preserve its text and stop');
      if (hasEmptyReadyHint(tree) && fields.length === 2) {
        report.emptyChatReadyObserved = true;
        return state;
      }
      await bounded(() => pause(Math.min(1000, Math.max(1, readyDeadline - Date.now()))), false, readyDeadline);
      state = await snapshot('await-empty-ready', readyDeadline);
    }
    throw new FlowError('QA provider and empty ready hint did not appear within 30 seconds');
  }

  try {
    const initial = await snapshot('initial');
    require(initial.screenshot, 'An initial QA screenshot is required');
    let opened = initial;
    if (entry === 'shortcut') {
      require(!rows(initial).some(row => row.label === 'New Agent Chat'), 'A pre-existing chat creation dialog is open; preserve it and stop');
      await action('select-qa-workspace', tree => exact(tree, 'text', workspaceLabel).index, index => sky.click({app: appBundleId, element_index: index}));
      opened = await action('new-agent-chat-shortcut', tree => {
        require(!tree.some(row => row.label === 'New Agent Chat'), 'A chat creation dialog is already open');
      }, () => sky.press_key({app: appBundleId, key: 'super+shift+t'}));
    }
    dialogTargetsWorkspace(rows(opened), workspaceLabel);
    await action('open-agent-dropdown', tree => {
      dialogTargetsWorkspace(tree, workspaceLabel);
      return agentSelector(tree).index;
    }, index => sky.click({app: appBundleId, element_index: index}));
    const selected = await action('select-provider', tree => providerMenuEntry(tree, providerLabel).index, index => sky.click({app: appBundleId, element_index: index}));
    require(agentSelector(rows(selected)).label === providerLabel, 'The exact QA provider was not selected');
    let state = await action('start-chat', tree => {
      require(agentSelector(tree).label === providerLabel, 'QA provider selection changed before Start Chat');
      dialogTargetsWorkspace(tree, workspaceLabel);
      return exact(children(tree, dialog(tree)), 'button', 'Start Chat').index;
    }, index => sky.click({app: appBundleId, element_index: index}));
    state = await awaitChatCreated(state);
    state = await awaitEmptyReady(state);
    const clickedComposer = await action('focus-empty-composer', tree => {
      checkChat(tree);
      require(hasEmptyReadyHint(tree), 'QA provider or empty ready hint changed before focusing the composer');
      const field = composer(tree);
      require(field.label === '', 'Composer is not empty; preserve its text and stop');
      return field.index;
    }, index => sky.click({app: appBundleId, element_index: index}));
    require(clickedComposer.screenshot, 'A fresh screenshot after the explicit composer click is required');
    state = await action('type-exact-prompt', (tree, before) => {
      checkChat(tree);
      require(hasEmptyReadyHint(tree), 'QA provider or empty ready hint changed before typing');
      const field = composer(tree);
      require(field.label === '', 'Composer is not empty; exact typing cannot be retried safely');
      require(before.screenshot, 'A fresh screenshot before exact typing is required');
      const focus = before.text.match(/^\s*The focused UI element is (\d+)\b(.*)$/m);
      const editableFocus = focus && (/^\s*(?:text field|text area|search field|editable text)\b/i.test(focus[2]) || tree.find(row => row.index === Number(focus[1]))?.role === 'text field');
      require(!editableFocus || Number(focus[1]) === field.index, 'Fresh AX focus belongs to a different editable field; preserve it and stop');
      report.composerFocusMetadata = editableFocus ? 'composer' : focus ? 'generic' : 'absent';
      sidebarBeforeTyping = tree.filter(row => row.role === 'text field')[0].label;
    }, () => {
      require(!report.typingAttempted, 'Exact typing was already attempted; preserve the chat and stop');
      report.typingAttempted = true;
      return sky.type_text({app: appBundleId, text: prompt});
    }, false);
    require(composer(rows(state)).label === prompt, 'Exact prompt is absent from the composer after typing');
    require(rows(state).filter(row => row.role === 'text field')[0].label === sidebarBeforeTyping, 'Sidebar text changed during typing; preserve it and do not send');
    state = await action('send-with-return', tree => {
      checkChat(tree);
      require(composer(tree).label === prompt, 'Composer changed before Return; preserve it and stop');
      require(tree.filter(row => row.role === 'text field')[0].label === sidebarBeforeTyping, 'Sidebar text changed before Return; preserve it and do not send');
    }, () => {
      require(!report.keyboardSendAttempted, 'Return send was already attempted; preserve the chat and stop');
      report.keyboardSendAttempted = true;
      return sky.press_key({app: appBundleId, key: 'Return'});
    }, false);
    const observeDeadline = Math.min(deadline, Date.now() + observeSeconds * 1000);
    let previousAnswer = null;
    while (Date.now() < observeDeadline) {
      const tree = rows(state);
      checkChat(tree);
      const answer = inspectMacAgentChatReply({state, prompt});
      if (answer && answer.text === previousAnswer) {
        report.replyValidated = true;
        report.assistantEvidence = {marker, axIndicesAtObservation: answer.indices};
        break;
      }
      previousAnswer = answer?.text ?? null;
      await bounded(() => pause(Math.min(1000, Math.max(1, observeDeadline - Date.now()))));
      state = await snapshot('observe-reply');
    }
    require(report.replyValidated, 'No stable assistant reply marker appeared before the observation deadline');
    report.ok = true;
    await snapshot('completed');
  } catch (error) {
    report.ok = false;
    report.error = error instanceof FlowError ? error.message : 'Sky action failed; inspect the captured QA evidence';
    try {
      await snapshot('stopped');
    } catch {
      report.finalCaptureFailed = true;
    }
  }
  report.elapsedMs = Date.now() - started;
  try {
    await bounded(() => write(report), true);
  } catch {
    report.reportWriteFailed = true;
    report.ok = false;
  }
  return report;
}

export default runMacAgentChatFlow;
