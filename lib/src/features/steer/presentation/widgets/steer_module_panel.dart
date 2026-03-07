import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/steer/domain/steer_rule.dart';
import 'package:alera/src/features/steer/domain/steer_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SteerModulePanel extends ConsumerWidget {
  const SteerModulePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(steerControllerProvider);
    final controller = ref.read(steerControllerProvider.notifier);

    if (!state.isExpanded) {
      return _CollapsedToggle(onToggle: controller.toggleExpanded);
    }

    return _ExpandedPanel(
      state: state,
      onToggleExpanded: controller.toggleExpanded,
      onAddRule: controller.addRule,
      onToggleRule: controller.toggleRule,
      onRemoveRule: controller.removeRule,
    );
  }
}

class _CollapsedToggle extends StatelessWidget {
  const _CollapsedToggle({required this.onToggle});

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Steer',
      child: InkWell(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: const Icon(
            Icons.directions_outlined,
            size: 18,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

class _ExpandedPanel extends StatefulWidget {
  const _ExpandedPanel({
    required this.state,
    required this.onToggleExpanded,
    required this.onAddRule,
    required this.onToggleRule,
    required this.onRemoveRule,
  });

  final SteerState state;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onAddRule;
  final ValueChanged<String> onToggleRule;
  final ValueChanged<String> onRemoveRule;

  @override
  State<_ExpandedPanel> createState() => _ExpandedPanelState();
}

class _ExpandedPanelState extends State<_ExpandedPanel> {
  late final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    widget.onAddRule(text);
    _inputController.clear();
    _inputFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedRules = widget.state.sortedRules;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Flexible(
            child: sortedRules.isEmpty
                ? _buildEmptyState(theme)
                : _buildRulesList(sortedRules),
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          _buildAddInput(theme),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: [
          const Icon(
            Icons.directions_outlined,
            size: 16,
            color: AleraTokens.accent,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              'Steer',
              style: theme.textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
              ),
            ),
          ),
          Tooltip(
            message: 'Collapse',
            child: InkWell(
              onTap: widget.onToggleExpanded,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: const Padding(
                padding: EdgeInsets.all(AleraTokens.space4),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Text(
        'Add steering rules to guide responses',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundFaint,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRulesList(List<SteerRule> sortedRules) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      itemCount: sortedRules.length,
      itemBuilder: (context, index) {
        final rule = sortedRules[index];
        return _RuleItem(
          key: ValueKey(rule.id),
          rule: rule,
          onToggle: () => widget.onToggleRule(rule.id),
          onRemove: () => widget.onRemoveRule(rule.id),
        );
      },
    );
  }

  Widget _buildAddInput(ThemeData theme) {
    final isMaxReached = widget.state.isMaxRulesReached;

    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _inputController,
            focusNode: _inputFocusNode,
            enabled: !isMaxReached,
            decoration: InputDecoration(
              hintText: isMaxReached
                  ? 'Max rules reached'
                  : 'Add a steer rule...',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                borderSide: const BorderSide(color: AleraTokens.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                borderSide: const BorderSide(color: AleraTokens.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                borderSide: const BorderSide(color: AleraTokens.border),
              ),
              suffixIcon: isMaxReached
                  ? null
                  : IconButton(
                      onPressed: _handleSubmit,
                      mouseCursor: SystemMouseCursors.click,
                      icon: const Icon(
                        Icons.add,
                        size: 16,
                        color: AleraTokens.foregroundMuted,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foreground,
            ),
            onSubmitted: (_) => _handleSubmit(),
          ),
          if (widget.state.rules.isNotEmpty) ...[
            const SizedBox(height: AleraTokens.space8),
            Text(
              '${widget.state.activeRules.length}/${widget.state.rules.length} active',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleItem extends StatelessWidget {
  const _RuleItem({
    super.key,
    required this.rule,
    required this.onToggle,
    required this.onRemove,
  });

  final SteerRule rule;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: rule.active,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: AleraTokens.accent,
              checkColor: AleraTokens.onAccent,
              side: const BorderSide(color: AleraTokens.border),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          Expanded(
            child: Text(
              rule.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: rule.active ? AleraTokens.foreground : AleraTokens.foregroundFaint,
                decoration: rule.active ? null : TextDecoration.lineThrough,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          Tooltip(
            message: 'Remove',
            child: InkWell(
              onTap: onRemove,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: const Padding(
                padding: EdgeInsets.all(AleraTokens.space4),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
