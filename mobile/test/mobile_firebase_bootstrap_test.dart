import 'package:alera_mobile/src/features/push_notifications/infra/mobile_firebase_bootstrap.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const initializeChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore',
    StandardMessageCodec(),
  );
  const optionsChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.optionsFromResource',
    StandardMessageCodec(),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockDecodedMessageHandler<Object?>(
      initializeChannel,
      (_) async => <Object?>[<Object?>[]],
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      optionsChannel,
      (_) async => <Object?>[
        'Exception',
        'Failed to load FirebaseOptions from resource.',
        null,
      ],
    );
  });

  tearDown(() {
    MobileFirebaseBootstrap.ready = false;
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockDecodedMessageHandler<Object?>(initializeChannel, null);
    messenger.setMockDecodedMessageHandler<Object?>(optionsChannel, null);
  });

  test(
    'missing native Firebase resources disable push without blocking startup',
    () async {
      MobileFirebaseBootstrap.ready = true;

      expect(await MobileFirebaseBootstrap.initialize(), isFalse);
      expect(MobileFirebaseBootstrap.ready, isFalse);
    },
  );

  test(
    'background notification tolerates missing native Firebase resources',
    () async {
      await expectLater(
        aleraFirebaseMessagingBackgroundHandler(const RemoteMessage()),
        completes,
      );
    },
  );
}
