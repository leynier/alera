import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class MobileFirebaseBootstrap {
  static bool ready = false;

  static Future<bool> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        final options = MobileFirebaseOptions.current;
        if (options == null) {
          await Firebase.initializeApp();
        } else {
          await Firebase.initializeApp(options: options);
        }
      }
      ready = true;
      FirebaseMessaging.onBackgroundMessage(
        aleraFirebaseMessagingBackgroundHandler,
      );
      return true;
    } on FirebaseException {
      ready = false;
      return false;
    } on PlatformException {
      // Missing native Firebase resources must not prevent offline startup.
      ready = false;
      return false;
    }
  }
}

abstract final class MobileFirebaseOptions {
  static const String _apiKey = .fromEnvironment('ALERA_FIREBASE_API_KEY');
  static const String _appId = .fromEnvironment('ALERA_FIREBASE_APP_ID');
  static const String _senderId = .fromEnvironment(
    'ALERA_FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _projectId = .fromEnvironment(
    'ALERA_FIREBASE_PROJECT_ID',
  );
  static const String _iosBundleId = .fromEnvironment(
    'ALERA_FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'dev.leynier.aleraMobile',
  );

  static FirebaseOptions? get current {
    if (_apiKey.isEmpty ||
        _appId.isEmpty ||
        _senderId.isEmpty ||
        _projectId.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
          ? _iosBundleId
          : null,
    );
  }
}

@pragma('vm:entry-point')
Future<void> aleraFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  if (Firebase.apps.isNotEmpty) {
    return;
  }
  try {
    final options = MobileFirebaseOptions.current;
    if (options == null) {
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(options: options);
    }
  } on FirebaseException {
    // A notification payload is still displayed by the operating system.
  } on PlatformException {
    // Native Firebase resources may be absent in builds without push setup.
  }
}
