import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/browser/application/browser_providers.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_history.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/domain/browser_settings.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'browser_settings_widgets.dart';

class BrowserSettingsPane extends ConsumerStatefulWidget {
  const BrowserSettingsPane({
    super.key,
    this.groupKeys = const <String, GlobalKey>{},
  });

  final Map<String, GlobalKey> groupKeys;

  @override
  ConsumerState<BrowserSettingsPane> createState() =>
      _BrowserSettingsPaneState();
}

class _BrowserSettingsPaneState extends ConsumerState<BrowserSettingsPane> {
  BrowserSettings _settings = const BrowserSettings();
  List<BrowserProfile> _profiles = const <BrowserProfile>[];
  List<BrowserClosedTab> _closedTabs = const <BrowserClosedTab>[];
  List<BrowserTrustedCertificate> _certificates =
      const <BrowserTrustedCertificate>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        ref.read(browserSettingsServiceProvider).get(),
        ref.read(browserProfileServiceProvider).list(),
        ref.read(browserClosedTabsServiceProvider).list(),
        ref.read(browserCertificateTrustServiceProvider).list(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = values[0] as BrowserSettings;
        _profiles = values[1] as List<BrowserProfile>;
        _closedTabs = values[2] as List<BrowserClosedTab>;
        _certificates = values[3] as List<BrowserTrustedCertificate>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(browserAvailabilityProvider);
    final browserReady = availability.asData?.value.meetsStableGate == true;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        KeyedSubtree(
          key: widget.groupKeys['general'],
          child: AleraSettingsGroup(
            title: 'Browser',
            description:
                'System browser engine status and address bar defaults.',
            children: <Widget>[
              AleraSettingRow(
                title: 'System Engine',
                description: availability.when(
                  data: (capabilities) => capabilities.meetsStableGate
                      ? '${browserEngineLabel(capabilities.engine)} is ready.'
                      : capabilities.limitations.isEmpty
                      ? 'Required browser capabilities are missing.'
                      : capabilities.limitations
                            .map(browserCapabilityLimitationMessage)
                            .join(' '),
                  loading: () => 'Checking the stable capability gate.',
                  error: (error, _) => error.toString(),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    availability.asData?.value.meetsStableGate == true
                        ? 'Available'
                        : 'Unavailable',
                  ),
                ),
              ),
              AleraSettingRow(
                title: 'Search Engine',
                description:
                    'Used when address bar input is not a web address.',
                child: AleraDropdownField<BrowserSearchEngine>(
                  value: _settings.searchEngine,
                  entries: <AleraDropdownFieldEntry<BrowserSearchEngine>>[
                    for (final engine in BrowserSearchEngine.values)
                      AleraDropdownFieldEntry<BrowserSearchEngine>(
                        value: engine,
                        label: _searchEngineLabel(engine),
                      ),
                  ],
                  onChanged: _setSearchEngine,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['certificates'],
          child: AleraSettingsGroup(
            title: 'Trusted Local Certificates',
            description:
                'Exact certificates allowed for local hosts in each profile.',
            children: <Widget>[
              if (_certificates.isEmpty)
                const AleraEmptyState(
                  icon: AleraIcons.secure,
                  title: 'No trusted certificates',
                  message: 'Certificates trusted permanently will appear here.',
                )
              else
                for (final certificate in _certificates)
                  _TrustedBrowserCertificateRow(
                    certificate: certificate,
                    profileLabel: _profileLabel(certificate.profileId),
                    onRemove: _busy
                        ? null
                        : () => _removeCertificate(certificate),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['profiles'],
          child: AleraSettingsGroup(
            title: 'Profiles',
            description:
                'Isolated cookies, storage and site permission catalogs.',
            children: <Widget>[
              for (final profile in _profiles)
                _BrowserProfileSettingsRow(
                  profile: profile,
                  onDelete: profile.isDefault || !browserReady
                      ? null
                      : () => _deleteProfile(profile),
                ),
              AleraSettingRow(
                title: 'Create Profile',
                description: 'Creates a new isolated persistent profile.',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _busy || !browserReady ? null : _createProfile,
                    icon: const Icon(AleraIcons.add),
                    label: const Text('Create'),
                  ),
                ),
              ),
              AleraSettingRow(
                title: 'Import Cookies',
                description: 'Imports atomically into a new isolated profile.',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _busy || !browserReady ? null : _importCookies,
                    icon: const Icon(AleraIcons.download),
                    label: const Text('Import'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space16),
        KeyedSubtree(
          key: widget.groupKeys['data'],
          child: AleraSettingsGroup(
            title: 'Browsing Data',
            description: 'History and recently closed browser tabs.',
            children: <Widget>[
              AleraSettingRow(
                title: 'History',
                description:
                    'Removes saved browser history from every profile.',
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _clearHistory,
                    child: const Text('Clear History'),
                  ),
                ),
              ),
              if (_closedTabs.isEmpty)
                const AleraEmptyState(
                  icon: AleraIcons.restore,
                  title: 'No recently closed tabs',
                  message: 'Closed browser tabs will appear here.',
                )
              else
                for (final tab in _closedTabs)
                  _ClosedBrowserTabRow(
                    tab: tab,
                    onReopen: () => _reopen(tab),
                    onRemove: () => _removeClosed(tab),
                  ),
            ],
          ),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
          ),
        ],
      ],
    );
  }

  Future<void> _setSearchEngine(BrowserSearchEngine engine) async {
    final previous = _settings;
    setState(() => _settings = BrowserSettings(searchEngine: engine));
    try {
      final saved = await ref
          .read(browserSettingsServiceProvider)
          .set(_settings);
      if (mounted) {
        setState(() => _settings = saved);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _settings = previous;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _createProfile() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _BrowserProfileNameDialog(),
    );
    if (name == null) {
      return;
    }
    await _withBusy(() async {
      await ref.read(browserProfileCoordinatorProvider).create(name: name);
      await _refresh();
    });
  }

  Future<void> _deleteProfile(BrowserProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Delete Browser Profile?',
        message:
            '${profile.label} and its cookies, storage and permissions will '
            'be removed.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _withBusy(() async {
      await ref.read(browserProfileCoordinatorProvider).delete(profile.id);
      await _refresh();
    });
  }

  Future<void> _importCookies() async {
    await _withBusy(() async {
      final sources = await ref
          .read(browserProfileCoordinatorProvider)
          .probeImportSources();
      if (!mounted) {
        return;
      }
      final request = await showDialog<_BrowserImportRequest>(
        context: context,
        builder: (_) => _BrowserCookieImportDialog(sources: sources),
      );
      if (request == null) {
        return;
      }
      String? manualJson;
      if (request.source == BrowserImportSourceFamily.manual) {
        final file = await openFile(
          acceptedTypeGroups: const <XTypeGroup>[
            XTypeGroup(label: 'JSON', extensions: <String>['json']),
          ],
          confirmButtonText: 'Import Cookies',
        );
        if (file == null) {
          return;
        }
        final byteLength = await file.length();
        if (byteLength > browserManualCookieImportMaximumBytes) {
          throw BrowserFailure(
            code: BrowserErrorCode.invalidPayload,
            message: 'Manual cookie import is limited to 16 MiB.',
            recoverable: true,
            details: <String, Object?>{
              'maximumBytes': browserManualCookieImportMaximumBytes,
              'actualBytes': byteLength,
            },
          );
        }
        manualJson = await file.readAsString();
      }
      await ref
          .read(browserProfileCoordinatorProvider)
          .importCookies(
            name: request.name,
            source: request.source,
            sourceProfileName: request.sourceProfileName,
            manualJson: manualJson,
          );
      await _refresh();
    });
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Clear Browser History?',
        message: 'Saved browser history will be removed from every profile.',
        confirmLabel: 'Clear History',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _withBusy(() async {
      await ref.read(browserHistoryServiceProvider).clear();
    });
  }

  String _profileLabel(String profileId) {
    for (final profile in _profiles) {
      if (profile.id == profileId) {
        return profile.label;
      }
    }
    return profileId;
  }

  Future<void> _removeCertificate(BrowserTrustedCertificate certificate) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Remove Trusted Certificate?',
        message:
            'Alera will ask again for ${certificate.host} after the app restarts.',
        confirmLabel: 'Remove Trust',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _withBusy(() async {
      await ref
          .read(browserCertificateTrustServiceProvider)
          .remove(certificate);
      ref
          .read(browserCertificateTrustRegistryProvider)
          .invalidatePersistentCache();
      await _refresh();
      if (mounted) {
        AleraToast.show(
          context,
          message:
              'Certificate trust removed. Restart Alera to apply the change.',
        );
      }
    });
  }

  Future<void> _reopen(BrowserClosedTab tab) async {
    await _withBusy(() async {
      await ref.read(browserClosedTabsServiceProvider).reopen(tab.id);
      await _refresh();
    });
  }

  Future<void> _removeClosed(BrowserClosedTab tab) async {
    await _withBusy(() async {
      await ref.read(browserClosedTabsServiceProvider).remove(tab.id);
      await _refresh();
    });
  }

  Future<void> _withBusy(Future<void> Function() operation) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        AleraToast.show(
          context,
          message: error.toString(),
          tone: AleraToastTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
