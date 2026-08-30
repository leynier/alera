import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_catalog_selection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rebasing removes the identity of the edited duplicate token', () {
    final skill = mobileCodexTrackCatalogSelection(const <String, Object?>{
      'type': 'skill',
      'name': 'shared',
      'path': '/skills/shared',
    }, tokenStart: 0);
    final app = mobileCodexTrackCatalogSelection(const <String, Object?>{
      'type': 'mention',
      'name': 'shared',
      'path': 'app://shared',
    }, tokenStart: 8);

    final rebased = mobileCodexRebaseCatalogSelections(
      const TextEditingValue(
        text: r'$shared $shared',
        selection: TextSelection(baseOffset: 0, extentOffset: 8),
      ),
      const TextEditingValue(
        text: r'$shared',
        selection: .collapsed(offset: 0),
      ),
      <Map<String, Object?>>[skill, app],
    );

    expect(rebased, hasLength(1));
    expect(
      mobileCodexCatalogWireSelection(rebased.single),
      const <String, Object?>{
        'type': 'mention',
        'name': 'shared',
        'path': 'app://shared',
      },
    );
  });

  test('trimming keeps tracked catalog token positions aligned', () {
    final selection = mobileCodexTrackCatalogSelection(const <String, Object?>{
      'type': 'skill',
      'name': 'review',
      'path': '/skills/review',
    }, tokenStart: 2);

    final trimmed = mobileCodexTrimCatalogSelections(
      '  \$review  ',
      <Map<String, Object?>>[selection],
    );

    expect(trimmed, hasLength(1));
    expect(
      mobileCodexCatalogWireSelection(trimmed.single),
      const <String, Object?>{
        'type': 'skill',
        'name': 'review',
        'path': '/skills/review',
      },
    );
  });
}
