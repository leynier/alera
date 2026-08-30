import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/projects/domain/project_management_models.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const ProjectSetupScreen({
  super.key,
  required final String hostId,
  required final ProjectSummary project,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ProjectSetupScreen> createState() => _ProjectSetupScreenState();
}

class _ProjectSetupScreenState extends ConsumerState<ProjectSetupScreen> {
  final List<_CopyRuleDraft> _copyRules = <_CopyRuleDraft>[];
  final TextEditingController _commandsController = TextEditingController();
  final TextEditingController _promptAppendController = TextEditingController();
  String? _provider;
  String _origin = 'none';
  String? _loadError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final rule in _copyRules) {
      rule.dispose();
    }
    _commandsController.dispose();
    _promptAppendController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.hostId).future,
      );
      final effective = await client.effectiveProjectConfig(widget.project.id);
      if (!mounted) return;
      for (final rule in _copyRules) {
        rule.dispose();
      }
      _copyRules
        ..clear()
        ..addAll(effective.config.copyRules.map(_CopyRuleDraft.fromRule));
      _commandsController.text = effective.config.setupCommands.join('\n');
      _promptAppendController.text = effective.config.promptAppend;
      setState(() {
        _provider = effective.config.gitHostingProvider;
        _origin = effective.origin;
        _loadError = effective.error;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final config = _buildConfig();
    if (config == null) return;
    setState(() => _saving = true);
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.hostId).future,
      );
      await client.saveProjectConfig(widget.project.id, config);
      if (!mounted) return;
      setState(() {
        _origin = 'uiOverride';
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Project setup saved')));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error.toString());
    }
  }

  Future<void> _useRepoFile() async {
    setState(() => _saving = true);
    try {
      final client = await ref.read(
        hostConnectionControllerProvider(widget.hostId).future,
      );
      await client.useRepoProjectConfig(widget.project.id);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _loading = true;
      });
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error.toString());
    }
  }

  MobileProjectConfig? _buildConfig() {
    final rules = <ProjectConfigCopyRule>[];
    for (final draft in _copyRules) {
      final from = draft.from.text.trim();
      final to = draft.to.text.trim();
      if (!_isRelativeProjectPath(from) ||
          (to.isNotEmpty && !_isRelativeProjectPath(to))) {
        _showError('Copy paths must stay inside the project');
        return null;
      }
      rules.add(
        ProjectConfigCopyRule(
          from: from,
          to: to.isEmpty ? null : to,
          overwrite: draft.overwrite,
        ),
      );
    }
    return MobileProjectConfig(
      copyRules: rules,
      setupCommands: _commandsController.text
          .split('\n')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      promptAppend: _promptAppendController.text.trim(),
      gitHostingProvider: _provider,
    );
  }

  bool _isRelativeProjectPath(String value) {
    if (value.isEmpty || value.startsWith('/') || value.startsWith('\\')) {
      return false;
    }
    if (RegExp(r'^[A-Za-z]:').hasMatch(value)) return false;
    return !value.split(RegExp(r'[/\\]')).any((segment) => segment == '..');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project Setup')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: AleraTokens.pagePadding,
                children: <Widget>[
                  Text(
                    widget.project.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AleraTokens.spaceXs),
                  Text(
                    widget.project.repoPath,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: AleraTokens.monoFontFamily,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.spaceLg),
                  _SourceBadge(origin: _origin),
                  if (_loadError != null) ...<Widget>[
                    const SizedBox(height: AleraTokens.spaceMd),
                    Text(
                      _loadError!,
                      style: const TextStyle(color: AleraTokens.error),
                    ),
                  ],
                  const SizedBox(height: AleraTokens.spaceXl),
                  Text(
                    'Git Hosting Provider',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  DropdownButtonFormField<String?>(
                    initialValue: _provider,
                    items: const <DropdownMenuItem<String?>>[
                      DropdownMenuItem(value: null, child: Text('Auto')),
                      DropdownMenuItem(value: 'github', child: Text('GitHub')),
                      DropdownMenuItem(
                        value: 'azureDevops',
                        child: Text('Azure DevOps'),
                      ),
                      DropdownMenuItem(value: 'gitlab', child: Text('GitLab')),
                    ],
                    onChanged: (value) => setState(() => _provider = value),
                  ),
                  const SizedBox(height: AleraTokens.spaceXl),
                  Text(
                    'New Workspace Prompt Append',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  TextField(
                    controller: _promptAppendController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Add project-specific agent instructions',
                    ),
                  ),
                  const SizedBox(height: AleraTokens.spaceXl),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Copy Rules',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => _copyRules.add(.empty())),
                        icon: const Icon(Icons.add),
                        tooltip: 'Add Copy Rule',
                      ),
                    ],
                  ),
                  if (_copyRules.isEmpty)
                    const Text(
                      'No copy rules',
                      style: TextStyle(color: AleraTokens.foregroundMuted),
                    )
                  else
                    for (var index = 0; index < _copyRules.length; index++)
                      _CopyRuleEditor(
                        key: ObjectKey(_copyRules[index]),
                        draft: _copyRules[index],
                        onChanged: () => setState(() {}),
                        onRemove: () {
                          final removed = _copyRules.removeAt(index);
                          removed.dispose();
                          setState(() {});
                        },
                      ),
                  const SizedBox(height: AleraTokens.spaceXl),
                  Text(
                    'Setup Commands',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  TextField(
                    controller: _commandsController,
                    minLines: 4,
                    maxLines: 8,
                    style: const TextStyle(
                      fontFamily: AleraTokens.monoFontFamily,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'One command per line',
                    ),
                  ),
                  const SizedBox(height: AleraTokens.spaceXl),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Save Override'),
                  ),
                  const SizedBox(height: AleraTokens.spaceSm),
                  OutlinedButton(
                    onPressed: _saving ? null : _useRepoFile,
                    child: const Text('Use Repo File'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CopyRuleDraft({
  required final TextEditingController from,
  required final TextEditingController to,
  required var bool overwrite,
}) {
  factory empty() => _CopyRuleDraft(
    from: TextEditingController(),
    to: TextEditingController(),
    overwrite: false,
  );

  factory fromRule(ProjectConfigCopyRule rule) => _CopyRuleDraft(
    from: TextEditingController(text: rule.from),
    to: TextEditingController(text: rule.to),
    overwrite: rule.overwrite,
  );

  void dispose() {
    from.dispose();
    to.dispose();
  }
}

class const _CopyRuleEditor({
  super.key,
  required final _CopyRuleDraft draft,
  required final VoidCallback onChanged,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: AleraTokens.spaceSm),
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          children: <Widget>[
            TextField(
              controller: draft.from,
              decoration: const InputDecoration(labelText: 'Copy From'),
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            TextField(
              controller: draft.to,
              decoration: const InputDecoration(labelText: 'Copy To Optional'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Overwrite Existing'),
              value: draft.overwrite,
              onChanged: (value) {
                draft.overwrite = value;
                onChanged();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class const _SourceBadge({required final String origin})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final label = switch (origin) {
      'uiOverride' => 'Runtime override',
      'repoFile' => 'Repo file',
      _ => 'No configuration',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.surfaceVariant,
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.spaceMd,
            vertical: AleraTokens.spaceSm,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}
