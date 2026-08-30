import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:flutter/material.dart';

Future<void> showWorkspaceSectionDialog(
  BuildContext context,
  WorkbenchController controller,
  Workspace workspace,
) => showDialog<void>(
  context: context,
  builder: (_) => _SectionDialog(controller: controller, workspace: workspace),
);

class _SectionDialog extends StatefulWidget {
  const _SectionDialog({required this.controller, required this.workspace});
  final WorkbenchController controller;
  final Workspace workspace;
  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  final _name = TextEditingController();
  List<WorkspaceSection> _sections = [];
  String? _selected;
  bool _create = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = widget.workspace.sectionId;
    _load();
  }

  Future<void> _load() async {
    try {
      final sections = await widget.controller.listWorkspaceSections();
      if (!mounted) return;
      setState(() {
        _sections = sections;
        if (!sections.any((section) => section.id == _selected)) {
          _selected = null;
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_create &&
        (name.isEmpty ||
            name.toLowerCase() == 'others' ||
            _sections.any(
              (section) => section.name.toLowerCase() == name.toLowerCase(),
            ))) {
      setState(() => _error = 'Enter a unique section name other than Others.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveWorkspaceSection(
        widget.workspace.id,
        sectionId: _selected,
        newName: _create ? name : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
      await _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Set Section',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space16),
              if (_loading)
                const LinearProgressIndicator()
              else ...[
                AleraDropdownField<String?>(
                  value: _create ? '__new__' : _selected,
                  labelText: 'Section',
                  filterable: true,
                  filterHintText: 'Search Sections',
                  entries: [
                    const AleraDropdownFieldEntry(
                      value: null,
                      label: 'No Section',
                    ),
                    for (final section in _sections)
                      AleraDropdownFieldEntry(
                        value: section.id,
                        label: section.name,
                      ),
                    const AleraDropdownFieldEntry(
                      value: '__new__',
                      label: 'New Section',
                    ),
                  ],
                  enabled: !_saving,
                  onChanged: (value) => setState(() {
                    _create = value == '__new__';
                    _selected = _create ? null : value;
                    _error = null;
                  }),
                ),
                if (_create) ...[
                  const SizedBox(height: AleraTokens.space12),
                  AleraTextField(
                    controller: _name,
                    labelText: 'Section Name',
                    enabled: !_saving,
                  ),
                ],
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: AleraTokens.space20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    onPressed: _saving || _loading ? null : _save,
                    child: Text(_saving ? 'Saving...' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
