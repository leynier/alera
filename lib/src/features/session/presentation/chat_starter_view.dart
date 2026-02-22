import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class ChatStarterView extends StatefulWidget {
  const ChatStarterView({
    super.key,
    required this.workspacePath,
    required this.controller,
    required this.isBusy,
    required this.availableModels,
  });

  final String workspacePath;
  final SessionController controller;
  final bool isBusy;
  final List<CodexModelOption> availableModels;

  @override
  State<ChatStarterView> createState() => _ChatStarterViewState();
}

class _ChatStarterViewState extends State<ChatStarterView> {
  final _promptController = TextEditingController();
  String? _selectedModelId;
  var _defaultsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final defaults = await widget.controller.loadSettingsDefaults();
      if (!mounted) {
        return;
      }
      final availableIds = widget.availableModels
          .map((model) => model.id)
          .toSet();
      final fallback = widget.availableModels.isNotEmpty
          ? widget.availableModels.first.id
          : codexDefaultModelId();
      final selected = availableIds.contains(defaults.selectedModel)
          ? defaults.selectedModel
          : fallback;
      setState(() {
        _selectedModelId = selected;
        _defaultsLoaded = true;
      });
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !widget.isBusy &&
      _promptController.text.trim().isNotEmpty &&
      _defaultsLoaded &&
      _selectedModelId != null;

  void _submit() {
    if (!_canSubmit) {
      return;
    }
    widget.controller.createSession(
      SessionCreateRequest(
        projectPath: widget.workspacePath,
        firstPrompt: _promptController.text.trim(),
        model: _selectedModelId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = widget.availableModels;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(AleraTokens.space24),
          children: <Widget>[
            if (!_defaultsLoaded)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AleraTokens.accent,
                backgroundColor: AleraTokens.surfaceVariant,
              ),
            Container(
              padding: const EdgeInsets.all(AleraTokens.space16),
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.source_outlined,
                    size: 18,
                    color: AleraTokens.accent,
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          p.basename(widget.workspacePath),
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AleraTokens.space2),
                        Text(
                          widget.workspacePath,
                          style: AleraTokens.monoStyle.copyWith(
                            fontSize: 11,
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AleraTokens.space24),
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: Text(
                'WHAT DO YOU WANT TO BUILD?',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AleraTokens.foregroundFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            TextField(
              controller: _promptController,
              maxLines: 8,
              minLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'describe what you want to build...',
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            DropdownButtonFormField<String>(
              initialValue: _selectedModelId,
              items: models
                  .map(
                    (model) => DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(model.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: widget.isBusy
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedModelId = value;
                      });
                    },
              decoration: const InputDecoration(labelText: 'model'),
            ),
            const SizedBox(height: AleraTokens.space24),
            FilledButton.icon(
              onPressed: _canSubmit ? _submit : null,
              icon: widget.isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AleraTokens.onAccent,
                      ),
                    )
                  : const Icon(Icons.play_arrow, size: 18),
              label: Text(
                widget.isBusy ? 'starting session...' : 'start session',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
