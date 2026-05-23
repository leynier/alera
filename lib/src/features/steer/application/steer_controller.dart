import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:alera/src/features/steer/domain/steer_rule.dart';
import 'package:alera/src/features/steer/domain/steer_state.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

class SteerController extends StateNotifier<SteerState> {
  SteerController({required this._preferencesStore})
    : super(const SteerState()) {
    _loadState();
  }

  final StringStore _preferencesStore;
  static const String _storageKey = 'steer_state';
  final _uuid = const Uuid();

  // Load persisted state from storage.
  Future<void> _loadState() async {
    try {
      final jsonStr = await _preferencesStore.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        state = SteerState.fromJson(json);
      }
    } catch (e) {
      // If loading fails, start with empty state.
      state = const SteerState();
    }
  }

  // Persist current state to storage.
  Future<void> _saveState() async {
    try {
      final jsonStr = jsonEncode(state.toJson());
      await _preferencesStore.setString(_storageKey, jsonStr);
    } catch (e) {
      // Silently fail if persistence fails.
    }
  }

  // Add a new steer rule.
  void addRule(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (state.isMaxRulesReached) {
      return;
    }
    // Check for duplicate labels (case-insensitive).
    final exists = state.rules.any(
      (r) => r.label.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    final maxOrder = state.rules.isEmpty
        ? 0
        : state.rules.map((r) => r.order).reduce(max);
    final newRule = SteerRule(
      id: _uuid.v4(),
      label: trimmed,
      active: true,
      createdAt: DateTime.now(),
      order: maxOrder + 1,
    );
    state = state.copyWith(rules: [...state.rules, newRule]);
    unawaited(_saveState());
  }

  // Remove a steer rule by id.
  void removeRule(String id) {
    final updated = state.rules
        .where((r) => r.id != id)
        .toList(growable: false);
    state = state.copyWith(rules: updated);
    unawaited(_saveState());
  }

  // Toggle a rule's active state.
  void toggleRule(String id) {
    final updated = state.rules
        .map((r) {
          if (r.id == id) {
            return r.copyWith(active: !r.active);
          }
          return r;
        })
        .toList(growable: false);
    state = state.copyWith(rules: updated);
    unawaited(_saveState());
  }

  // Update a rule's label.
  void updateRuleLabel(String id, String newLabel) {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) {
      return;
    }
    // Check for duplicate labels (excluding this rule).
    final exists = state.rules.any(
      (r) => r.id != id && r.label.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) {
      return;
    }
    final updated = state.rules
        .map((r) {
          if (r.id == id) {
            return r.copyWith(label: trimmed);
          }
          return r;
        })
        .toList(growable: false);
    state = state.copyWith(rules: updated);
    unawaited(_saveState());
  }

  // Reorder rules by moving a rule to a new position.
  void reorderRules(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.rules.length) {
      return;
    }
    if (newIndex < 0 || newIndex >= state.rules.length) {
      return;
    }
    if (oldIndex == newIndex) {
      return;
    }
    final sorted = state.sortedRules;
    final moved = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, moved);
    // Reassign order values.
    final updated = <SteerRule>[];
    for (var i = 0; i < sorted.length; i++) {
      updated.add(sorted[i].copyWith(order: i));
    }
    state = state.copyWith(rules: updated);
    unawaited(_saveState());
  }

  // Toggle the expanded state of the steer panel.
  void toggleExpanded() {
    state = state.copyWith(isExpanded: !state.isExpanded);
    unawaited(_saveState());
  }

  // Set the expanded state explicitly.
  void setExpanded(bool expanded) {
    if (state.isExpanded == expanded) {
      return;
    }
    state = state.copyWith(isExpanded: expanded);
    unawaited(_saveState());
  }

  // Get the context string for active steer rules to include in prompts.
  String? getSteerContext() {
    final active = state.activeRules;
    if (active.isEmpty) {
      return null;
    }
    final buffer = StringBuffer();
    buffer.writeln('<steer>');
    for (final rule in active) {
      buffer.writeln('- ${rule.label}');
    }
    buffer.write('</steer>');
    return buffer.toString();
  }

  // Clear all rules.
  void clearAllRules() {
    state = const SteerState();
    unawaited(_saveState());
  }

  // Reset to default rules.
  void resetToDefaults() {
    final defaults = <SteerRule>[
      SteerRule(
        id: _uuid.v4(),
        label: 'Be concise',
        active: true,
        createdAt: DateTime.now(),
        order: 0,
      ),
      SteerRule(
        id: _uuid.v4(),
        label: 'Prefer simple solutions',
        active: true,
        createdAt: DateTime.now(),
        order: 1,
      ),
    ];
    state = SteerState(rules: defaults, isExpanded: state.isExpanded);
    unawaited(_saveState());
  }
}
