import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_flow_state.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pairing/pairing_confirm_card.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pairing/pairing_manual_entry_sheet.dart';
import 'package:alera_mobile/src/features/hosts/presentation/pairing/pairing_scanner_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PairHostScreen extends ConsumerWidget {
  const PairHostScreen({super.key});

  Future<void> _enterManually(BuildContext context, WidgetRef ref) async {
    final raw = await showPairingManualEntrySheet(context);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }
    ref.read(pairingControllerProvider.notifier).offerEntered(raw);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pairingControllerProvider);
    final scannerEnabled = ref.watch(pairingScannerEnabledProvider);
    ref.listen(pairingControllerProvider, (previous, next) {
      if (next is PairingSuccess) {
        Future<void>.delayed(AleraTokens.pairingSuccessAutoClose, () {
          if (context.mounted) {
            Navigator.of(context).pop(true);
          }
        });
      }
    });
    final notifier = ref.read(pairingControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Host')),
      body: SafeArea(
        child: switch (state) {
          PairingScanning() when scannerEnabled => PairingScannerView(
            onOffer: notifier.offerEntered,
            onEnterManually: () => _enterManually(context, ref),
          ),
          PairingScanning() => _ManualFirstEntry(
            onEnterManually: () => _enterManually(context, ref),
          ),
          PairingOfferReady(:final offer) => PairingConfirmCard(
            offer: offer,
            pairing: false,
            onPair: (deviceName) =>
                notifier.confirmPair(deviceName: deviceName),
            onScanAgain: notifier.restart,
          ),
          PairingInProgress(:final offer) => PairingConfirmCard(
            offer: offer,
            pairing: true,
            onPair: (_) {},
            onScanAgain: notifier.restart,
          ),
          PairingSuccess(:final host) => _PairingSuccessView(
            hostName: host.displayName,
          ),
          PairingFailure(:final reason, :final detail) => _PairingFailureView(
            reason: reason,
            detail: detail,
            onRetry: notifier.restart,
            onEnterManually: () => _enterManually(context, ref),
          ),
        },
      ),
    );
  }
}

class _ManualFirstEntry extends StatelessWidget {
  const _ManualFirstEntry({required this.onEnterManually});

  final VoidCallback onEnterManually;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.qr_code_2_outlined,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'Pair This Phone',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'Paste the offer from the Alera mobile --json pairing create command.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton.icon(
              onPressed: onEnterManually,
              icon: const Icon(Icons.keyboard_outlined),
              label: const Text('Enter Code Manually'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingSuccessView extends StatelessWidget {
  const _PairingSuccessView({required this.hostName});

  final String hostName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: AleraTokens.successIcon,
              color: AleraTokens.success,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text('Paired', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              hostName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingFailureView extends StatelessWidget {
  const _PairingFailureView({
    required this.reason,
    required this.detail,
    required this.onRetry,
    required this.onEnterManually,
  });

  final PairingFailureReason reason;
  final String detail;
  final VoidCallback onRetry;
  final VoidCallback onEnterManually;

  String get _title {
    return switch (reason) {
      PairingFailureReason.invalidOffer => 'Invalid offer',
      PairingFailureReason.offerExpired => 'Offer expired',
      PairingFailureReason.runtimeMismatch => 'Runtime mismatch',
      PairingFailureReason.unreachable => 'Could not reach runtime',
    };
  }

  String get _hint {
    return switch (reason) {
      PairingFailureReason.invalidOffer =>
        'The scanned code is not a valid Alera pairing offer.',
      PairingFailureReason.offerExpired =>
        'Generate a fresh pairing offer on the runtime host and try again.',
      PairingFailureReason.runtimeMismatch =>
        'The endpoint answered for a different runtime than the offer '
            'promised. Check the network and generate a new offer.',
      PairingFailureReason.unreachable =>
        'Check that the runtime host is running and reachable from this '
            'phone, then try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: AleraTokens.pagePadding,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: AleraTokens.emptyIcon,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          Text(
            _title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          Text(
            _hint,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Try Again'),
          ),
          const SizedBox(height: AleraTokens.spaceSm),
          TextButton(
            onPressed: onEnterManually,
            child: const Text('Enter Code Manually'),
          ),
        ],
      ),
    );
  }
}
