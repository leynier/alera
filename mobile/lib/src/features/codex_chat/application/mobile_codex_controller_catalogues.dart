part of 'mobile_codex_controller.dart';

extension _MobileCodexControllerCatalogues on MobileCodexController {
  Future<void> _reloadMobileCodexCatalogue(String catalog) async {
    final client = _client;
    if (client == null || (catalog != 'skills' && catalog != 'apps')) return;
    final request = catalog == 'skills'
        ? 'codex.skills.list'
        : 'codex.apps.list';
    try {
      final payload = await client.codexRequest(request, <String, Object?>{
        'tabId': tabId,
      });
      final items = catalog == 'skills'
          ? _mobileSkillItems(payload)
          : _mobileAppItems(payload);
      _update(
        (current) => catalog == 'skills'
            ? current.copyWith(skills: items)
            : current.copyWith(apps: items),
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'Codex $catalog catalogue refresh was unavailable.',
        error,
        stackTrace,
      );
    }
  }

  Future<MobileCodexState> _loadCatalogues(
    MobileCodexClient client,
    MobileCodexState current,
  ) async {
    var next = current;
    try {
      final payload = await client.codexRequest('codex.model.list');
      final discovered = _modelItems(payload);
      final models = discovered.isEmpty
          ? const <MobileCodexModelOption>[
              MobileCodexModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
            ]
          : discovered;
      final selected = models.any((model) => model.id == next.selectedModel)
          ? next.selectedModel
          : null;
      next = next.copyWith(
        models: models,
        selectedModel:
            selected ??
            models.where((model) => model.isDefault).firstOrNull?.id ??
            models.first.id,
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'Codex model discovery was unavailable.',
        error,
        stackTrace,
      );
      next = next.copyWith(
        models: const <MobileCodexModelOption>[
          MobileCodexModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
        ],
        selectedModel: next.selectedModel ?? 'gpt-5.6-sol',
      );
    }
    final selectedOption = next.models
        .where((model) => model.id == next.selectedModel)
        .firstOrNull;
    final initialEffort = next.reasoningEffort;
    next = next.copyWith(
      reasoningEffort: _supportedEffort(selectedOption, initialEffort),
      speedMode: selectedOption?.supportsFastMode == false
          ? 'normal'
          : next.speedMode,
    );
    next = next.copyWith(
      collaborationModes: await _optionalItems(
        client,
        'codex.collaborationModes.list',
      ),
      skills: await _optionalItems(
        client,
        'codex.skills.list',
        includeTabId: true,
        decoder: _mobileSkillItems,
      ),
      apps: await _optionalItems(
        client,
        'codex.apps.list',
        includeTabId: true,
        decoder: _mobileAppItems,
      ),
    );
    return next;
  }

  Future<List<Map<String, Object?>>> _optionalItems(
    MobileCodexClient client,
    String request, {
    bool includeTabId = false,
    List<Map<String, Object?>> Function(Map<String, Object?>)? decoder,
  }) async {
    try {
      final payload = await client.codexRequest(
        request,
        includeTabId
            ? <String, Object?>{'tabId': tabId}
            : const <String, Object?>{},
      );
      return (decoder ?? _catalogueItems)(payload);
    } catch (error, stackTrace) {
      _logger.warning(
        'Optional Codex catalogue was unavailable.',
        error,
        stackTrace,
      );
      return const <Map<String, Object?>>[];
    }
  }

  List<Map<String, Object?>> _catalogueItems(Map<String, Object?> payload) {
    final value =
        payload['data'] ??
        payload['items'] ??
        payload['apps'] ??
        payload['skills'] ??
        payload['collaborationModes'] ??
        payload['modes'];
    return value is List
        ? <Map<String, Object?>>[
            for (final item in value)
              if (item is Map) Map<String, Object?>.from(item),
          ]
        : const <Map<String, Object?>>[];
  }

  List<Map<String, Object?>> _mobileSkillItems(Map<String, Object?> payload) {
    final entries = _catalogueItems(payload);
    final grouped = entries.any((entry) => entry['skills'] is List);
    if (!grouped) return entries;
    return <Map<String, Object?>>[
      for (final entry in entries)
        if (entry['skills'] is List)
          for (final skill in entry['skills'] as List)
            if (skill is Map && skill['enabled'] != false)
              <String, Object?>{
                ...Map<String, Object?>.from(skill),
                if (entry['cwd'] != null) 'cwd': entry['cwd'],
              },
    ];
  }

  List<Map<String, Object?>> _mobileAppItems(Map<String, Object?> payload) =>
      _catalogueItems(payload)
          .where(
            (app) => app['isAccessible'] != false && app['isEnabled'] != false,
          )
          .toList(growable: false);
}
