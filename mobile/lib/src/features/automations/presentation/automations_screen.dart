import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_editor.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_detail_widgets.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_widgets.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class AutomationsScreen extends ConsumerStatefulWidget {
  const AutomationsScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _project = TextEditingController();
  final TextEditingController _profile = TextEditingController();
  final TextEditingController _tag = TextEditingController();
  String? _state;
  bool _includeTrashed = false;

  @override
  void dispose() {
    _search.dispose();
    _project.dispose();
    _profile.dispose();
    _tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final automations = ref.watch(
      mobileAutomationCatalogProvider(widget.host.id, _includeTrashed),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automations'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import',
            onPressed: () => unawaited(_import(context)),
            icon: const Icon(Icons.file_download),
          ),
          IconButton(
            tooltip: 'Export',
            onPressed: () => unawaited(_export()),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(context)),
        icon: const Icon(Icons.add),
        label: const Text('New Automation'),
      ),
      body: SafeArea(
        child: automations.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(error: error),
          data: (items) {
            final visible = items.where(_matches).toList(growable: false);
            return Column(
              children: <Widget>[
                Padding(
                  padding: AleraTokens.pagePadding,
                  child: Column(
                    children: <Widget>[
                      TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AleraTokens.spaceSm),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: _project,
                              decoration: const InputDecoration(
                                labelText: 'Project Id',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.spaceSm),
                          Expanded(
                            child: TextField(
                              controller: _profile,
                              decoration: const InputDecoration(
                                labelText: 'Profile Id',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.spaceSm),
                          Expanded(
                            child: TextField(
                              controller: _tag,
                              decoration: const InputDecoration(
                                labelText: 'Tag Id',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AleraTokens.spaceSm),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _state,
                              decoration: const InputDecoration(
                                labelText: 'State',
                              ),
                              items: const <DropdownMenuItem<String?>>[
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('All States'),
                                ),
                                DropdownMenuItem(
                                  value: 'draft',
                                  child: Text('Draft'),
                                ),
                                DropdownMenuItem(
                                  value: 'active',
                                  child: Text('Active'),
                                ),
                                DropdownMenuItem(
                                  value: 'paused',
                                  child: Text('Paused'),
                                ),
                                DropdownMenuItem(
                                  value: 'blocked',
                                  child: Text('Blocked'),
                                ),
                                DropdownMenuItem(
                                  value: 'trashed',
                                  child: Text('Trashed'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _state = value),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.spaceSm),
                          FilterChip(
                            label: const Text('Trash'),
                            selected: _includeTrashed,
                            onSelected: (value) =>
                                setState(() => _includeTrashed = value),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? const _EmptyState()
                      : ListView.separated(
                          padding: AleraTokens.pagePadding,
                          itemCount: visible.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AleraTokens.spaceSm),
                          itemBuilder: (context, index) => MobileAutomationCard(
                            clientFuture: ref.watch(
                              hostConnectionControllerProvider(
                                widget.host.id,
                              ).future,
                            ),
                            automation: visible[index],
                            onChanged: _refresh,
                            onOpen: () =>
                                unawaited(_showDetail(visible[index])),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _matches(MobileAutomation item) {
    final query = _search.text.trim().toLowerCase();
    final target = _nested(item.target, _firstKey(item.target));
    final profile = target?['agentProfileId']?.toString() ?? '';
    return (_state == null || item.state == _state) &&
        (_project.text.trim().isEmpty ||
            item.projectId == _project.text.trim()) &&
        (_profile.text.trim().isEmpty || profile == _profile.text.trim()) &&
        (_tag.text.trim().isEmpty || item.tagIds.contains(_tag.text.trim())) &&
        (query.isEmpty ||
            item.name.toLowerCase().contains(query) ||
            item.slug.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query));
  }

  MobileRuntimeAutomationRepository? _repository() {
    final connection = ref.read(
      hostConnectionControllerProvider(widget.host.id),
    );
    return connection.value == null
        ? null
        : MobileRuntimeAutomationRepository(connection.value!);
  }

  Future<void> _create(BuildContext context) async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final options = await loadMobileAutomationEditorOptions(client);
      if (!context.mounted) return;
      final definition = await showMobileAutomationEditor(
        context,
        options: options,
      );
      if (definition == null || !mounted) return;
      await MobileRuntimeAutomationRepository(client).upsert(definition);
      _refresh();
      _message('Automation created');
    } on Object catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _showDetail(MobileAutomation automation) async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.host.id).future,
      );
      final repository = MobileRuntimeAutomationRepository(client);
      final detail = await repository.show(automation.id);
      if (mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => MobileAutomationDetailSheet(
            detail: detail,
            repository: repository,
            client: client,
            onChanged: _refresh,
          ),
        );
      }
    } on Object catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _export() async {
    try {
      final bundle = await _repository()?.exportCatalog();
      if (bundle == null) return;
      await SharePlus.instance.share(ShareParams(text: jsonEncode(bundle)));
    } on Object catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _import(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final text = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Automations'),
          content: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 15,
            decoration: const InputDecoration(
              labelText: 'Versioned JSON Catalog',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (text == null || text.trim().isEmpty) return;
      final value = jsonDecode(text);
      if (value is! Map) {
        throw const FormatException('Catalog JSON must be an object.');
      }
      final bundle = <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      if (!context.mounted) return;
      final remap = await _askForRemap(context, bundle);
      if (remap == null) return;
      await _repository()?.importCatalog(<String, Object?>{...bundle}, remap);
      _refresh();
      _message('Automation catalog imported as drafts');
    } on Object catch (error) {
      _message(error.toString(), error: true);
    } finally {
      controller.dispose();
    }
  }

  Future<Map<String, String>?> _askForRemap(
    BuildContext context,
    Map<String, Object?> bundle,
  ) async {
    final keys = _portableKeys(bundle).toList()..sort();
    if (keys.isEmpty) return const <String, String>{};
    final controller = TextEditingController(
      text: jsonEncode(<String, String>{for (final key in keys) key: ''}),
    );
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Map Imported Targets'),
          content: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 15,
            decoration: const InputDecoration(
              labelText: 'Source Key To Local Id JSON',
              helperText: 'Every key must map to an existing local id.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final value = jsonDecode(controller.text);
                  if (value is! Map) throw const FormatException();
                  Navigator.pop(context, <String, String>{
                    for (final entry in value.entries)
                      if (entry.key is String && entry.value is String)
                        entry.key as String: (entry.value as String).trim(),
                  });
                } on FormatException {
                  _message('Remap must be a JSON object.', error: true);
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

  void _refresh() => ref.invalidate(
    mobileAutomationCatalogProvider(widget.host.id, _includeTrashed),
  );

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
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
      if (target is! Map) continue;
      for (final details in target.values.whereType<Map>()) {
        for (final key in <String>[
          'workspaceKey',
          'sourceWorkspaceKey',
          'tabKey',
          'profileKey',
          'conversationKey',
        ]) {
          final value = details[key];
          if (value is String && value.trim().isNotEmpty) result.add(value);
        }
      }
    }
  }
  final templates = bundle['templates'];
  if (templates is List) {
    for (final item in templates.whereType<Map>()) {
      final projectKey = item['projectKey'];
      if (projectKey is String && projectKey.trim().isNotEmpty) {
        result.add(projectKey.trim());
      }
    }
  }
  return result;
}

Map<String, Object?>? _nested(Map<String, Object?> map, String? key) {
  final value = key == null ? null : map[key];
  return value is Map
      ? <String, Object?>{
          for (final entry in value.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : null;
}

String? _firstKey(Map<String, Object?> map) =>
    map.isEmpty ? null : map.keys.first;

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: AleraTokens.pagePadding,
      child: Text('No automations are configured on this host.'),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.pagePadding,
      child: Text(
        error is UnsupportedError
            ? 'Update the runtime to manage automations from mobile.'
            : error.toString(),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
