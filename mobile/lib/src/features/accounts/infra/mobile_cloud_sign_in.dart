import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:alera_mobile/src/features/accounts/infra/alera_cloud_api.dart';
import 'package:alera_mobile/src/features/accounts/domain/cloud_account_session.dart';
import 'package:cryptography/cryptography.dart';
import 'package:url_launcher/url_launcher.dart';

class MobileCloudSignIn {
  const MobileCloudSignIn({required this.api, required this.installationId});

  final AleraMobileAuthApi api;
  final String installationId;

  Future<CloudAccountSession> signIn(String provider) async {
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: listener.port,
      path: '/callback/mobile',
    );
    final verifier = _verifier();
    final challenge = base64UrlEncode(
      (await Sha256().hash(utf8.encode(verifier))).bytes,
    ).replaceAll('=', '');
    try {
      final transaction = await api.createMobileAuthTransaction(
        provider: provider,
        redirectUri: redirectUri.toString(),
        codeChallenge: challenge,
        clientId: installationId,
        deviceName: 'Alera Mobile',
      );
      if (!await launchUrl(
        transaction.authorizationUrl,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Could not open the identity provider.');
      }
      final request = await listener.first.timeout(const Duration(minutes: 5));
      final query = request.uri.queryParameters;
      final response = request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<!doctype html><title>Alera</title><p>You can return to Alera.</p>',
        );
      await response.close();
      if (query['state'] != transaction.state) {
        throw StateError('The sign-in callback state is invalid.');
      }
      final code = query['code'];
      if (code == null || code.trim().isEmpty) {
        throw StateError(
          query['error_description'] ?? 'Sign-in was cancelled.',
        );
      }
      return api.exchangeMobileAuth(
        transactionId: transaction.transactionId,
        state: transaction.state,
        code: code,
        codeVerifier: verifier,
      );
    } finally {
      await listener.close(force: true);
    }
  }

  String _verifier() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List<String>.generate(
      64,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
