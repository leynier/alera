import 'dart:convert';

import 'browser_errors.dart';
import 'browser_models.dart';

const String aleraBrowserInvalidateAutomationScript =
    'delete window.__aleraBrowserAutomation;';

String aleraBrowserSnapshotScript({
  required String namespace,
  required String pageId,
  required int pageGeneration,
  required String snapshotId,
  required bool includeSameOriginFrames,
  bool interactiveOnly = false,
  int maxNodes = 500,
}) {
  final config = jsonEncode(<String, Object?>{
    'namespace': namespace,
    'pageId': pageId,
    'pageGeneration': pageGeneration,
    'snapshotId': snapshotId,
    'includeSameOriginFrames': includeSameOriginFrames,
    'interactiveOnly': interactiveOnly,
    'maxNodes': maxNodes,
  });
  return '''
(() => {
  const config = $config;
  const snapshotKey = [
    config.namespace,
    config.pageId,
    config.pageGeneration,
    config.snapshotId,
  ].join(':');
  const state = {
    key: snapshotKey,
    sequence: 0,
    elements: new Map(),
  };
  window.__aleraBrowserAutomation = state;
  const nodes = [];
  let blockedCrossOriginFrameCount = 0;
  let truncated = false;
  let visitedCount = 0;
  const visitBudget = Math.max(config.maxNodes, config.maxNodes * 20);
  const interactive = new Set([
    'A', 'BUTTON', 'INPUT', 'SELECT', 'TEXTAREA', 'SUMMARY', 'OPTION'
  ]);
  const semantic = new Set([
    'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'P', 'LABEL', 'LI', 'DT', 'DD',
    'TH', 'TD', 'PRE', 'CODE', 'BLOCKQUOTE'
  ]);
  const roleFor = (element) => {
    const explicit = element.getAttribute('role');
    if (explicit) return explicit;
    switch (element.tagName) {
      case 'A': return element.hasAttribute('href') ? 'link' : 'generic';
      case 'BUTTON': return 'button';
      case 'SELECT': return 'combo box';
      case 'TEXTAREA': return 'text box';
      case 'SUMMARY': return 'button';
      case 'OPTION': return 'option';
      case 'IFRAME': return 'iframe';
      case 'INPUT':
        switch ((element.getAttribute('type') || 'text').toLowerCase()) {
          case 'checkbox': return 'check box';
          case 'radio': return 'radio button';
          case 'button':
          case 'submit':
          case 'reset': return 'button';
          default: return 'text box';
        }
      default: return 'generic';
    }
  };
  const concealedAutocomplete = new Set([
    'current-password', 'new-password', 'one-time-code', 'cc-number', 'cc-csc'
  ]);
  const concealedFor = (element) => {
    if (element.tagName !== 'INPUT') return false;
    if (String(element.type || '').toLowerCase() === 'password') return true;
    const autocomplete = String(element.autocomplete || '')
      .toLowerCase()
      .split(/\\s+/);
    return autocomplete.some((token) => concealedAutocomplete.has(token));
  };
  const nameFor = (element) => {
    const labelledBy = element.getAttribute('aria-labelledby');
    if (labelledBy) {
      const label = labelledBy.split(/\\s+/)
        .map((id) => element.ownerDocument.getElementById(id)?.innerText || '')
        .join(' ')
        .trim();
      if (label) return label;
    }
    return (
      element.getAttribute('aria-label') ||
      element.getAttribute('alt') ||
      element.getAttribute('title') ||
      element.getAttribute('placeholder') ||
      element.innerText ||
      (!concealedFor(element) ? element.value : '') ||
      ''
    ).trim().replace(/\\s+/g, ' ').slice(0, 500);
  };
  const valueFor = (element) =>
    'value' in element && !concealedFor(element)
      ? String(element.value ?? '').slice(0, 500)
      : null;
  const disabledFor = (element) =>
    Boolean(element.disabled) ||
    element.getAttribute('aria-disabled') === 'true';
  const signatureFor = (element) => ({
    tag: element.tagName,
    role: roleFor(element),
    name: nameFor(element),
    type: element.getAttribute('type') || '',
    childCount: element.children.length,
    disabled: disabledFor(element),
  });
  const visible = (element) => {
    const view = element.ownerDocument.defaultView;
    const style = view?.getComputedStyle(element);
    const rect = element.getBoundingClientRect();
    return style?.visibility !== 'hidden' && style?.display !== 'none' &&
      rect.width > 0 && rect.height > 0;
  };
  const visitRoot = (root, depth) => {
    for (const child of root.children || []) {
      visit(child, depth);
      if (truncated) return;
    }
  };
  const visit = (element, depth) => {
    if (truncated) return;
    visitedCount += 1;
    if (visitedCount > visitBudget || nodes.length >= config.maxNodes) {
      truncated = true;
      return;
    }
    if (!element || element.nodeType !== 1 || !visible(element)) return;
    const signature = signatureFor(element);
    const include = interactive.has(element.tagName) ||
      signature.role !== 'generic' || element.hasAttribute('tabindex') ||
      element.isContentEditable || (!config.interactiveOnly &&
        signature.name && (semantic.has(element.tagName) ||
          element.children.length === 0));
    if (include) {
      const ref = snapshotKey + ':e' + (++state.sequence);
      state.elements.set(ref, {element, signature});
      nodes.push({
        ref,
        role: signature.role,
        name: signature.name,
        value: valueFor(element),
        depth,
        disabled: signature.disabled,
        checked: 'checked' in element ? Boolean(element.checked) : null,
      });
    }
    if (element.shadowRoot) visitRoot(element.shadowRoot, depth + 1);
    for (const child of element.children) {
      visit(child, depth + 1);
      if (truncated) return;
    }
    if (config.includeSameOriginFrames && element.tagName === 'IFRAME') {
      try {
        const body = element.contentDocument?.body;
        if (body) {
          visit(body, depth + 1);
        } else {
          blockedCrossOriginFrameCount += 1;
        }
      } catch (_) {
        blockedCrossOriginFrameCount += 1;
      }
    }
  };
  if (document.body) visit(document.body, 0);
  state.signatureFor = signatureFor;
  return JSON.stringify({
    namespace: config.namespace,
    pageGeneration: config.pageGeneration,
    snapshotId: config.snapshotId,
    url: location.href,
    title: document.title || '',
    blockedCrossOriginFrameCount,
    truncated,
    nodes,
  });
})()
''';
}

String aleraBrowserActionScript(AleraBrowserAction action) {
  final payload = jsonEncode(<String, Object?>{
    'kind': action.kind.name,
    'ref': action.elementRef,
    'value': action.value,
    'values': action.values,
    'targetRef': action.targetElementRef,
    'offsetX': action.offsetX,
    'offsetY': action.offsetY,
  });
  return '''
(() => {
  const action = $payload;
  const state = window.__aleraBrowserAutomation;
  const entry = state?.elements?.get(action.ref);
  const stale = (candidate) => {
    if (!candidate?.element?.isConnected) return true;
    return JSON.stringify(state.signatureFor(candidate.element)) !==
      JSON.stringify(candidate.signature);
  };
  if (stale(entry)) {
    return JSON.stringify({ok: false, code: 'stale_element'});
  }
  const element = entry.element;
  const viewFor = (target) => target.ownerDocument?.defaultView ?? window;
  const eventFor = (target, type) =>
    new (viewFor(target).Event)(type, {bubbles: true});
  const mouseEventFor = (target, type) =>
    new (viewFor(target).MouseEvent)(type, {bubbles: true});
  const keyboardEventFor = (target, type) =>
    new (viewFor(target).KeyboardEvent)(type, {
      key: action.value ?? '',
      bubbles: true,
    });
  const emitValue = () => {
    element.dispatchEvent(eventFor(element, 'input'));
    element.dispatchEvent(eventFor(element, 'change'));
  };
  switch (action.kind) {
    case 'click':
      element.click();
      break;
    case 'focus':
      element.focus();
      break;
    case 'fill':
      element.focus();
      element.value = action.value ?? '';
      emitValue();
      break;
    case 'clear':
      element.focus();
      if ('value' in element) element.value = '';
      else if (element.isContentEditable) element.textContent = '';
      else return JSON.stringify({ok: false, code: 'wrong_element_type'});
      emitValue();
      break;
    case 'type':
      element.focus();
      if ('value' in element) {
        element.value = String(element.value ?? '') + (action.value ?? '');
      } else if (element.isContentEditable) {
        element.textContent = String(element.textContent ?? '') +
          (action.value ?? '');
      } else {
        return JSON.stringify({ok: false, code: 'wrong_element_type'});
      }
      emitValue();
      break;
    case 'select':
      if (element.tagName !== 'SELECT') {
        return JSON.stringify({ok: false, code: 'wrong_element_type'});
      }
      for (const option of element.options) {
        option.selected = action.values.includes(option.value);
      }
      emitValue();
      break;
    case 'check':
    case 'uncheck':
      if (!('checked' in element)) {
        return JSON.stringify({ok: false, code: 'wrong_element_type'});
      }
      element.checked = action.kind === 'check';
      emitValue();
      break;
    case 'hover':
      element.dispatchEvent(mouseEventFor(element, 'mouseenter'));
      element.dispatchEvent(mouseEventFor(element, 'mouseover'));
      break;
    case 'scrollIntoView':
      element.scrollIntoView({block: 'center', inline: 'center'});
      break;
    case 'scroll':
      element.scrollBy({left: action.offsetX, top: action.offsetY});
      break;
    case 'drag':
      const target = state.elements.get(action.targetRef);
      if (stale(target)) {
        return JSON.stringify({ok: false, code: 'stale_target'});
      }
      element.dispatchEvent(mouseEventFor(element, 'mousedown'));
      target.element.dispatchEvent(mouseEventFor(target.element, 'mousemove'));
      target.element.dispatchEvent(mouseEventFor(target.element, 'mouseup'));
      break;
    case 'keyPress':
      element.focus();
      element.dispatchEvent(keyboardEventFor(element, 'keydown'));
      element.dispatchEvent(keyboardEventFor(element, 'keyup'));
      break;
    default:
      return JSON.stringify({ok: false, code: 'unsupported_action'});
  }
  return JSON.stringify({ok: true});
})()
''';
}

String aleraBrowserWaitScript(AleraBrowserWaitCondition condition) {
  final payload = jsonEncode(<String, Object?>{
    'kind': condition.kind.name,
    'value': condition.value,
    'exact': condition.exact,
  });
  return '''
(() => {
  const condition = $payload;
  if (condition.kind === 'url') {
    return condition.exact
      ? location.href === condition.value
      : location.href.includes(condition.value);
  }
  const roots = [document];
  for (let index = 0; index < roots.length; index += 1) {
    const root = roots[index];
    for (const element of root.querySelectorAll('*')) {
      if (element.shadowRoot) roots.push(element.shadowRoot);
      if (element.tagName === 'IFRAME') {
        try {
          if (element.contentDocument) roots.push(element.contentDocument);
        } catch (_) {}
      }
    }
  }
  if (condition.kind === 'selector') {
    return roots.some((root) => {
      try { return Boolean(root.querySelector(condition.value)); }
      catch (_) { return false; }
    });
  }
  const text = roots.map((root) => root.body?.innerText || root.textContent || '')
    .join('\\n');
  return condition.exact ? text.trim() === condition.value : text.includes(condition.value);
})()
''';
}

AleraBrowserSnapshot decodeAleraBrowserSnapshot(String pageId, Object? raw) {
  final value = decodeAleraBrowserJavaScriptJson(raw);
  if (value is! Map<Object?, Object?> || value['nodes'] is! List<Object?>) {
    throw const AleraBrowserNativeError(
      'invalid_snapshot',
      'The engine returned a malformed browser snapshot.',
    );
  }
  final rawNodes = value['nodes']! as List<Object?>;
  final nodes = <AleraBrowserSnapshotNode>[];
  for (final rawNode in rawNodes) {
    if (rawNode is! Map<Object?, Object?>) {
      continue;
    }
    nodes.add(
      AleraBrowserSnapshotNode(
        ref: rawNode['ref'] as String? ?? '',
        role: rawNode['role'] as String? ?? 'generic',
        name: rawNode['name'] as String? ?? '',
        value: rawNode['value'] as String?,
        depth: (rawNode['depth'] as num?)?.toInt() ?? 0,
        disabled: rawNode['disabled'] as bool? ?? false,
        checked: rawNode['checked'] as bool?,
      ),
    );
  }
  final rawUrl = value['url'] as String?;
  return AleraBrowserSnapshot(
    pageId: pageId,
    namespace: value['namespace'] as String? ?? '',
    pageGeneration: (value['pageGeneration'] as num?)?.toInt() ?? 0,
    snapshotId: value['snapshotId'] as String? ?? '',
    url: rawUrl == null ? null : Uri.tryParse(rawUrl),
    title: value['title'] as String? ?? '',
    nodes: nodes,
    blockedCrossOriginFrameCount:
        (value['blockedCrossOriginFrameCount'] as num?)?.toInt() ?? 0,
    truncated: value['truncated'] as bool? ?? false,
  );
}

void validateAleraBrowserActionResult(Object? raw) {
  final value = decodeAleraBrowserJavaScriptJson(raw);
  if (value is Map<Object?, Object?> && value['ok'] == true) {
    return;
  }
  final code = value is Map<Object?, Object?>
      ? value['code'] as String? ?? 'action_failed'
      : 'action_failed';
  throw AleraBrowserStateError(code, 'The browser rejected the DOM action.');
}

Object? decodeAleraBrowserJavaScriptJson(Object? raw) {
  Object? value = raw;
  for (var index = 0; index < 2 && value is String; index += 1) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      break;
    }
  }
  return value;
}
