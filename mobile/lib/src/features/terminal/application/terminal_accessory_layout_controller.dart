import 'package:alera_mobile/src/features/terminal/application/accessory_layout_repository.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_shortcut_builder.dart';
import 'package:alera_mobile/src/features/terminal/infra/local_accessory_layout_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_accessory_layout_controller.g.dart';

@Riverpod(keepAlive: true)
AccessoryLayoutRepository accessoryLayoutRepository(Ref ref) {
  return LocalAccessoryLayoutRepository();
}

/// The accessory bar configuration, global across hosts and tabs.
@Riverpod(keepAlive: true)
class TerminalAccessoryLayoutController
    extends _$TerminalAccessoryLayoutController {
  @override
  Future<TerminalAccessoryLayout> build() {
    return ref.watch(accessoryLayoutRepositoryProvider).load();
  }

  Future<void> setKeyVisible(String id, bool visible) {
    return _update((layout) {
      final hidden = <String>{...layout.hiddenIds};
      if (visible) {
        hidden.remove(id);
      } else {
        hidden.add(id);
      }
      return layout.copyWith(hiddenIds: hidden);
    });
  }

  /// [toIndex] is the position after removal (the `onReorderItem` contract).
  Future<void> moveKey(int fromIndex, int toIndex) {
    return _update((layout) {
      final ordered = <String>[for (final key in layout.orderedKeys()) key.id];
      if (fromIndex < 0 || fromIndex >= ordered.length) {
        return layout;
      }
      final id = ordered.removeAt(fromIndex);
      ordered.insert(toIndex.clamp(0, ordered.length), id);
      return layout.copyWith(orderedIds: ordered);
    });
  }

  Future<void> addCustomKey({
    required String key,
    required Set<TerminalShortcutModifier> modifiers,
  }) {
    return _update((layout) {
      final custom = TerminalCustomKey(
        id: 'custom-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        key: key,
        modifiers: modifiers,
      );
      if (custom.build() == null) {
        return layout;
      }
      return layout.copyWith(
        orderedIds: <String>[...layout.orderedIds, custom.id],
        customKeys: <TerminalCustomKey>[...layout.customKeys, custom],
      );
    });
  }

  Future<void> removeCustomKey(String id) {
    return _update(
      (layout) => layout.copyWith(
        orderedIds: <String>[
          for (final orderedId in layout.orderedIds)
            if (orderedId != id) orderedId,
        ],
        hiddenIds: <String>{...layout.hiddenIds}..remove(id),
        customKeys: <TerminalCustomKey>[
          for (final custom in layout.customKeys)
            if (custom.id != id) custom,
        ],
      ),
    );
  }

  Future<void> resetToDefaults() {
    return _update((_) => TerminalAccessoryLayout.defaults());
  }

  Future<void> _update(
    TerminalAccessoryLayout Function(TerminalAccessoryLayout) transform,
  ) async {
    final current = await future;
    final next = transform(current);
    state = AsyncData(next);
    await ref.read(accessoryLayoutRepositoryProvider).save(next);
  }
}
