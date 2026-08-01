import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_settings.dart';
import 'package:flutter/material.dart';

class ClaudeQuotaProfileDialog extends StatefulWidget {
  const ClaudeQuotaProfileDialog({
    super.key,
    required this.profiles,
    this.initial,
  });

  final List<ClaudeQuotaProfile> profiles;
  final ClaudeQuotaProfile? initial;

  @override
  State<ClaudeQuotaProfileDialog> createState() =>
      _ClaudeQuotaProfileDialogState();
}

class _ClaudeQuotaProfileDialogState extends State<ClaudeQuotaProfileDialog> {
  late final TextEditingController _alias;
  late final TextEditingController _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(text: widget.initial?.alias);
    _profile = TextEditingController(text: widget.initial?.profile);
  }

  @override
  void dispose() {
    _alias.dispose();
    _profile.dispose();
    super.dispose();
  }

  void _save() {
    final alias = _alias.text.trim();
    final profile = _profile.text.trim();
    final duplicate = widget.profiles.any(
      (candidate) =>
          candidate != widget.initial &&
          (candidate.alias == alias || candidate.profile == profile),
    );
    if (alias.isEmpty || profile.isEmpty) {
      setState(() => _error = 'Alias and profile are required.');
    } else if (duplicate) {
      setState(() => _error = 'Alias and profile must be unique.');
    } else {
      Navigator.of(
        context,
      ).pop(ClaudeQuotaProfile(alias: alias, profile: profile));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Add CCS Profile' : 'Edit CCS Profile',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _alias,
            decoration: const InputDecoration(labelText: 'Alias'),
          ),
          TextField(
            controller: _profile,
            decoration: const InputDecoration(labelText: 'CCS Profile'),
            onSubmitted: (_) => _save(),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AleraTokens.error)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save Profile')),
      ],
    );
  }
}
