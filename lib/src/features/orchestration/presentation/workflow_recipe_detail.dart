import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';

class WorkflowRecipeDetail extends StatelessWidget {
  const WorkflowRecipeDetail({
    super.key,
    required this.record,
    required this.document,
    required this.filename,
    required this.editing,
    required this.exporting,
    required this.busy,
    required this.preview,
    required this.onEdit,
    required this.onCopy,
    required this.onValidate,
    required this.onSave,
    required this.onCancel,
    required this.onExport,
    required this.onPreview,
    required this.onApply,
    required this.onFilenameChanged,
    required this.onOpen,
  });

  final Map<String, Object?> record;
  final TextEditingController document;
  final TextEditingController filename;
  final bool editing;
  final bool exporting;
  final bool busy;
  final Map<String, Object?>? preview;
  final VoidCallback onEdit, onCopy, onValidate, onSave, onCancel;
  final VoidCallback? onExport, onPreview, onApply, onOpen;
  final ValueChanged<String> onFilenameChanged;

  @override
  Widget build(BuildContext context) {
    final recipe = _map(record['recipe']);
    final source = _map(record['source']);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            recipe['name'] as String? ?? 'Invalid Recipe',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(
            recipe['description'] as String? ??
                record['error'] as String? ??
                '',
          ),
          const SizedBox(height: AleraTokens.space8),
          Text(switch (source['origin']) {
            'personal' =>
              'Personal · Recipe Revision ${recipe['revision']} · Catalog Revision ${record['catalogRevision']}',
            'project' => 'Project · ${source['path']}',
            _ => 'Built-in · Recipe Revision ${recipe['revision']}',
          }, style: theme.textTheme.bodySmall),
          const SizedBox(height: AleraTokens.space16),
          if (!editing && !exporting)
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: [
                if (recipe.isNotEmpty && source['origin'] == 'personal')
                  FilledButton(
                    onPressed: busy ? null : onEdit,
                    child: const Text('Edit Personal'),
                  ),
                if (recipe.isNotEmpty)
                  OutlinedButton(
                    onPressed: busy ? null : onCopy,
                    child: const Text('Copy To Personal'),
                  ),
                if (onOpen != null)
                  OutlinedButton(
                    onPressed: busy ? null : onOpen,
                    child: const Text('Open File'),
                  ),
                if (recipe.isNotEmpty)
                  OutlinedButton(
                    onPressed: busy ? null : onExport,
                    child: const Text('Export To Project'),
                  ),
              ],
            ),
          if (editing) ...[
            const Text(
              'Edit the portable recipe and its included contracts. Save validates every role, schema and stage.',
            ),
            const SizedBox(height: AleraTokens.space12),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: [
                FilledButton(
                  onPressed: busy ? null : onSave,
                  child: const Text('Save Personal'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onValidate,
                  child: const Text('Validate'),
                ),
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('Discard Edit'),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            TextField(
              controller: document,
              readOnly: busy,
              minLines: 12,
              maxLines: 24,
              style: AleraTokens.monoStyle,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Recipe And Role Contracts',
              ),
            ),
          ] else if (exporting) ...[
            const Text(
              'Review the destination and changes before writing. Export includes portable contracts and does not include Agent Profile commands or credentials.',
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: filename,
              labelText: 'Filename',
              readOnly: busy,
              onChanged: onFilenameChanged,
            ),
            const SizedBox(height: AleraTokens.space12),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onPreview,
                  child: const Text('Review Export'),
                ),
                if (preview != null)
                  FilledButton(
                    onPressed: busy ? null : onApply,
                    child: const Text('Confirm Export'),
                  ),
                TextButton(
                  onPressed: busy ? null : onCancel,
                  child: const Text('Cancel Export'),
                ),
              ],
            ),
            if (preview != null) ...[
              const SizedBox(height: AleraTokens.space16),
              SelectableText(
                preview!['path']! as String,
                style: AleraTokens.monoStyle,
              ),
              Text(
                preview!['before'] == null
                    ? 'New file'
                    : 'Replace existing file after review',
              ),
              const SizedBox(height: AleraTokens.space12),
              SelectableText(
                preview!['diff'] as String? ?? '',
                style: AleraTokens.monoStyle,
              ),
            ],
          ] else if (recipe.isNotEmpty) ...[
            const SizedBox(height: AleraTokens.space24),
            Text('Stages', style: theme.textTheme.titleMedium),
            for (final value in recipe['stages']! as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_map(value)['name']! as String),
                subtitle: Text(
                  '${_map(value)['purpose']}${_map(value)['gate'] == null ? '' : '\nHuman ${_map(value)['gate']} gate'}',
                ),
              ),
            const SizedBox(height: AleraTokens.space16),
            Text('Role Contracts', style: theme.textTheme.titleMedium),
            const Text(
              'These versioned contracts travel with this recipe. Copy to Personal to edit them.',
            ),
            for (final value in recipe['contracts']! as List)
              ExpansionTile(
                title: Text(
                  '${_map(value)['id']} · Revision ${_map(value)['revision']}',
                ),
                subtitle: Text(_map(value)['purpose'] as String? ?? ''),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AleraTokens.space12),
                    child: SelectableText(
                      '${_map(value)['instructions']}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AleraTokens.space16),
            ExpansionTile(
              title: const Text('Portable Document'),
              children: [
                SelectableText(document.text, style: AleraTokens.monoStyle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
