import 'package:flutter/services.dart';

import 'browser_errors.dart';

final class const AleraBrowserNativeChannel({
  final MethodChannel methodChannel = const MethodChannel(
    'dev.leynier.alera/browser',
  ),
  final EventChannel eventChannel = const EventChannel(
    'dev.leynier.alera/browser/events',
  ),
}) {
  Stream<Map<Object?, Object?>> get events => eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map<Object?, Object?>)
      .cast<Map<Object?, Object?>>();

  Future<void> invokeVoid(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => _invoke<void>(method, arguments);

  Future<T?> invoke<T>(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) => _invoke<T>(method, arguments);

  Future<Map<Object?, Object?>> invokeMap(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async =>
      await _invoke<Map<Object?, Object?>>(method, arguments) ??
      <Object?, Object?>{};

  Future<List<Object?>> invokeList(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async => await _invoke<List<Object?>>(method, arguments) ?? <Object?>[];

  Future<T?> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await methodChannel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const AleraBrowserUnsupportedError(
        'native_plugin_unavailable',
        'The Alera browser native plugin is not registered.',
      );
    } on PlatformException catch (error) {
      throw AleraBrowserNativeError(
        error.code,
        error.message ?? 'The native browser operation failed.',
      );
    }
  }
}
