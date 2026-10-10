import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/mcp_access/application/mcp_access_providers.dart';
import 'package:alera/src/features/webhooks/application/webhook_providers.dart';
import 'package:alera/src/features/webhooks/domain/runtime_webhook.dart';
import 'package:alera/src/features/webhooks/domain/webhook_repository.dart';
import 'package:alera/src/features/webhooks/presentation/add_webhook_dialog.dart';
import 'package:alera/src/features/webhooks/presentation/webhook_secret_dialog.dart';
import 'package:alera/src/features/webhooks/presentation/webhooks_settings_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wires the webhook providers into [WebhooksSettingsGroup]. Account sign-in
/// comes from the MCP settings, which already follow `aleraAccountChanged`.
class const WebhooksSettings({super.key}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<WebhooksSettings> createState() => _WebhooksSettingsState();
}

class _WebhooksSettingsState extends ConsumerState<WebhooksSettings> {
  final Set<String> _busyIds = <String>{};
  String? _error;
  String? _notice;

  @override
  Widget build(BuildContext context) {
    return WebhooksSettingsGroup(
      view: _view(),
      busyIds: _busyIds,
      error: _error,
      notice: _notice,
      onRefresh: _refresh,
      onAdd: _add,
      onTest: _test,
      onDelete: _delete,
    );
  }

  WebhooksView _view() {
    final supported = ref.watch(webhooksSupportedProvider);
    final settings = ref.watch(mcpAccessSettingsControllerProvider);
    if (supported.isLoading || settings.isLoading) {
      return const WebhooksLoading();
    }
    if (supported case AsyncError(:final error)) {
      return WebhooksFailed(webhookErrorMessage(error));
    }
    if (supported.value != true) {
      return const WebhooksUnavailable(
        'Update the Alera runtime to use webhooks. This runtime does not '
        'publish runtime events.',
      );
    }
    if (settings.value?.accountConnected != true) {
      return const WebhooksSignedOut();
    }
    // `when` keeps the previous list on screen while a refresh is in flight.
    return ref
        .watch(runtimeWebhooksProvider)
        .when(
          data: WebhooksLoaded.new,
          error: (error, _) => WebhooksFailed(webhookErrorMessage(error)),
          loading: WebhooksLoading.new,
        );
  }

  void _refresh() {
    setState(() {
      _error = null;
      _notice = null;
    });
    ref.invalidate(runtimeWebhooksProvider);
  }

  Future<void> _add() async {
    final repository = ref.read(webhookRepositoryProvider);
    final created = await showDialog<RuntimeWebhookCreation>(
      context: context,
      builder: (_) => AddWebhookDialog(
        onCreate: (url, kinds) =>
            repository.createWebhook(url: url, kinds: kinds),
        errorMessage: webhookErrorMessage,
      ),
    );
    if (created == null || !mounted) {
      return;
    }
    setState(() {
      _error = null;
      _notice = null;
    });
    ref.invalidate(runtimeWebhooksProvider);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WebhookSecretDialog(creation: created),
    );
  }

  Future<void> _test(RuntimeWebhook webhook) {
    return _run(webhook, () async {
      await ref.read(webhookRepositoryProvider).testWebhook(webhook.id);
      if (mounted) {
        setState(
          () => _notice =
              'Test event queued for ${webhook.url}. Refresh to see its '
              'delivery.',
        );
      }
    });
  }

  Future<void> _delete(RuntimeWebhook webhook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Delete Webhook',
        message:
            '${webhook.url} stops receiving runtime events. Its signing '
            'secret cannot be recovered.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _run(webhook, () async {
      await ref.read(webhookRepositoryProvider).deleteWebhook(webhook.id);
      if (mounted) {
        ref.invalidate(runtimeWebhooksProvider);
      }
    });
  }

  Future<void> _run(
    RuntimeWebhook webhook,
    Future<void> Function() action,
  ) async {
    setState(() {
      _busyIds.add(webhook.id);
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = webhookErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(webhook.id));
      }
    }
  }
}
