import 'package:alera/src/features/steer/application/steer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../unit/_fakes.dart';

void main() {
  group('SteerController', () {
    late InMemoryStringStore store;

    setUp(() {
      store = InMemoryStringStore();
    });

    test('initializes with empty state when no persisted data', () {
      final controller = SteerController(preferencesStore: store);

      expect(controller.state.rules, isEmpty);
      expect(controller.state.isExpanded, isFalse);
      expect(controller.state.maxRules, 20);
    });

    test('adds a new rule', () {
      final controller = SteerController(preferencesStore: store);

      controller.addRule('Be concise');

      expect(controller.state.rules.length, 1);
      expect(controller.state.rules.first.label, 'Be concise');
      expect(controller.state.rules.first.active, isTrue);
    });

    test('does not add empty rule', () {
      final controller = SteerController(preferencesStore: store);

      controller.addRule('');
      controller.addRule('   ');

      expect(controller.state.rules, isEmpty);
    });

    test('does not add duplicate rule (case-insensitive)', () {
      final controller = SteerController(preferencesStore: store);

      controller.addRule('Be concise');
      controller.addRule('be concise');
      controller.addRule('BE CONCISE');

      expect(controller.state.rules.length, 1);
    });

    test('respects max rules limit', () {
      final controller = SteerController(preferencesStore: store);

      for (var i = 0; i < 25; i++) {
        controller.addRule('Rule $i');
      }

      expect(controller.state.rules.length, 20);
      expect(controller.state.isMaxRulesReached, isTrue);
    });

    test('toggles rule active state', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      final ruleId = controller.state.rules.first.id;

      expect(controller.state.rules.first.active, isTrue);

      controller.toggleRule(ruleId);

      expect(controller.state.rules.first.active, isFalse);

      controller.toggleRule(ruleId);

      expect(controller.state.rules.first.active, isTrue);
    });

    test('removes a rule', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      final ruleId = controller.state.rules.first.id;

      controller.removeRule(ruleId);

      expect(controller.state.rules, isEmpty);
    });

    test('updates rule label', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      final ruleId = controller.state.rules.first.id;

      controller.updateRuleLabel(ruleId, 'Be very concise');

      expect(controller.state.rules.first.label, 'Be very concise');
    });

    test('does not update to empty label', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      final ruleId = controller.state.rules.first.id;

      controller.updateRuleLabel(ruleId, '');

      expect(controller.state.rules.first.label, 'Be concise');
    });

    test('does not update to duplicate label', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      controller.addRule('Be helpful');
      final ruleId = controller.state.rules.first.id;

      controller.updateRuleLabel(ruleId, 'Be helpful');

      expect(controller.state.rules.first.label, 'Be concise');
    });

    test('reorders rules', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('First');
      controller.addRule('Second');
      controller.addRule('Third');

      final sortedRules = controller.state.sortedRules;
      expect(sortedRules[0].label, 'First');
      expect(sortedRules[1].label, 'Second');
      expect(sortedRules[2].label, 'Third');

      controller.reorderRules(0, 2);

      final reorderedRules = controller.state.sortedRules;
      expect(reorderedRules[0].label, 'Second');
      expect(reorderedRules[1].label, 'Third');
      expect(reorderedRules[2].label, 'First');
    });

    test('ignores invalid reorder indices', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('First');
      controller.addRule('Second');

      controller.reorderRules(-1, 1);
      controller.reorderRules(0, 5);
      controller.reorderRules(0, 0);

      expect(controller.state.sortedRules[0].label, 'First');
      expect(controller.state.sortedRules[1].label, 'Second');
    });

    test('toggles expanded state', () {
      final controller = SteerController(preferencesStore: store);

      expect(controller.state.isExpanded, isFalse);

      controller.toggleExpanded();

      expect(controller.state.isExpanded, isTrue);

      controller.toggleExpanded();

      expect(controller.state.isExpanded, isFalse);
    });

    test('sets expanded state explicitly', () {
      final controller = SteerController(preferencesStore: store);

      controller.setExpanded(true);

      expect(controller.state.isExpanded, isTrue);

      controller.setExpanded(true); // no change

      expect(controller.state.isExpanded, isTrue);

      controller.setExpanded(false);

      expect(controller.state.isExpanded, isFalse);
    });

    test('returns active rules only', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Active Rule');
      controller.addRule('Inactive Rule');
      final inactiveId = controller.state.rules[1].id;
      controller.toggleRule(inactiveId);

      final activeRules = controller.state.activeRules;

      expect(activeRules.length, 1);
      expect(activeRules.first.label, 'Active Rule');
    });

    test('returns steer context when active rules exist', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      controller.addRule('Be helpful');

      final context = controller.getSteerContext();

      expect(context, isNotNull);
      expect(context, contains('<steer>'));
      expect(context, contains('- Be concise'));
      expect(context, contains('- Be helpful'));
      expect(context, contains('</steer>'));
    });

    test('returns null steer context when no active rules', () {
      final controller = SteerController(preferencesStore: store);

      final context = controller.getSteerContext();

      expect(context, isNull);
    });

    test('returns null steer context when all rules are inactive', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Be concise');
      final ruleId = controller.state.rules.first.id;
      controller.toggleRule(ruleId);

      final context = controller.getSteerContext();

      expect(context, isNull);
    });

    test('clears all rules', () {
      final controller = SteerController(preferencesStore: store);
      controller.addRule('Rule 1');
      controller.addRule('Rule 2');
      controller.toggleExpanded();

      controller.clearAllRules();

      expect(controller.state.rules, isEmpty);
      expect(controller.state.isExpanded, isFalse); // also reset
    });

    test('resets to default rules', () {
      final controller = SteerController(preferencesStore: store);

      controller.resetToDefaults();

      expect(controller.state.rules.length, 2);
      expect(controller.state.rules[0].label, 'Be concise');
      expect(controller.state.rules[1].label, 'Prefer simple solutions');
    });

    test('persists and loads state', () async {
      var controller = SteerController(preferencesStore: store);
      controller.addRule('Persisted Rule');
      controller.toggleExpanded();

      // Allow async save to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // Create new controller with same store
      controller = SteerController(preferencesStore: store);

      // Allow async load to complete
      await Future.delayed(const Duration(milliseconds: 50));

      expect(controller.state.rules.length, 1);
      expect(controller.state.rules.first.label, 'Persisted Rule');
      expect(controller.state.isExpanded, isTrue);
    });
  });
}
