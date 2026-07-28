part of 'browser_settings_pane.dart';

class _BrowserProfileSettingsRow extends StatelessWidget {
  const _BrowserProfileSettingsRow({required this.profile, this.onDelete});

  final BrowserProfile profile;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: profile.label,
      description: profile.isDefault
          ? 'Default Shared Browser Profile.'
          : 'Isolated Persistent Browser Profile.',
      child: Align(
        alignment: Alignment.centerRight,
        child: AleraIconButton(
          tooltip: profile.isDefault
              ? 'Default Profile'
              : onDelete == null
              ? 'Browser Engine Unavailable'
              : 'Delete Profile',
          icon: profile.isDefault ? AleraIcons.secure : AleraIcons.delete,
          onPressed: onDelete,
        ),
      ),
    );
  }
}

class _ClosedBrowserTabRow extends StatelessWidget {
  const _ClosedBrowserTabRow({
    required this.tab,
    required this.onReopen,
    required this.onRemove,
  });

  final BrowserClosedTab tab;
  final VoidCallback onReopen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AleraSettingRow(
      title: tab.title.isEmpty ? 'Recently Closed Tab' : tab.title,
      description: tab.url.host,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
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

class _BrowserProfileNameDialog extends StatefulWidget {
  const _BrowserProfileNameDialog();

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Create Browser Profile',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'Profile Name',
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

final class _BrowserImportRequest {
  const _BrowserImportRequest({
    required this.name,
    required this.source,
    this.sourceProfileName,
  });

  final String name;
  final BrowserImportSourceFamily source;
  final String? sourceProfileName;
}

typedef _BrowserImportSourceOption = ({
  BrowserImportSourceFamily source,
  String? profileName,
});

class _BrowserCookieImportDialog extends StatefulWidget {
  const _BrowserCookieImportDialog({required this.sources});

  final List<BrowserCookieImportSourceStatus> sources;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Import Browser Cookies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _nameController,
              autofocus: true,
              hintText: 'New Profile Name',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<_BrowserImportSourceOption>(
              value: _source,
              hintText: 'Import Source',
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
