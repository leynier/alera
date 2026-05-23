import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/sidebar_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SidebarPrefs', () {
    test('defaults align with AleraTokens', () {
      expect(SidebarPrefs.defaults.pinnedChatIds, isEmpty);
      expect(SidebarPrefs.defaults.pinnedChatOrder, isEmpty);
      expect(SidebarPrefs.defaults.collapsed, isFalse);
      expect(SidebarPrefs.defaults.width, AleraTokens.sidebarDefaultWidth);
    });

    test('round-trips through json', () {
      const prefs = SidebarPrefs(
        pinnedChatIds: <String>{'a', 'b'},
        pinnedChatOrder: <String>['b', 'a'],
        collapsed: true,
        width: 300,
      );
      final restored = SidebarPrefs.fromJson(prefs.toJson());
      expect(restored.pinnedChatIds, prefs.pinnedChatIds);
      expect(restored.pinnedChatOrder, prefs.pinnedChatOrder);
      expect(restored.collapsed, isTrue);
      expect(restored.width, 300);
    });

    test('fromJson clamps width into [min, max]', () {
      final tooNarrow = SidebarPrefs.fromJson(<String, Object?>{
        'pinnedChatIds': <String>[],
        'pinnedChatOrder': <String>[],
        'collapsed': false,
        'width': 10.0,
      });
      expect(tooNarrow.width, AleraTokens.sidebarMinWidth);
      final tooWide = SidebarPrefs.fromJson(<String, Object?>{
        'pinnedChatIds': <String>[],
        'pinnedChatOrder': <String>[],
        'collapsed': false,
        'width': 9999.0,
      });
      expect(tooWide.width, AleraTokens.sidebarMaxWidth);
    });

    test('fromJson appends pinned ids missing from order list', () {
      final prefs = SidebarPrefs.fromJson(<String, Object?>{
        'pinnedChatIds': <String>['a', 'b', 'c'],
        'pinnedChatOrder': <String>['c'],
        'collapsed': false,
        'width': 280.0,
      });
      expect(prefs.pinnedChatIds, <String>{'a', 'b', 'c'});
      // Stored order keeps the persisted prefix, then appends missing ids.
      expect(prefs.pinnedChatOrder.first, 'c');
      expect(prefs.pinnedChatOrder.toSet(), <String>{'a', 'b', 'c'});
    });

    test('fromJson drops orphan order entries', () {
      final prefs = SidebarPrefs.fromJson(<String, Object?>{
        'pinnedChatIds': <String>['a'],
        'pinnedChatOrder': <String>['ghost', 'a'],
        'collapsed': false,
        'width': 280.0,
      });
      expect(prefs.pinnedChatOrder, <String>['a']);
    });

    test('fromJson falls back to defaults on malformed input', () {
      final prefs = SidebarPrefs.fromJson(<String, Object?>{});
      expect(prefs.pinnedChatIds, isEmpty);
      expect(prefs.collapsed, isFalse);
      expect(prefs.width, AleraTokens.sidebarDefaultWidth);
    });
  });
}
