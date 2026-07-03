import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/application_support_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraCliSkillControl extends ConsumerStatefulWidget {
  const AleraCliSkillControl({super.key});

  @override
  ConsumerState<AleraCliSkillControl> createState() =>
      _AleraCliSkillControlState();
}

class _AleraCliSkillControlState extends ConsumerState<AleraCliSkillControl> {
  bool _installing = false;
  String? _status;

  Future<void> _install() async {
    if (_installing) {
      return;
    }
    setState(() {
      _installing = true;
      _status = null;
    });
    try {
      final result = await ref
          .read(aleraCliSkillServiceProvider)
          .installOrUpdate();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = result.summary;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Install Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(
      const ClipboardData(text: aleraCliSkillInstallCommand),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Install Command Copied';
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            SizedBox(
              height: kSupportControlHeight,
              child: OutlinedButton.icon(
                onPressed: _installing ? null : _copyCommand,
                icon: const Icon(AleraIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ),
            SizedBox(
              height: kSupportControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AleraTokens.foreground,
                        ),
                      )
                    : const Icon(AleraIcons.download, size: 16),
                label: Text(_installing ? 'Installing' : 'Install / Update'),
              ),
            ),
          ],
        ),
        if (status != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            status,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status.startsWith('Install Failed')
                  ? AleraTokens.error
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}
