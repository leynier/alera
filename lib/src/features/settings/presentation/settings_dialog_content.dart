import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';

const double _kSectionIconSize = 18;

/// Minimum number of pane groups before the header shows subsection chips.
const int _kGroupChipsThreshold = 3;

class SettingsContent extends StatefulWidget {
  const SettingsContent({
    super.key,
    required this.section,
    required this.onClose,
    this.groupKeys = const <String, GlobalKey>{},
    this.scrollToGroupId,
  });

  final SettingsSectionData section;
  final VoidCallback onClose;
  final Map<String, GlobalKey> groupKeys;

  /// When set (search jump), the content scrolls to this group after build.
  final String? scrollToGroupId;

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  @override
  void initState() {
    super.initState();
    _scheduleSearchJump();
  }

  @override
  void didUpdateWidget(SettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section.id != oldWidget.section.id ||
        widget.scrollToGroupId != oldWidget.scrollToGroupId) {
      _scheduleSearchJump();
    }
  }

  void _scheduleSearchJump() {
    final groupId = widget.scrollToGroupId;
    if (groupId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.scrollToGroupId == groupId) {
        _scrollToGroup(groupId);
      }
    });
  }

  void _scrollToGroup(String groupId) {
    final groupContext = widget.groupKeys[groupId]?.currentContext;
    if (groupContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      groupContext,
      duration: AleraTokens.durationMid,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final showGroupChips = section.groups.length >= _kGroupChipsThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space24,
            AleraTokens.space20,
            AleraTokens.space24,
            AleraTokens.space16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    section.icon,
                    size: _kSectionIconSize,
                    color: AleraTokens.accent,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      section.title,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  if (section.onReset != null) ...<Widget>[
                    const SizedBox(width: AleraTokens.space8),
                    TextButton(
                      onPressed: () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        await Future<void>.delayed(Duration.zero);
                        await section.onReset!();
                      },
                      child: Text('Reset ${section.title}'),
                    ),
                  ],
                  const SizedBox(width: AleraTokens.space4),
                  AleraIconButton(
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                    icon: AleraIcons.close,
                    minSize: 34,
                  ),
                ],
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                section.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              if (showGroupChips) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                Wrap(
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space6,
                  children: <Widget>[
                    for (final group in section.groups)
                      _GroupChip(
                        title: group.title,
                        onTap: () => _scrollToGroup(group.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        // Resource sections use a master-detail layout with independent
        // scroll contexts, so they fill the pane instead of living inside a
        // single scrolling list.
        Expanded(
          child: section.navGroup == SettingsNavGroup.resources
              ? Padding(
                  padding: const EdgeInsets.all(AleraTokens.space24),
                  child: section.builder(context),
                )
              : ListView(
                  padding: const EdgeInsets.all(AleraTokens.space24),
                  children: <Widget>[section.builder(context)],
                ),
        ),
      ],
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      mouseCursor: SystemMouseCursors.click,
      child: AleraChip(label: title),
    );
  }
}

class NoSettingsResults extends StatelessWidget {
  const NoSettingsResults({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: AleraEmptyState(message: 'No settings found.'),
        ),
        Positioned(
          top: AleraTokens.space16,
          right: AleraTokens.space16,
          child: AleraIconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: AleraIcons.close,
            minSize: 28,
          ),
        ),
      ],
    );
  }
}
