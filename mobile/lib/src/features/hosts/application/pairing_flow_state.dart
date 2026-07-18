import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';

sealed class PairingFlowState {
  const PairingFlowState();
}

class PairingScanning extends PairingFlowState {
  const PairingScanning();
}

class PairingOfferReady extends PairingFlowState {
  const PairingOfferReady(this.offer);

  final PairingOffer offer;
}

class PairingInProgress extends PairingFlowState {
  const PairingInProgress(this.offer);

  final PairingOffer offer;
}

class PairingSuccess extends PairingFlowState {
  const PairingSuccess(this.host);

  final PairedHostProfile host;
}

class PairingFailure extends PairingFlowState {
  const PairingFailure(this.reason, this.detail);

  final PairingFailureReason reason;
  final String detail;
}

enum PairingFailureReason {
  invalidOffer,
  offerExpired,
  runtimeMismatch,
  unreachable,
}
