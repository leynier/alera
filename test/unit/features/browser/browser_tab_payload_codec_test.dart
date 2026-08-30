import 'dart:convert';

import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/infra/browser_tab_payload_codec.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = BrowserTabPayloadCodec();

  test('uses workspace tab id as the stable browser page id', () {
    final tab = _tab(
      payload: const <String, Object?>{
        workspaceTabBrowserProfileIdPayloadKey: 'work',
        workspaceTabBrowserUrlPayloadKey: 'https://example.com/docs',
        workspaceTabBrowserRuntimeTitlePayloadKey: 'Docs',
      },
    );

    final decoded = codec.decode(tab);

    expect(decoded.page.pageId, tab.id);
    expect(decoded.page.workspaceId, tab.workspaceId);
    expect(decoded.page.profileId, 'work');
    expect(decoded.page.initialUrl.toString(), 'https://example.com/docs');
    expect(decoded.runtimeTitle, 'Docs');
  });

  test('preserves unrelated payload and omits sensitive URLs', () {
    final payload = codec.encodePayload(
      existing: const <String, Object?>{'manualTitle': true, 'other': 7},
      profileId: 'work',
      url: Uri.parse('https://example.com/callback?token=secret'),
      runtimeTitle: 'Account',
    );

    expect(payload['manualTitle'], isTrue);
    expect(payload['other'], 7);
    expect(payload[workspaceTabBrowserProfileIdPayloadKey], 'work');
    expect(payload, isNot(contains(workspaceTabBrowserUrlPayloadKey)));
    expect(payload, isNot(contains(workspaceTabBrowserRuntimeTitlePayloadKey)));
  });

  test('rejects unsafe or sensitive saved addresses', () {
    for (final url in <String>[
      'file:///tmp/private',
      'https://example.com/oauth/callback',
      'https://user:password@example.com/private',
    ]) {
      expect(
        () => codec.decode(
          _tab(
            payload: <String, Object?>{
              workspaceTabBrowserProfileIdPayloadKey: 'default',
              workspaceTabBrowserUrlPayloadKey: url,
            },
          ),
        ),
        throwsA(
          isA<BrowserFailure>().having(
            (failure) => failure.code,
            'code',
            BrowserErrorCode.invalidPayload,
          ),
        ),
      );
    }
  });

  test('normalizes titles and drops titles associated with sensitive URLs', () {
    final rawTitle = ' \u0000Docs\n${List<String>.filled(300, '🚀').join()}\t ';
    final safe = codec.encodePayload(
      existing: const <String, Object?>{},
      profileId: 'work',
      url: Uri.parse('https://example.com/docs'),
      runtimeTitle: rawTitle,
    );
    final sensitive = codec.encodePayload(
      existing: safe,
      profileId: 'work',
      url: Uri.parse('https://example.com/oauth/callback?code=secret'),
      runtimeTitle: 'Private Account',
    );

    final normalized =
        safe[workspaceTabBrowserRuntimeTitlePayloadKey]! as String;
    expect(normalized.codeUnits, isNot(contains(0)));
    expect(utf8.encode(normalized), hasLength(aleraBrowserTitleMaximumBytes));
    expect(
      sensitive,
      isNot(contains(workspaceTabBrowserRuntimeTitlePayloadKey)),
    );
  });

  test('does not decode a page-controlled title without its URL', () {
    final decoded = codec.decode(
      _tab(
        payload: const <String, Object?>{
          workspaceTabBrowserProfileIdPayloadKey: 'work',
          workspaceTabBrowserRuntimeTitlePayloadKey: 'Private Account',
        },
      ),
    );

    expect(decoded.page.initialUrl.toString(), 'about:blank');
    expect(decoded.runtimeTitle, isNull);
  });

  test('does not encode a page-controlled title without its URL', () {
    final payload = codec.encodePayload(
      existing: const <String, Object?>{},
      profileId: 'work',
      runtimeTitle: 'Private Account',
    );

    expect(payload, isNot(contains(workspaceTabBrowserRuntimeTitlePayloadKey)));
  });
}

WorkspaceTabRecord _tab({Map<String, Object?> payload = const {}}) {
  return WorkspaceTabRecord(
    id: 'page-1',
    workspaceId: 'workspace-1',
    kind: .browser,
    title: 'New Tab',
    createdAt: .utc(2026),
    updatedAt: .utc(2026),
    payload: payload,
  );
}
