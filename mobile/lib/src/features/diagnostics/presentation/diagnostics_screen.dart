import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/logging/mobile_logger.dart';
import 'package:alera_mobile/src/features/diagnostics/application/diagnostics_settings.dart';
import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Device-local diagnostics: export the log files and control crash reporting.
///
/// Logs stay on the phone and are shared explicitly by the user, rather than
/// uploaded to the runtime: a phone reporting a problem is usually a phone that
/// cannot reach its host.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _crashReporting = CrashReporting.isEnabled;
  bool _exporting = false;

  Future<void> _exportLogs() async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    try {
      await MobileLogger.flush();
      final files = MobileLogger.logFiles();
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No logs recorded yet.')),
          );
        }
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[for (final file in files) XFile(file.path)],
          subject: 'Alera Mobile Logs',
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export logs: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _setCrashReporting(bool value) async {
    setState(() => _crashReporting = value);
    await writeCrashReportingEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            Text('Logs', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.spaceSm),
            Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Export Logs'),
                subtitle: const Text(
                  'Share the log files kept on this phone. Tokens are masked '
                  'before anything is written.',
                ),
                trailing: _exporting
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _exportLogs,
              ),
            ),
            const SizedBox(height: AleraTokens.spaceXl),
            Text('Crash Reports', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.spaceSm),
            Card(
              child: SwitchListTile(
                value: _crashReporting,
                onChanged: _setCrashReporting,
                title: const Text('Send Crash Reports'),
                subtitle: const Text(
                  'Send crashes to Sentry, an external service. Off by '
                  'default; local logs work either way.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
