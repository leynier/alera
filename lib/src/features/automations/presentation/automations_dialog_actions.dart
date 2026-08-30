part of 'automations_dialog.dart';

extension on _AutomationsDialogState {
  Future<void> _createAutomation() async {
    final definition = await showAutomationEditorDialog(context);
    if (definition == null || !mounted) {
      return;
    }
    await _save(definition, 'Automation created');
  }

  Future<void> _edit(AutomationRecord automation) async {
    final definition = await showAutomationEditorDialog(
      context,
      initial: automation,
    );
    if (definition == null || !mounted) {
      return;
    }
    await _save(definition, 'Automation saved');
  }

  Future<void> _clone(AutomationRecord automation) async {
    final raw = <String, Object?>{
      ...automation.raw,
      'id': const Uuid().v4(),
      'slug': '${automation.slug}-copy',
      'name': '${automation.name} Copy',
      'state': 'draft',
      'revision': 0,
      'approvedRevision': null,
    };
    final definition = await showAutomationEditorDialog(
      context,
      initial: .fromJson(raw),
    );
    if (definition != null && mounted) {
      await _save(definition, 'Automation cloned');
    }
  }

  Future<void> _exportCatalog() async {
    try {
      final bundle = await ref
          .read(automationRepositoryProvider)
          .exportCatalog();
      await Clipboard.setData(ClipboardData(text: jsonEncode(bundle)));
      _showMessage('Automation catalog copied to clipboard');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _importCatalog() async {
    final controller = TextEditingController();
    try {
      final imported = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import Automations'),
          content: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Versioned JSON Catalog',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (imported == null || imported.trim().isEmpty || !mounted) {
        return;
      }
      final bundle = jsonDecode(imported);
      if (bundle is! Map) {
        throw const FormatException('Catalog JSON must be an object.');
      }
      final bundleMap = <String, Object?>{
        for (final entry in bundle.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      final remap = await _askForRemap(bundleMap);
      if (remap == null || !mounted) {
        return;
      }
      await ref
          .read(automationRepositoryProvider)
          .importCatalog(bundleMap, remap);
      ref.invalidate(automationCatalogProvider(_includeTrashed));
      _showMessage('Automation catalog imported as drafts');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _save(JsonMap definition, String message) async {
    try {
      final saved = await ref
          .read(automationRepositoryProvider)
          .upsert(definition);
      if (!mounted) {
        return;
      }
      // ignore: invalid_use_of_protected_member
      setState(() {
        _selectedId = saved.id;
        _detailFuture = ref.read(automationRepositoryProvider).show(saved.id);
      });
      ref.invalidate(automationListProvider);
      _showMessage(message);
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _approve(AutomationRecord automation) async {
    try {
      await ref
          .read(automationRepositoryProvider)
          .approve(automation.id, automation.revision);
      await _refresh(automation.id);
      ref.invalidate(automationListProvider);
      _showMessage('Automation approved');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _runNow(AutomationRecord automation) async {
    try {
      final choice = await showDialog<(bool, String, bool, bool)>(
        context: context,
        builder: (context) => const AutomationRunNowChoiceDialog(),
      );
      if (choice == null || !mounted) {
        return;
      }
      await ref
          .read(automationRepositoryProvider)
          .runNow(
            automation.id,
            runPrecheck: choice.$1,
            overlap: choice.$2,
            draftTest: choice.$3,
            revision: choice.$4 ? automation.revision : null,
          );
      await _refresh(automation.id);
      _showMessage('Automation run started');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _setState(String request, String id) async {
    try {
      final activeRuns = request == 'automation.pause'
          ? await showDialog<String>(
              context: context,
              builder: (context) => const AutomationPauseChoiceDialog(),
            )
          : null;
      if (request == 'automation.pause' && activeRuns == null) {
        return;
      }
      await ref
          .read(automationRepositoryProvider)
          .setState(request, id, activeRuns: activeRuns);
      await _refresh(id);
      ref.invalidate(automationListProvider);
      _showMessage(
        request == 'automation.pause'
            ? 'Automation paused'
            : 'Automation resumed',
      );
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _cancelRun(AutomationRunRecord run, String automationId) async {
    try {
      await ref
          .read(automationRepositoryProvider)
          .cancel(run.id, run.targetIdentity);
      await _refresh(automationId);
      _showMessage('Automation cancellation requested');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _resumeWaiting(
    AutomationRunRecord run,
    String automationId,
  ) async {
    try {
      await ref
          .read(automationRepositoryProvider)
          .setWaiting(run.id, run.targetIdentity, waiting: false);
      await _refresh(automationId);
      _showMessage('Waiting run resumed');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _extendWaiting(
    AutomationRunRecord run,
    String automationId,
  ) async {
    try {
      await ref
          .read(automationRepositoryProvider)
          .extendWaiting(run.id, run.targetIdentity);
      await _refresh(automationId);
      _showMessage('Waiting run extended');
    } catch (error) {
      _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _refresh(String id) async {
    if (!mounted) {
      return;
    }
    // ignore: invalid_use_of_protected_member
    setState(() {
      _selectedId = id;
      _detailFuture = ref.read(automationRepositoryProvider).show(id);
    });
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error
            ? AleraTokens.error
            : AleraTokens.surfaceElevated,
        content: Text(message),
      ),
    );
  }

  Future<Map<String, String>?> _askForRemap(Map<String, Object?> bundle) async {
    final keys = _portableKeys(bundle).toList()..sort();
    if (keys.isEmpty) {
      return const <String, String>{};
    }
    final controller = TextEditingController(
      text: jsonEncode(<String, String>{for (final key in keys) key: ''}),
    );
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Map Imported Targets'),
          content: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              labelText: 'Source Key To Local Id JSON',
              helperText: 'Map every source key to an existing local id.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final value = jsonDecode(controller.text);
                  if (value is! Map) {
                    throw const FormatException('Remap must be an object.');
                  }
                  Navigator.of(dialogContext).pop(<String, String>{
                    for (final entry in value.entries)
                      if (entry.key is String && entry.value is String)
                        entry.key as String: (entry.value as String).trim(),
                  });
                } on FormatException catch (error) {
                  _showMessage(error.message, error: true);
                }
              },
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

Set<String> _portableKeys(Map<String, Object?> bundle) {
  final result = <String>{};
  final definitions = bundle['definitions'];
  if (definitions is List) {
    for (final item in definitions.whereType<Map>()) {
      final definition = <String, Object?>{
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (definition['projectKey'] is String) {
        result.add(definition['projectKey']! as String);
      }
      final target = definition['target'];
      if (target is! Map) {
        continue;
      }
      for (final details in target.values.whereType<Map>()) {
        for (final key in <String>[
          'workspaceKey',
          'sourceWorkspaceKey',
          'tabKey',
          'profileKey',
          'conversationKey',
        ]) {
          final value = details[key];
          if (value is String && value.trim().isNotEmpty) {
            result.add(value);
          }
        }
      }
    }
  }
  final templates = bundle['templates'];
  if (templates is List) {
    for (final item in templates.whereType<Map>()) {
      for (final key in <String>['projectKey']) {
        final value = item[key];
        if (value is String && value.trim().isNotEmpty) {
          result.add(value.trim());
        }
      }
    }
  }
  return result;
}
