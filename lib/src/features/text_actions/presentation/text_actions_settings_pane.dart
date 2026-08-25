import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_mutations.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:alera/src/features/text_actions/presentation/text_action_editor.dart';
import 'package:alera/src/features/text_actions/presentation/text_action_list_row.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class TextActionsSettingsPane extends StatefulWidget {
  const TextActionsSettingsPane({
    super.key,
    required this.settings,
    required this.aiAssistSettings,
    required this.onChanged,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final TextActionsSettings settings;
  final AiAssistSettings aiAssistSettings;
  final ValueChanged<TextActionsSettings> onChanged;
  final Map<String, GlobalKey> groupKeys;

  @override
  State<TextActionsSettingsPane> createState() =>
      _TextActionsSettingsPaneState();
}

class _TextActionsSettingsPaneState extends State<TextActionsSettingsPane> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  String? _selectedId;
  bool _creatingNew = false;
  bool _enabled = true;
  AiAssistAgent? _agentOverride;
  String? _modelOverride;
  Map<String, String> _reasoningByModel = <String, String>{};
  String? _error;
  String? _seededSignature;

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = widget.settings.actions;
    final selected = _selectedAction(actions);
    if (!_creatingNew && selected == null && actions.isNotEmpty) {
      _selectedId = actions.first.id;
      _seedFromAction(actions.first);
    } else if (!_creatingNew && selected != null) {
      _seedFromAction(selected);
    }
    return KeyedSubtree(
      key: widget.groupKeys['actions'],
      child: AleraMasterDetail(
        masterTitle: 'Text Actions',
        masterAction: FilledButton.icon(
          onPressed: _newAction,
          icon: const Icon(AleraIcons.add, size: 16),
          label: const Text('New Action'),
        ),
        master: actions.isEmpty
            ? const AleraEmptyState(
                icon: AleraIcons.text,
                title: 'No text actions',
                message: 'Create an action to replace selected text with AI.',
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: actions.length,
                    onReorderItem: _reorder,
                    itemBuilder: (context, index) {
                      final action = actions[index];
                      return TextActionListRow(
                        key: ValueKey<String>(action.id),
                        action: action,
                        selected: action.id == _selectedId,
                        onTap: () => _selectAction(action),
                        onDuplicate: () => _duplicate(action),
                        onEnabledChanged: (value) => _setEnabled(action, value),
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(
                            AleraIcons.dragHandle,
                            size: 16,
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
        detail: _detail(selected),
      ),
    );
  }

  Widget _detail(TextAction? selected) {
    if (selected == null && !_creatingNew) {
      return const AleraEmptyState(
        icon: AleraIcons.text,
        title: 'Select a text action',
        message: 'Choose an action or create a new one.',
      );
    }
    return TextActionEditor(
      nameController: _nameController,
      promptController: _promptController,
      enabled: _enabled,
      agentOverride: _agentOverride,
      modelOverride: _modelOverride,
      reasoningByModel: _reasoningByModel,
      aiAssistSettings: widget.aiAssistSettings,
      error: _error,
      onEnabledChanged: (value) => setState(() => _enabled = value),
      onAgentChanged: (value) => setState(() {
        _agentOverride = value;
        _modelOverride = null;
        _error = null;
      }),
      onModelChanged: (value) => setState(() {
        _modelOverride = value;
        _error = null;
      }),
      onReasoningChanged: (value) {
        final agent = _agentOverride ?? widget.aiAssistSettings.agent;
        final modelId = _modelOverride?.trim().isNotEmpty == true
            ? _modelOverride!.trim()
            : widget.aiAssistSettings.modelFor(agent) ??
                  defaultModelIdForAgent(agent, widget.aiAssistSettings);
        if (modelId.isEmpty) {
          return;
        }
        setState(() {
          final next = <String, String>{..._reasoningByModel};
          if (value == null) {
            next.remove(modelId);
          } else {
            next[modelId] = value;
          }
          _reasoningByModel = next;
        });
      },
      onSave: _save,
      onDelete: selected == null
          ? _discardNew
          : () => unawaited(_delete(selected)),
      isNew: _creatingNew,
    );
  }

  TextAction? _selectedAction(List<TextAction> actions) {
    final selectedId = _selectedId;
    if (selectedId == null) {
      return null;
    }
    return actions.where((action) => action.id == selectedId).firstOrNull;
  }

  void _selectAction(TextAction action) {
    setState(() {
      _creatingNew = false;
      _selectedId = action.id;
      _error = null;
      _seedFromAction(action);
    });
  }

  void _newAction() {
    setState(() {
      _creatingNew = true;
      _selectedId = const Uuid().v4();
      _nameController.clear();
      _promptController.clear();
      _enabled = true;
      _agentOverride = null;
      _modelOverride = null;
      _reasoningByModel = <String, String>{};
      _error = null;
      _seededSignature = null;
    });
  }

  void _seedFromAction(TextAction action) {
    final signature = _signature(action);
    if (_seededSignature == signature) {
      return;
    }
    _nameController.text = action.name;
    _promptController.text = action.prompt;
    _enabled = action.enabled;
    _agentOverride = action.agentOverride;
    _modelOverride = action.modelOverride;
    _reasoningByModel = <String, String>{...action.reasoningByModel};
    _error = null;
    _seededSignature = signature;
  }

  String _signature(TextAction action) {
    return <Object?>[
      action.id,
      action.name,
      action.prompt,
      action.enabled,
      action.agentOverride?.key,
      action.modelOverride,
      action.reasoningByModel,
    ].toString();
  }

  void _save() {
    final action = TextAction(
      id: _selectedId ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      prompt: _promptController.text.trim(),
      enabled: _enabled,
      agentOverride: _agentOverride,
      modelOverride: _modelOverride?.trim().isEmpty == true
          ? null
          : _modelOverride?.trim(),
      reasoningByModel: _reasoningByModel,
    );
    final error = textActionValidationError(
      action,
      widget.settings.actions,
      editingId: _creatingNew ? null : action.id,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final next = _creatingNew
        ? TextActionsMutations.append(widget.settings, action)
        : TextActionsMutations.update(widget.settings, action);
    widget.onChanged(next);
    setState(() {
      _creatingNew = false;
      _selectedId = action.id;
      _error = null;
      _seededSignature = _signature(action);
    });
  }

  void _setEnabled(TextAction action, bool enabled) {
    widget.onChanged(
      TextActionsMutations.update(
        widget.settings,
        action.copyWith(enabled: enabled),
      ),
    );
  }

  void _reorder(int oldIndex, int newIndex) {
    widget.onChanged(
      TextActionsMutations.reorder(
        widget.settings,
        oldIndex,
        newIndex >= oldIndex ? newIndex + 1 : newIndex,
      ),
    );
  }

  void _duplicate(TextAction action) {
    final next = TextActionsMutations.duplicate(widget.settings, action);
    final sourceIndex = next.actions.indexWhere(
      (candidate) => candidate.id == action.id,
    );
    final duplicate = sourceIndex < 0 || sourceIndex + 1 >= next.actions.length
        ? null
        : next.actions[sourceIndex + 1];
    widget.onChanged(next);
    if (duplicate == null) {
      return;
    }
    setState(() {
      _creatingNew = false;
      _selectedId = duplicate.id;
      _seedFromAction(duplicate);
    });
  }

  Future<void> _delete(TextAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const AleraConfirmDialog(
        title: 'Delete Text Action',
        message: 'This action and its settings will be removed.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final remaining = widget.settings.actions
        .where((candidate) => candidate.id != action.id)
        .toList(growable: false);
    widget.onChanged(TextActionsMutations.delete(widget.settings, action.id));
    setState(() {
      _selectedId = remaining.firstOrNull?.id;
      _creatingNew = false;
      _seededSignature = null;
      _error = null;
    });
  }

  void _discardNew() {
    setState(() {
      _creatingNew = false;
      _selectedId = widget.settings.actions.firstOrNull?.id;
      _seededSignature = null;
      _error = null;
    });
  }
}
