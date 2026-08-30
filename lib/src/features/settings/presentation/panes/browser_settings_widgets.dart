part of 'browser_settings_pane.dart';

class const _BrowserProfileSettingsRow({
  required final BrowserProfile profile,
  final VoidCallback? onDelete,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: profile.label,
      description: profile.isDefault
          ? 'Default shared browser profile.'
          : 'Isolated persistent browser profile.',
      child: Align(
        alignment: Alignment.centerRight,
        child: AleraIconButton(
          tooltip: profile.isDefault
              ? 'Default Profile'
              : onDelete == null
              ? 'Browser engine unavailable'
              : 'Delete Profile',
          icon: profile.isDefault ? AleraIcons.secure : AleraIcons.delete,
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class const _ClosedBrowserTabRow({
  required final BrowserClosedTab tab,
  required final VoidCallback onReopen,
  required final VoidCallback onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: tab.title.isEmpty ? 'Recently Closed Tab' : tab.title,
      description: tab.url.host,
      child: Row(
        mainAxisAlignment: .end,
        children: <Widget>[
          AleraIconButton(
            tooltip: 'Reopen Tab',
            icon: AleraIcons.refresh,
            onPressed: onReopen,
          ),
          AleraIconButton(
            tooltip: 'Remove From List',
            icon: AleraIcons.close,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class const _TrustedBrowserCertificateRow({
  required final BrowserTrustedCertificate certificate,
  required final String profileLabel,
  final VoidCallback? onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fingerprint = displayBrowserCertificateFingerprint(
      certificate.fingerprintSha256,
    );
    return AleraSettingRow(
      title: certificate.host,
      description:
          '$profileLabel - ${certificate.subject ?? certificate.issuer ?? 'Local certificate'}\n$fingerprint',
      child: Align(
        alignment: Alignment.centerRight,
        child: AleraIconButton(
          tooltip: 'Remove Trust',
          icon: AleraIcons.delete,
          onPressed: onRemove,
        ),
      ),
    );
  }
}

class const _BrowserProfileNameDialog() extends StatefulWidget {
  @override
  State<_BrowserProfileNameDialog> createState() =>
      _BrowserProfileNameDialogState();
}

class _BrowserProfileNameDialogState extends State<_BrowserProfileNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return AleraDialog(
      maxWidth: AleraTokens.dialogCompactWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              'Create Browser Profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'Profile name',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _finish(valid),
            ),
            const SizedBox(height: AleraTokens.space16),
            FilledButton(
              onPressed: valid ? () => _finish(true) : null,
              child: const Text('Create Profile'),
            ),
          ],
        ),
      ),
    );
  }

  void _finish(bool valid) {
    if (valid) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }
}

final class const _BrowserImportRequest({
  required final String name,
  required final BrowserImportSourceFamily source,
  final String? sourceProfileName,
});

typedef _BrowserImportSourceOption = ({
  BrowserImportSourceFamily source,
  String? profileName,
});

class const _BrowserCookieImportDialog({
  required final List<BrowserCookieImportSourceStatus> sources,
}) extends StatefulWidget {
  @override
  State<_BrowserCookieImportDialog> createState() =>
      _BrowserCookieImportDialogState();
}

class _BrowserCookieImportDialogState
    extends State<_BrowserCookieImportDialog> {
  final TextEditingController _nameController = TextEditingController();
  _BrowserImportSourceOption? _source;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableImportOptions(widget.sources);
    final valid = _nameController.text.trim().isNotEmpty && _source != null;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              'Import Browser Cookies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _nameController,
              autofocus: true,
              hintText: 'New profile name',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<_BrowserImportSourceOption>(
              value: _source,
              hintText: 'Import source',
              entries: <AleraDropdownFieldEntry<_BrowserImportSourceOption>>[
                for (final option in available)
                  AleraDropdownFieldEntry<_BrowserImportSourceOption>(
                    value: option,
                    label: option.profileName == null
                        ? _importSourceLabel(option.source)
                        : '${_importSourceLabel(option.source)} - '
                              '${option.profileName}',
                  ),
              ],
              onChanged: (value) => setState(() => _source = value),
            ),
            const SizedBox(height: AleraTokens.space16),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.of(context).pop(
                      _BrowserImportRequest(
                        name: _nameController.text.trim(),
                        source: _source!.source,
                        sourceProfileName: _source!.profileName,
                      ),
                    )
                  : null,
              child: const Text('Import Into New Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

List<_BrowserImportSourceOption> _availableImportOptions(
  List<BrowserCookieImportSourceStatus> statuses,
) {
  final options = <_BrowserImportSourceOption>[];
  for (final status in statuses) {
    if (!status.supported || !status.available) {
      continue;
    }
    if (status.source == BrowserImportSourceFamily.manual) {
      options.add((source: status.source, profileName: null));
      continue;
    }
    final counts = <String, int>{};
    for (final name in status.profileNames.where((name) => name.isNotEmpty)) {
      counts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final name in status.profileNames) {
      if (counts[name] == 1) {
        options.add((source: status.source, profileName: name));
      }
    }
  }
  return options;
}

String _searchEngineLabel(BrowserSearchEngine engine) {
  return switch (engine) {
    BrowserSearchEngine.google => 'Google',
    BrowserSearchEngine.duckDuckGo => 'DuckDuckGo',
    BrowserSearchEngine.bing => 'Bing',
    BrowserSearchEngine.kagi => 'Kagi',
  };
}

String _importSourceLabel(BrowserImportSourceFamily source) {
  return switch (source) {
    BrowserImportSourceFamily.chrome => 'Chrome',
    BrowserImportSourceFamily.edge => 'Edge',
    BrowserImportSourceFamily.arc => 'Arc',
    BrowserImportSourceFamily.brave => 'Brave',
    BrowserImportSourceFamily.comet => 'Comet',
    BrowserImportSourceFamily.helium => 'Helium',
    BrowserImportSourceFamily.firefox => 'Firefox',
    BrowserImportSourceFamily.safari => 'Safari',
    BrowserImportSourceFamily.manual => 'Manual JSON',
  };
}
