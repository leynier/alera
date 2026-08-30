import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';

sealed class const PairingFlowState();

class const PairingScanning() extends PairingFlowState;

class const PairingOfferReady(final PairingOffer offer)
    extends PairingFlowState;

class const PairingInProgress(final PairingOffer offer)
    extends PairingFlowState;

class const PairingSuccess(final PairedHostProfile host)
    extends PairingFlowState;

class const PairingFailure(
  final PairingFailureReason reason,
  final String detail,
) extends PairingFlowState;

enum PairingFailureReason {
  invalidOffer,
  offerExpired,
  runtimeMismatch,
  unreachable,
}
