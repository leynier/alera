import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:uuid/uuid.dart';

/// Pure list operations used by Settings and covered independently of Flutter.
abstract final class TextActionsMutations {
  static TextActionsSettings update(
    TextActionsSettings settings,
    TextAction action,
  ) {
    final index = settings.actions.indexWhere(
      (candidate) => candidate.id == action.id,
    );
    if (index < 0) {
      return settings;
    }
    final actions = <TextAction>[...settings.actions]..[index] = action;
    return settings.copyWith(actions: actions);
  }

  static TextActionsSettings append(
    TextActionsSettings settings,
    TextAction action,
  ) {
    return settings.copyWith(
      actions: <TextAction>[...settings.actions, action],
    );
  }

  static TextActionsSettings delete(
    TextActionsSettings settings,
    String actionId,
  ) {
    return settings.copyWith(
      actions: settings.actions
          .where((action) => action.id != actionId)
          .toList(growable: false),
    );
  }

  static TextActionsSettings reorder(
    TextActionsSettings settings,
    int oldIndex,
    int newIndex,
  ) {
    final actions = <TextAction>[...settings.actions];
    if (oldIndex < 0 || oldIndex >= actions.length) {
      return settings;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0) {
      return settings;
    }
    if (newIndex > actions.length) {
      newIndex = actions.length;
    }
    final action = actions.removeAt(oldIndex);
    final insertionIndex = newIndex.clamp(0, actions.length).toInt();
    actions.insert(insertionIndex, action);
    return settings.copyWith(actions: actions);
  }

  static TextActionsSettings duplicate(
    TextActionsSettings settings,
    TextAction source, {
    Uuid uuid = const Uuid(),
  }) {
    final sourceIndex = settings.actions.indexWhere(
      (action) => action.id == source.id,
    );
    if (sourceIndex < 0) {
      return settings;
    }
    final clone = TextAction(
      id: uuid.v4(),
      name: uniqueCopyName(source.name, settings.actions),
      prompt: source.prompt,
      enabled: source.enabled,
      agentOverride: source.agentOverride,
      modelOverride: source.modelOverride,
      reasoningByModel: <String, String>{...source.reasoningByModel},
    );
    final actions = <TextAction>[...settings.actions]
      ..insert(sourceIndex + 1, clone);
    return settings.copyWith(actions: actions);
  }

  static String uniqueCopyName(
    String sourceName,
    Iterable<TextAction> actions,
  ) {
    final names = <String>{
      for (final action in actions) action.name.trim().toLowerCase(),
    };
    final base = '${sourceName.trim()} Copy';
    if (names.add(base.toLowerCase())) {
      return base;
    }
    var suffix = 2;
    while (!names.add('$base $suffix'.toLowerCase())) {
      suffix += 1;
    }
    return '$base $suffix';
  }
}
