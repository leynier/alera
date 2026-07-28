import 'dart:convert';

import 'package:alera_browser/alera_browser.dart';
import 'package:alera_browser/src/dom_automation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot decoder preserves namespace and stale-ref dimensions', () {
    final payload = jsonEncode(<String, Object?>{
      'namespace': 'tab-a',
      'pageGeneration': 3,
      'snapshotId': 's9',
      'url': 'https://example.test/',
      'title': 'Example',
      'blockedCrossOriginFrameCount': 1,
      'truncated': true,
      'nodes': <Object?>[
        <String, Object?>{
          'ref': 'tab-a:page:3:s9:e1',
          'role': 'button',
          'name': 'Submit',
          'value': null,
          'depth': 2,
          'disabled': false,
          'checked': null,
        },
      ],
    });

    final snapshot = decodeAleraBrowserSnapshot('page', jsonEncode(payload));

    expect(snapshot.namespace, 'tab-a');
    expect(snapshot.pageGeneration, 3);
    expect(snapshot.snapshotId, 's9');
    expect(snapshot.blockedCrossOriginFrameCount, 1);
    expect(snapshot.truncated, isTrue);
    expect(snapshot.nodes.single.ref, endsWith(':s9:e1'));
  });

  test(
    'action script revalidates signature and supports required primitives',
    () {
      final script = aleraBrowserActionScript(
        const AleraBrowserAction(
          kind: AleraBrowserActionKind.drag,
          elementRef: 'source',
          targetElementRef: 'target',
        ),
      );

      expect(script, contains('signatureFor'));
      expect(script, contains('isConnected'));
      expect(script, contains('stale_target'));
      expect(script, contains("case 'clear'"));
      expect(script, contains("case 'scroll'"));
      expect(script, contains("case 'drag'"));
    },
  );

  test('action events use the target element document realm', () {
    final script = aleraBrowserActionScript(
      const AleraBrowserAction(
        kind: AleraBrowserActionKind.drag,
        elementRef: 'source',
        targetElementRef: 'target',
      ),
    );

    expect(
      script,
      contains(
        'const viewFor = (target) => '
        'target.ownerDocument?.defaultView ?? window;',
      ),
    );
    expect(script, contains('new (viewFor(target).Event)'));
    expect(script, contains('new (viewFor(target).MouseEvent)'));
    expect(script, contains('new (viewFor(target).KeyboardEvent)'));
    expect(script, contains("eventFor(element, 'input')"));
    expect(script, contains("mouseEventFor(element, 'mousedown')"));
    expect(script, contains("mouseEventFor(target.element, 'mousemove')"));
    expect(script, contains("keyboardEventFor(element, 'keydown')"));
    expect(script, isNot(contains("new Event('")));
    expect(script, isNot(contains("new MouseEvent('")));
    expect(script, isNot(contains("new KeyboardEvent('")));
  });

  test('snapshot script traverses shadow roots and same-origin frames', () {
    final script = aleraBrowserSnapshotScript(
      namespace: 'tab',
      pageId: 'page',
      pageGeneration: 4,
      snapshotId: 'snapshot',
      includeSameOriginFrames: true,
      interactiveOnly: true,
      maxNodes: 25,
    );

    expect(script, contains('element.shadowRoot'));
    expect(script, contains('element.contentDocument'));
    expect(script, contains('blockedCrossOriginFrameCount'));
    expect(script, contains('visitedCount > visitBudget'));
    expect(script, contains('nodes.length >= config.maxNodes'));
    expect(script, contains('config.interactiveOnly'));
    expect(script, contains('element.contentDocument?.body'));
    expect(script, contains('blockedCrossOriginFrameCount += 1'));
    expect(script, contains('childCount'));
    expect(script, contains("String(element.type || '').toLowerCase()"));
    expect(script, contains("'current-password', 'new-password'"));
    expect(script, contains("'one-time-code', 'cc-number', 'cc-csc'"));
    expect(script, contains('concealedAutocomplete.has(token)'));
    expect(script, contains("!concealedFor(element) ? element.value : ''"));
    expect(script, contains('value: valueFor(element)'));
    expect(script, contains("String(element.value ?? '').slice(0, 500)"));
    expect(
      script,
      isNot(
        contains(
          "value: 'value' in element ? String(element.value ?? '') : null",
        ),
      ),
    );
  });
}
