import 'package:alera_agent_chat/alera_agent_chat.dart';

/// Where one row of the Models list came from.
enum AgentProviderModelSource(final String label) {
  discovered('Discovered'),
  configured('Configured'),
  custom('Custom'),
  providerDefault('Provider Default'),
}

class const AgentProviderModelRow({
  required final String? id,
  required final String label,
  required final AgentProviderModelSource source,
  final bool hidden = false,
  final bool favorite = false,
  final bool isDefault = false,
}) {
  /// The provider default stays in the picker: hiding it would leave a chat
  /// with nothing to fall back to.
  bool get canHide => id != null;
}

class const AgentProviderModelList({
  required final List<AgentProviderModelRow> rows,
  required final int total,
  required final int hiddenCount,
}) {
  int get visibleCount => total - hiddenCount;

  /// The ends of the stored order. Only identified rows can move, so the
  /// provider default never counts as a neighbour: the last model above it
  /// is still the last one Move Down can reach.
  String? get firstMovableId =>
      rows.where((row) => row.id != null).firstOrNull?.id;

  String? get lastMovableId =>
      rows.where((row) => row.id != null).lastOrNull?.id;
}

/// Every model the instance offers in picker order, with this host's
/// visibility and favorites applied. [customModels] are the draft's ids, so a
/// model added but not yet saved shows up at once. [query] filters rows but
/// never the counts. [defaultModel] is the instance's own default from its
/// launch definition, never the person's default selection; when it is null
/// the provider default row is the one marked default.
AgentProviderModelList agentProviderModelRows({
  required AgentChatProviderInstance? instance,
  required List<String> customModels,
  required AgentChatPreferences preferences,
  required String providerInstanceId,
  String? defaultModel,
  String query = '',
}) {
  final modelPreferences =
      preferences.models[providerInstanceId] ??
      const AgentChatModelPreferences();
  final hidden = modelPreferences.hidden.toSet();
  final favorites = <String?>{
    for (final favorite in preferences.favorites)
      if (favorite.providerInstanceId == providerInstanceId) favorite.model,
  };
  AgentProviderModelSource catalogSource(AgentChatModelOption model) =>
      switch (model.source ?? instance?.modelsSource) {
        AgentChatModelsSource.discovered ||
        AgentChatModelsSource.discoveredAndConfigured =>
          AgentProviderModelSource.discovered,
        _ => AgentProviderModelSource.configured,
      };
  final custom = customModels.toSet();
  final candidates = <AgentProviderModelRow>[];
  final seen = <String?>{};
  void add(String? id, String label, AgentProviderModelSource source) {
    if (!seen.add(id)) {
      return;
    }
    candidates.add(
      AgentProviderModelRow(
        id: id,
        label: label,
        source: source,
        hidden: id != null && hidden.contains(id),
        favorite: favorites.contains(id),
        isDefault: id == defaultModel,
      ),
    );
  }

  for (final model in instance?.models ?? const <AgentChatModelOption>[]) {
    final source = model.id == null
        ? AgentProviderModelSource.providerDefault
        : custom.contains(model.id)
        ? AgentProviderModelSource.custom
        : catalogSource(model);
    add(model.id, model.label, source);
  }
  add(null, 'Provider Default', AgentProviderModelSource.providerDefault);
  for (final id in customModels) {
    add(id, id, AgentProviderModelSource.custom);
  }

  final ranks = <String, int>{
    for (var i = 0; i < modelPreferences.order.length; i++)
      modelPreferences.order[i]: i,
  };
  final original = <String?, int>{
    for (var i = 0; i < candidates.length; i++) candidates[i].id: i,
  };
  int rank(AgentProviderModelRow row) {
    final id = row.id;
    final explicit = id == null ? null : ranks[id];
    return explicit ?? ranks.length + original[id]!;
  }

  candidates.sort((left, right) => rank(left).compareTo(rank(right)));
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
  final rows = <AgentProviderModelRow>[
    for (final row in candidates)
      if (terms.every('${row.label} ${row.id ?? ''}'.toLowerCase().contains))
        row,
  ];
  return AgentProviderModelList(
    rows: List.unmodifiableOf(rows),
    total: candidates.length,
    hiddenCount: candidates.where((row) => row.hidden).length,
  );
}

/// How a default that names no model reads: it starts with the instance's
/// own default when [instanceDefault] is set, else with the provider's.
String agentProviderUnsetModelLabel(
  List<AgentProviderModelRow> rows,
  String? instanceDefault,
) {
  if (instanceDefault == null) {
    return 'Provider Default';
  }
  final label =
      rows.where((row) => row.id == instanceDefault).firstOrNull?.label ??
      instanceDefault;
  return 'Instance Default ($label)';
}

/// [current] with [id] shown or hidden. The provider default is never hidden.
AgentChatModelPreferences agentProviderSetModelHidden(
  AgentChatModelPreferences current,
  String id, {
  required bool hidden,
}) {
  final next = <String>[
    for (final value in current.hidden)
      if (value != id) value,
    if (hidden) id,
  ];
  return AgentChatModelPreferences(hidden: next, order: current.order);
}

/// The explicit order after moving [id] by [delta] within [displayed], the
/// ids in the order the list currently shows them. The provider default has
/// no id to store, so it keeps its natural place.
AgentChatModelPreferences agentProviderMoveModel(
  AgentChatModelPreferences current,
  List<String?> displayed,
  String id,
  int delta,
) {
  final ids = <String>[for (final value in displayed) ?value];
  final index = ids.indexOf(id);
  if (index < 0) {
    return current;
  }
  final target = (index + delta).clamp(0, ids.length - 1);
  if (target == index) {
    return current;
  }
  ids
    ..removeAt(index)
    ..insert(target, id);
  return AgentChatModelPreferences(hidden: current.hidden, order: ids);
}

/// [favorites] with this instance's [model] added or removed.
List<AgentChatSelection> agentProviderSetFavorite(
  List<AgentChatSelection> favorites, {
  required String providerInstanceId,
  required String? model,
  required bool favorite,
}) {
  final next = <AgentChatSelection>[
    for (final entry in favorites)
      if (entry.providerInstanceId != providerInstanceId ||
          entry.model != model)
        entry,
  ];
  if (favorite) {
    next.add(
      AgentChatSelection(providerInstanceId: providerInstanceId, model: model),
    );
  }
  return next;
}
