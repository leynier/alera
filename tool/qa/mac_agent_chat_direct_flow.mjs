// Public Sky and private evidence storage are injected by the caller. This module has no host access.
const FLOW_MS = 300_000;
const CALL_MS = 30_000;
const SEARCH_HINT = 'Search agents and models';
const AX_ROLE = 'standard window|text field|text area|search field|menu item|pop up button|scroll area|container|button|checkbox|heading|dialog|group|menu|tab|text';
const EDITABLE = new Set(['text field', 'text area', 'search field']);
class FlowError extends Error {}
function require(condition, message) { if (!condition) throw new FlowError(message); }
function label(value) { return typeof value === 'string' && value.length > 0 && value.length <= 256 && value.trim() === value && !/[\r\n]/.test(value); }

function rows(state) {
  require(typeof state?.text === 'string', 'Sky did not return AX text');
  require(!/^\s*The following is a diff/.test(state.text), 'A fresh full AX snapshot is required');
  const result = [], pattern = new RegExp(`^([\\t ]*)(\\d+) (${AX_ROLE})\\b(.*)$`);
  for (const line of state.text.split('\n')) {
    const match = line.match(pattern);
    if (match) {
      const annotations = match[4].match(/^\s*((?:\([^)]*\)\s*)*)/);
      const flags = annotations[1], text = match[4].slice(annotations[0].length).trim();
      result.push({index: Number(match[2]), depth: match[1].replace(/\t/g, '    ').length, role: match[3], label: text, fullLabel: text, flags});
    } else if (result.length && line.trim() && !/^\s*(?:Window:|The focused UI element|\d+ menu bar)/.test(line)) {
      result.at(-1).fullLabel += '\n' + line.trim();
    }
  }
  require(new Set(result.map(row => row.index)).size === result.length, 'Full AX snapshot contains ambiguous indices');
  return result;
}
function fields(tree) { return tree.filter(row => EDITABLE.has(row.role)); }
function exact(tree, roles, text) {
  const matches = tree.filter(row => roles.includes(row.role) && row.label === text);
  require(matches.length === 1, 'Expected one fresh AX target with the exact requested label');
  require(!/disabled|unavailable/i.test(matches[0].flags), 'The requested AX target is disabled');
  return matches[0];
}
function composer(tree) {
  const inputs = fields(tree);
  require(inputs.length === 2, 'Expected only sidebar search and the chat composer');
  require(!/disabled|readonly|read only/i.test(inputs[1].flags), 'Chat composer is not editable');
  return inputs[1];
}
function focus(state) {
  const match = state.text.match(/^\s*The focused UI element is (\d+)\b(.*)$/m);
  return match ? {index: Number(match[1]), description: match[2]} : null;
}
function children(tree, parent) {
  const start = tree.indexOf(parent) + 1;
  let end = start;
  while (end < tree.length && tree[end].depth > parent.depth) end++;
  return tree.slice(start, end);
}
function pickerField(tree) {
  const inputs = fields(tree);
  require(inputs.length === 3, 'The model picker search field is not visible');
  return inputs[2];
}
function modelTarget(tree, provider, model) {
  const search = pickerField(tree);
  const popup = tree.slice(tree.indexOf(search) + 1);
  const header = exact(popup, ['text', 'heading', 'container', 'group'], provider);
  const nested = children(popup, header);
  // Flat Flutter AX sections end at the next heading or provider label at the same depth.
  const section = nested.length ? nested : popup.slice(popup.indexOf(header) + 1).filter((row, index, rest) =>
    !rest.slice(0, index + 1).some(candidate => candidate.role === 'heading' || (candidate.depth <= header.depth && /^QA\b/.test(candidate.label))));
  const target = exact(section, ['text', 'button', 'menu item'], model);
  require(!/unavailable|disabled|cannot switch|not logged in/i.test(target.fullLabel), 'Requested model is unavailable');
  return target;
}
function visibleError(tree, prompt) {
  return tree.some(row => !EDITABLE.has(row.role) && row.label !== prompt && /^(?:provider protocol error|provider unavailable|not logged in|authentication failed|auth required|failed after|the turn failed|the agent session stopped|failed to (?:start|spawn)|error:)/i.test(row.label));
}

/** Pure UI evidence only; it never establishes runtime terminal status. */
export function inspectMacAgentChatDirectReply({state, prompt, replyMarker} = {}) {
  require(label(replyMarker) && typeof prompt === 'string' && prompt.includes(replyMarker), 'Provide the exact prompt and reply marker');
  const tree = rows(state), input = composer(tree);
  if (input.fullLabel !== '' || visibleError(tree, prompt)) return null;
  const transcript = tree.slice(tree.indexOf(fields(tree)[0]) + 1, tree.indexOf(input));
  const prompts = transcript.filter(row => row.role === 'text' && row.label === prompt);
  if (prompts.length !== 1) return null;
  const user = prompts[0], after = transcript.slice(transcript.indexOf(user) + 1);
  const suffix = user.fullLabel.startsWith(prompt + '\n') ? user.fullLabel.slice(prompt.length + 1) : '';
  const escaped = replyMarker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const marker = new RegExp(`(?:^|[^A-Za-z0-9_-])${escaped}(?=$|[^A-Za-z0-9_-])`);
  if ([suffix, ...after.map(row => row.fullLabel)].some(text => text.includes(prompt) || /^(?:You|User|User message)(?::|$)/im.test(text))) return null;
  // Unlabelled merged AX text needs a turn boundary; a bare prompt suffix could be a user echo.
  const boundary = /^(?:Assistant(?::|$)|Worked for\b|Working for\b)/m;
  const answers = after.filter(row => row.role === 'text' && marker.test(row.fullLabel));
  const explicitAssistant = answers.filter(row => /^Assistant:\s/m.test(row.fullLabel) || after.slice(0, after.indexOf(row)).some(candidate => candidate.label === 'Assistant' || /^Worked for\b/.test(candidate.label)));
  if (suffix && marker.test(suffix) && boundary.test(suffix)) explicitAssistant.unshift({fullLabel: suffix, index: user.index});
  if (!explicitAssistant.length) return null;
  return {marker: replyMarker, text: explicitAssistant.map(row => row.fullLabel).join('\n'), indices: explicitAssistant.map(row => row.index)};
}

/**
 * entry: empty-panel, add-tab, or existing-chat. All QA labels and replyMarker are explicit.
 * pickerLabel names the current chip if selection is needed; modelSearch is optional.
 * Reuse an existing empty composer only with a prompt that has not already appeared in its transcript.
 * capture({label,sequence,state,elapsedMs}) stores private evidence and returns path metadata.
 * verifyComposer(state,{prompt,providerLabel,modelLabel}) must assess the actual screenshot immediately
 * before Send and return {screenshotVerified:true,exactPrompt:true}. AX values alone cannot prove it.
 * selectSendTarget(state), only when no semantic Send button exists, must return
 * {screenshotVerified:true, element_index} or {screenshotVerified:true, x, y} for that fresh state.
 * confirmRuntime({state,replyMarker,...labels}) is an optional read-only caller check returning
 * {confirmed:true,status:'succeeded'|'failed'|'cancelled'|'stopped'}; UI evidence stays separate.
 */
export async function runMacAgentChatDirectFlow({sky, capture, write, pause, verifyComposer, appBundleId, entry, workspaceLabel, chatLabel, providerLabel, modelLabel, pickerLabel = modelLabel, modelSearch, prompt, replyMarker, selectSendTarget, confirmRuntime, observeSeconds = 60} = {}) {
  require(typeof appBundleId === 'string' && /^dev\.leynier\.alera\.agentqa(?:\.[A-Za-z0-9_-]+)*$/.test(appBundleId), 'An explicit Agent QA app bundle is required');
  require(['empty-panel', 'add-tab', 'existing-chat'].includes(entry), 'Choose an explicit direct entry');
  require([workspaceLabel, chatLabel, providerLabel, modelLabel, pickerLabel].every(label) && /^QA\b/.test(workspaceLabel) && /^QA\b/.test(providerLabel), 'Explicit exact QA workspace, chat, provider, model, and picker labels are required');
  require(typeof prompt === 'string' && prompt.length > 0 && prompt.length <= 4096 && !/[\r\n]/.test(prompt), 'Provide a bounded single-line exact QA prompt');
  require(label(replyMarker) && /^[A-Z0-9_-]+$/.test(replyMarker) && /(?:^|[-_])QA(?:$|[-_])/.test(replyMarker) && prompt.includes(replyMarker), 'Provide an explicit uppercase QA reply marker in the prompt');
  require(modelSearch === undefined || label(modelSearch), 'Model search must be a bounded exact query');
  require(Number.isFinite(observeSeconds) && observeSeconds > 0 && observeSeconds <= 180, 'Observation must be between zero and 180 seconds');
  require(['get_app_state', 'click', 'type_text'].every(method => typeof sky?.[method] === 'function'), 'Inject the public Sky API');
  require([capture, write, pause].every(callback => typeof callback === 'function'), 'Inject private capture, write, and pause callbacks');
  require(typeof verifyComposer === 'function', 'Inject verifyComposer for actual screenshot confirmation before Send');
  require([selectSendTarget, confirmRuntime].every(callback => callback === undefined || typeof callback === 'function'), 'Optional selectors and runtime confirmation must be callbacks');
  const started = Date.now(), deadline = started + FLOW_MS;
  const report = {bundleId: appBundleId, entry, workspaceLabel, chatLabel, providerLabel, modelLabel, replyMarker, actions: [], observations: [], staleSnapshots: 0, typingAttempted: false, sendAttempted: false, selectionVerified: false, composerVisualVerified: false, replyValidated: false, turnTerminalStatusVerified: false, runtimeConfirmationRequested: Boolean(confirmRuntime)};
  let sequence = 0, sidebar;

  async function bounded(operation, until = deadline) {
    const remaining = Math.min(CALL_MS, until - Date.now());
    require(remaining > 0, 'Mac direct QA deadline exceeded');
    let timer;
    try {
      return await Promise.race([Promise.resolve().then(operation), new Promise((_, reject) => {
        timer = setTimeout(() => reject(new FlowError('Mac direct QA call deadline exceeded')), remaining);
      })]);
    } finally { clearTimeout(timer); }
  }
  async function snapshot(name, until = deadline) {
    let state;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        state = await bounded(() => sky.get_app_state({app: appBundleId, disableDiff: true}), until);
        rows(state);
        break;
      } catch (error) {
        if (attempt || !/snapshot.*stale|app.*changed.*snapshot/i.test(String(error?.message))) throw error;
        report.staleSnapshots++;
      }
    }
    const metadata = await bounded(() => capture({label: name, sequence: sequence++, state, elapsedMs: Date.now() - started}), until);
    report.observations.push({label: name, elapsedMs: Date.now() - started, screenshotAvailable: Boolean(state.screenshot), axPath: metadata?.axPath ?? null, screenshotPath: metadata?.screenshotPath ?? null});
    return state;
  }
  function context(tree, needChat = false) {
    require(!tree.some(row => row.role === 'dialog' || row.label === 'New Agent Chat' || row.label === 'Start Chat'), 'A modal is visible; direct replay stops');
    require(tree.some(row => row.label === workspaceLabel), 'The exact QA workspace is not visible; preserve navigation and stop');
    if (needChat) require(tree.some(row => row.label === chatLabel), 'The exact QA chat label is not visible');
    if (visibleError(tree, prompt)) {
      report.providerErrorVisible = true;
      throw new FlowError('Provider error is visible; inspect private evidence');
    }
  }
  function selection(tree) {
    context(tree, true);
    composer(tree);
    require(!tree.some(row => !EDITABLE.has(row.role) && row.fullLabel.includes(prompt)), 'The exact QA prompt is already in the transcript; never resend it');
    require(observedSelection(tree), 'Observed provider/model does not match the exact requested selection');
    report.selectionVerified = true;
  }
  function observedSelection(tree) {
    const input = composer(tree), position = tree.indexOf(input);
    const footer = tree.slice(position + 1), body = tree.slice(tree.indexOf(fields(tree)[0]) + 1, position);
    const exactLine = (region, value) => region.some(row => row.role === 'text' && row.fullLabel.split('\n').some(line => line.trim() === value));
    // Model text in an old transcript cannot stand in for the actual footer chip.
    const chip = footer.some(row => row.label === modelLabel && ['text', 'button', 'pop up button'].includes(row.role));
    const emptyCard = exactLine(body, `${providerLabel} · ${modelLabel}`) && exactLine(body, 'Send a message to start.');
    return chip && (emptyCard || exactLine(footer, providerLabel));
  }
  async function action(name, select, operate, needChat = true) {
    const before = await snapshot(`${name}-before`);
    require(before.screenshot, 'A fresh screenshot before every action is required');
    const tree = rows(before);
    context(tree, needChat);
    const target = await bounded(() => select(tree, before));
    report.actions.push({label: name, attempted: true, completed: false});
    try {
      await bounded(() => operate(target));
      report.actions.at(-1).completed = true;
    } catch (error) {
      report.actionUncertain = true;
      // A rejected click can already have applied. Never replay a mutation, even a selector click.
      try { await snapshot(`${name}-after-error`, Math.min(deadline, Date.now() + 5000)); } catch { report.finalCaptureFailed = true; }
      throw error;
    }
    return snapshot(`${name}-after`);
  }
  const click = target => sky.click({app: appBundleId, ...target});
  const indexed = row => ({element_index: row.index});
  function requireComposerFocus(tree, state) {
    const current = focus(state), input = composer(tree);
    const editable = current && (fields(tree).some(row => row.index === current.index) || /text field|text area|search field|editable text/i.test(current.description));
    require(!editable || current.index === input.index, 'Fresh AX focus belongs to a different editable field; stop before typing');
    report.composerFocusMetadata = editable ? 'composer' : current ? 'generic' : 'absent';
  }
  async function wait(state, name, seconds, predicate, needChat = true) {
    const until = Math.min(deadline, Date.now() + seconds * 1000);
    for (let sample = 0; sample <= Math.ceil(seconds); sample++) {
      context(rows(state), needChat);
      if (predicate(state)) return state;
      require(Date.now() < until && sample < Math.ceil(seconds), `Mac direct QA ${name} timeout`);
      await bounded(() => pause(Math.min(1000, until - Date.now())), until);
      state = await snapshot(name, until);
    }
  }

  try {
    let state = await snapshot('initial');
    require(state.screenshot, 'An initial QA screenshot is required');
    context(rows(state));
    if (entry === 'empty-panel') {
      state = await action('open-empty-panel-chat', tree => {
        require(tree.some(row => row.label === 'Panel is empty'), 'The empty panel card is not visible');
        return indexed(exact(tree, ['text', 'button'], 'Agent Chat'));
      }, click, false);
    } else if (entry === 'add-tab') {
      await action('open-add-tab-menu', tree => indexed(exact(tree, ['button'], 'Add Tab')), click, false);
      state = await action('choose-agent-chat', tree => {
        require(tree.some(row => row.label === 'Dismiss menu' || row.role === 'menu'), 'The Add Tab menu is not visible');
        return indexed(exact(tree, ['text', 'menu item', 'button'], 'Agent Chat'));
      }, click, false);
    } else {
      state = await action('open-existing-chat', tree => {
        const roles = tree.some(row => ['tab', 'button'].includes(row.role) && row.label === chatLabel) ? ['tab', 'button'] : ['text'];
        return indexed(exact(tree, roles, chatLabel));
      }, click, false);
    }
    state = await wait(state, 'await-composer', 30, candidate => {
      const current = rows(candidate), inputs = fields(current);
      if (!current.some(row => row.label === chatLabel)) return false;
      if (inputs.length < 2) return false;
      require(composer(rows(candidate)).fullLabel === '', 'Composer is not empty; preserve its draft and stop');
      return true;
    }, false);
    const tree = rows(state);
    require(!tree.some(row => !EDITABLE.has(row.role) && row.fullLabel.includes(prompt)), 'The exact QA prompt is already in the transcript; never resend it');
    const alreadySelected = observedSelection(tree);
    if (!alreadySelected || modelSearch !== undefined) {
      await action('open-model-picker', current => {
        require(composer(current).fullLabel === '', 'Composer is not empty; stop before selection');
        // The chip is rendered after the composer, outside the transcript and sidebar.
        return indexed(exact(current.slice(current.indexOf(composer(current)) + 1), ['text', 'button', 'pop up button'], pickerLabel));
      }, click);
      if (modelSearch !== undefined) {
        await action('search-model-picker', (current, before) => {
          const search = pickerField(current);
          require(focus(before)?.index === search.index, 'Picker search is not the snapshot-focused field; do not click or type');
          require(search.fullLabel === '' || search.fullLabel === SEARCH_HINT, 'Picker search contains existing text; preserve it');
        }, () => sky.type_text({app: appBundleId, text: modelSearch}));
      }
      state = await action('select-exact-model', current => indexed(modelTarget(current, providerLabel, modelLabel)), click);
    }
    selection(rows(state));
    await action('focus-empty-composer', current => {
      selection(current);
      require(composer(current).fullLabel === '', 'Composer is not empty; preserve its draft');
      return indexed(composer(current));
    }, click);
    state = await action('type-exact-prompt', (current, before) => {
      selection(current);
      require(composer(current).fullLabel === '', 'Composer changed; exact typing cannot be retried');
      requireComposerFocus(current, before);
      sidebar = fields(current)[0].fullLabel;
    }, () => {
      require(!report.typingAttempted, 'Exact prompt typing was already attempted');
      report.typingAttempted = true;
      return sky.type_text({app: appBundleId, text: prompt});
    });
    require(composer(rows(state)).fullLabel === prompt, 'The exact prompt did not render in the composer; do not send');
    state = await action('send-exact-prompt', async (current, before) => {
      selection(current);
      require(composer(current).fullLabel === prompt, 'Composer changed before Send; preserve it');
      require(fields(current)[0].fullLabel === sidebar, 'Sidebar changed during typing; do not send');
      const semantic = current.filter(row => row.role === 'button' && ['Send', 'Send Message'].includes(row.label));
      require(semantic.length <= 1, 'Semantic Send target is ambiguous');
      let sendTarget, verificationState = before;
      if (semantic.length) {
        require(!/disabled|unavailable/i.test(semantic[0].flags), 'Semantic Send button is disabled');
        report.sendTargetSource = 'semantic';
        sendTarget = indexed(semantic[0]);
      } else {
        require(typeof selectSendTarget === 'function', 'No semantic Send button; inject selectSendTarget for this fresh screenshot');
        const target = await bounded(() => selectSendTarget(before));
        require(target?.screenshotVerified === true, 'Send target must be explicitly screenshot-verified');
        const verified = await snapshot('verify-injected-send-target');
        require(verified.screenshot && verified.text === before.text, 'Send selector snapshot changed; do not send or retry');
        const index = Number.isInteger(target.element_index) && target.element_index >= 0;
        const coordinates = Number.isFinite(target.x) && Number.isFinite(target.y) && target.x >= 0 && target.y >= 0;
        require(index !== coordinates, 'Provide either a fresh Send index or coordinates');
        if (index) require(current.some(row => row.index === target.element_index && !EDITABLE.has(row.role) && !/disabled/.test(row.flags)), 'Injected Send index is absent or unsafe in the fresh snapshot');
        report.sendTargetSource = 'screenshot';
        sendTarget = index ? {element_index: target.element_index} : {x: target.x, y: target.y};
        verificationState = verified;
      }
      const proof = await bounded(() => verifyComposer(verificationState, {prompt, providerLabel, modelLabel}));
      require(proof?.screenshotVerified === true && proof.exactPrompt === true, 'Composer visual confirmation failed; preserve the draft and do not send');
      report.composerVisualVerified = true;
      return sendTarget;
    }, target => {
      require(!report.sendAttempted, 'Send was already attempted; never retry');
      report.sendAttempted = true;
      return click(target);
    });
    let previous = null;
    state = await wait(state, 'observe-reply', observeSeconds, candidate => {
      const answer = inspectMacAgentChatDirectReply({state: candidate, prompt, replyMarker});
      const stable = answer && answer.text === previous;
      previous = answer?.text ?? null;
      if (!stable) return false;
      report.replyValidated = true;
      report.assistantEvidence = {marker: replyMarker, axIndicesAtObservation: answer.indices};
      return true;
    });
    report.ok = true;
    if (confirmRuntime) {
      try {
        const confirmation = await bounded(() => confirmRuntime({state, replyMarker, workspaceLabel, chatLabel, providerLabel, modelLabel}));
        if (confirmation?.confirmed === true && ['succeeded', 'failed', 'cancelled', 'stopped'].includes(confirmation.status)) {
          report.turnTerminalStatusVerified = true;
          report.turnTerminalStatus = confirmation.status;
          report.ok = confirmation.status === 'succeeded';
        }
      } catch { report.runtimeConfirmationFailed = true; }
    }
    await snapshot('completed');
  } catch (error) {
    report.ok = false;
    report.error = error instanceof FlowError ? error.message : 'Sky action failed; inspect private QA evidence';
    try { await snapshot('stopped', Date.now() + 5000); } catch { report.finalCaptureFailed = true; }
  }
  report.elapsedMs = Date.now() - started;
  try { await bounded(() => write(report), Date.now() + 5000); } catch { report.reportWriteFailed = true; report.ok = false; }
  return report;
}

export default runMacAgentChatDirectFlow;
