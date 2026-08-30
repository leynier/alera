import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// Records provider failures.
///
/// Most of the app's async work runs inside providers, so a failure there is
/// the broadest signal available. Without this it only ever surfaces as an
/// `AsyncError` rendered by some widget, and is gone once the screen changes.
final class const LoggingProviderObserver() extends ProviderObserver {
  static final Logger _logger = Logger('Providers');

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final provider = context.provider;
    _logger.severe(
      'provider ${provider.name ?? provider.runtimeType} failed',
      error,
      stackTrace,
    );
  }
}
