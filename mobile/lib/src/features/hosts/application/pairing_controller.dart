import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/pairing_flow_state.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_device_credentials.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pairing_controller.g.dart';

typedef PairDeviceFunction =
    Future<PairedDeviceCredentials> Function(
      PairingOffer offer, {
      String? deviceName,
    });

/// Indirection over the static pairing call so tests can drive the pairing
/// flow without a live runtime gateway.
@riverpod
PairDeviceFunction pairDeviceFunction(Ref ref) {
  return MobileRuntimeClient.pairDevice;
}

/// Whether the QR scanner can be offered as the primary pairing input. Tests
/// (and platforms without camera support) override this to false so the
/// manual entry path becomes the primary flow.
@riverpod
bool pairingScannerEnabled(Ref ref) {
  return true;
}

@riverpod
class PairingController extends _$PairingController {
  @override
  PairingFlowState build() {
    return const PairingScanning();
  }

  void offerEntered(String rawOffer) {
    try {
      state = PairingOfferReady(PairingOffer.parse(rawOffer));
    } on FormatException catch (error) {
      state = PairingFailure(_parseFailureReason(error), error.message);
    } on Object catch (error) {
      state = PairingFailure(
        PairingFailureReason.invalidOffer,
        error.toString(),
      );
    }
  }

  Future<void> confirmPair({String? deviceName}) async {
    final current = state;
    if (current is! PairingOfferReady) {
      return;
    }
    final offer = current.offer;
    if (offer.isExpired) {
      state = const PairingFailure(
        PairingFailureReason.offerExpired,
        'Pairing offer expired',
      );
      return;
    }
    state = PairingInProgress(offer);
    try {
      final pair = ref.read(pairDeviceFunctionProvider);
      final credentials = await pair(offer, deviceName: deviceName);
      final host = PairedHostProfile.fromPairingResult(offer, credentials);
      // Persist through the keep-alive repository instead of the auto-dispose
      // hosts controller: the host list may not be mounted while pairing.
      await ref
          .read(hostRepositoryProvider)
          .savePairedHost(host, credentials.deviceToken);
      ref.invalidate(pairedHostsControllerProvider);
      state = PairingSuccess(host);
    } on FormatException catch (error) {
      state = PairingFailure(
        error.message.toLowerCase().contains('runtime id')
            ? PairingFailureReason.runtimeMismatch
            : PairingFailureReason.invalidOffer,
        error.message,
      );
    } on Object catch (error) {
      state = PairingFailure(
        PairingFailureReason.unreachable,
        error.toString(),
      );
    }
  }

  void restart() {
    state = const PairingScanning();
  }

  PairingFailureReason _parseFailureReason(FormatException error) {
    if (error.message.toLowerCase().contains('expired')) {
      return PairingFailureReason.offerExpired;
    }
    return PairingFailureReason.invalidOffer;
  }
}
