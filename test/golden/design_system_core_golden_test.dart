import 'package:alchemist/alchemist.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alera_golden_harness.dart';

enum _WorkbenchMode { projects, terminals }

void main() {
  runAleraGoldenTests(() {
    group('Alera design system goldens', () {
      goldenTest(
        'renders core controls',
        fileName: 'design_system_core_controls',
        constraints: const BoxConstraints(maxWidth: 780),
        builder: () => GoldenTestGroup(
          columns: 2,
          scenarioConstraints: const BoxConstraints.tightFor(width: 320),
          children: <Widget>[
            GoldenTestScenario(name: 'Actions', child: _ActionsScenario()),
            GoldenTestScenario(
              name: 'Forms and Panels',
              child: _FormsPanelScenario(),
            ),
            GoldenTestScenario(
              name: 'Badges and Status',
              child: _StatusScenario(),
            ),
            GoldenTestScenario(
              name: 'Empty State',
              child: _EmptyStateScenario(),
            ),
          ],
        ),
      );
    });
  });
}

class _ActionsScenario extends StatelessWidget {
  const _ActionsScenario();

  @override
  Widget build(BuildContext context) {
    return AleraGoldenScenarioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              AleraIconButton(
                tooltip: 'New Terminal',
                icon: AleraIcons.add,
                backgroundColor: AleraTokens.surfaceVariant,
                borderColor: AleraTokens.border,
                onPressed: () {},
              ),
              const SizedBox(width: AleraTokens.space8),
              AleraIconButton(
                tooltip: 'Settings',
                icon: AleraIcons.settings,
                onPressed: () {},
              ),
              const SizedBox(width: AleraTokens.space12),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(AleraIcons.folderOpen, size: 16),
                label: const Text('Add Project'),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(AleraIcons.gitFork, size: 16),
            label: const Text('New Workspace'),
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraSegmentedButton<_WorkbenchMode>(
            dense: true,
            selected: _WorkbenchMode.projects,
            onSelectionChanged: (_) {},
            segments: const <ButtonSegment<_WorkbenchMode>>[
              ButtonSegment<_WorkbenchMode>(
                value: _WorkbenchMode.projects,
                icon: Icon(AleraIcons.folder, size: 16),
                label: Text('Projects'),
              ),
              ButtonSegment<_WorkbenchMode>(
                value: _WorkbenchMode.terminals,
                icon: Icon(AleraIcons.terminal, size: 16),
                label: Text('Terminals'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormsPanelScenario extends StatelessWidget {
  const _FormsPanelScenario();

  @override
  Widget build(BuildContext context) {
    return AleraGoldenScenarioSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const <Widget>[
          AleraTextField(
            dense: true,
            prefixIcon: AleraIcons.search,
            hintText: 'Search Projects',
          ),
          SizedBox(height: AleraTokens.space12),
          AleraTextField(
            labelText: 'Workspace Name',
            hintText: 'feature/refactor-terminal',
          ),
          SizedBox(height: AleraTokens.space16),
          AleraPanel(
            children: <Widget>[
              _PanelRow(
                icon: AleraIcons.folder,
                title: 'Alera',
                subtitle: '/projects/alera',
              ),
              _PanelRow(
                icon: AleraIcons.terminal,
                title: 'Terminal 1',
                subtitle: 'Running',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusScenario extends StatelessWidget {
  const _StatusScenario();

  @override
  Widget build(BuildContext context) {
    return AleraGoldenScenarioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              const AleraBadge(label: 'Primary'),
              const AleraBadge(
                label: 'Synced',
                color: AleraTokens.accentSubtle,
                foregroundColor: AleraTokens.foreground,
              ),
              AleraBadge(
                label: 'Review',
                color: AleraTokens.info.withAlpha(26),
                foregroundColor: AleraTokens.info,
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.space16),
          Row(
            children: const <Widget>[
              AleraStatusIndicator(
                icon: AleraIcons.check,
                color: AleraTokens.success,
              ),
              SizedBox(width: AleraTokens.space8),
              AleraStatusIndicator(
                icon: Icons.priority_high,
                color: AleraTokens.warning,
              ),
              SizedBox(width: AleraTokens.space8),
              AleraStatusIndicator(
                icon: AleraIcons.error,
                color: AleraTokens.error,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyStateScenario extends StatelessWidget {
  const _EmptyStateScenario();

  @override
  Widget build(BuildContext context) {
    return const AleraGoldenScenarioSurface(
      child: AleraEmptyState(
        icon: AleraIcons.folderOpen,
        title: 'No Projects Yet',
        message: 'Add a local folder or clone a repository to get started.',
        action: FilledButton(onPressed: null, child: Text('Add Project')),
      ),
    );
  }
}

class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AleraTokens.foregroundMuted),
          const SizedBox(width: AleraTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AleraTokens.space2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
