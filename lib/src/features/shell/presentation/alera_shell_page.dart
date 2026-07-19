import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_status/application/runtime_agent_status_sync.dart';
import 'package:alera/src/features/agent_quota/presentation/agent_quota_status_bar.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/app_menu/presentation/alera_app_menu_scope.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_shortcuts_scope.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workbench_tab_attention.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workspace_context_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:alera/src/features/workbench/application/terminal_driver_presence_controller.dart';
import 'package:alera/src/features/workbench/presentation/mobile_driver_overlay.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'alera_shell_page_body.dart';

class AleraShellPage extends ConsumerWidget {
  const AleraShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(aleraDatabaseProvider);
    return dbAsync.when(
      loading: () => const _ShellLoading(),
      error: (error, _) => _ShellError(error: error.toString()),
      data: (_) => const _AleraShellPageBody(),
    );
  }
}

class _ShellLoading extends StatelessWidget {
  const _ShellLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _ShellError extends StatelessWidget {
  const _ShellError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(AleraIcons.error, color: AleraTokens.error, size: 32),
              const SizedBox(height: AleraTokens.space12),
              Text(
                'Failed to open the local database',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AleraShellPageBody extends ConsumerStatefulWidget {
  const _AleraShellPageBody();

  @override
  ConsumerState<_AleraShellPageBody> createState() =>
      _AleraShellPageBodyState();
}

bool _canShowContextSidebar({
  required double shellWidth,
  required bool collapsed,
  required WorkbenchViewPrefs prefs,
}) {
  final leftWidth = collapsed
      ? AleraTokens.sidebarCollapsedWidth
      : prefs.sidebarWidth;
  final rightWidth = prefs.rightSidebarVisible
      ? prefs.rightSidebarWidth
      : AleraTokens.sidebarCollapsedWidth;
  return shellWidth - leftWidth - rightWidth >= AleraTokens.emptyStateMaxWidth;
}

String buildRawLogClipboardText(List<String> logs) {
  return logs.join('\n');
}
