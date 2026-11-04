import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/hosts/domain/pairing_offer.dart';
import 'package:alera_mobile/src/features/runtime/domain/connection_attempt.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

const _deviceName = 'Alera Agent QA';
const _fixturePrefix = 'ALERA-QA-';
const _budget = Duration(seconds: 60);
const _cleanupReserve = Duration(seconds: 15);

void main() {
  final environment = Platform.environment;
  final offerPath = environment['ALERA_QA_PAIRING_OFFER_FILE'];
  test(
    'Live mobile pairing, agent chat snapshots, and cursor event parity',
    () => HttpOverrides.runWithHttpOverrides(
      () => _runAcceptance(environment),
      _LiveGatewayHttpOverrides(),
    ),
    skip: offerPath == null || offerPath.trim().isEmpty
        ? 'Opt in with a private ALERA_QA_PAIRING_OFFER_FILE.'
        : false,
    timeout: const Timeout(_budget),
  );
}

// Flutter's test HTTP override rejects real network traffic. This override is
// confined to the opted-in test; the pairing endpoint is checked before use.
final class _LiveGatewayHttpOverrides extends HttpOverrides {}

Future<void> _runAcceptance(Map<String, String> environment) async {
  final clock = Stopwatch()..start();
  var phase = 'input validation';
  MobileRuntimeClient? client;
  StreamSubscription<MobileRuntimeEvent>? rawSubscription;
  StreamSubscription<AgentChatStreamEvent>? chatSubscription;
  RuntimeAgentChatRepository? repository;
  AgentChatRef? chat;
  File? cleanupFile;
  String? deviceId;
  String? originalTitle;
  var renameAttempted = false;
  var titleRestored = false;
  Object? failure;

  Duration remaining({bool cleanup = false}) {
    final duration =
        _budget - clock.elapsed - (cleanup ? Duration.zero : _cleanupReserve);
    if (duration <= Duration.zero) {
      throw TimeoutException('Live mobile QA deadline reached.');
    }
    return duration;
  }

  Future<T> bounded<T>(Future<T> operation, {bool cleanup = false}) =>
      operation.timeout(remaining(cleanup: cleanup));

  Future<void> writeCleanup() async {
    if (cleanupFile == null || deviceId == null) return;
    await bounded(
      cleanupFile.writeAsString(
        jsonEncode(<String, Object?>{
          'deviceId': deviceId,
          'deviceName': _deviceName,
          'chatId': chat?.chatId,
          'workspaceId': chat?.workspaceId,
          'originalTitle': originalTitle,
          'renameAttempted': renameAttempted,
          'titleRestored': titleRestored,
        }),
        flush: true,
      ),
      cleanup: true,
    );
  }

  try {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw StateError('Private POSIX files are required for live mobile QA.');
    }
    String requiredInput(String key) {
      final value = environment[key]?.trim();
      if (value == null || value.isEmpty) {
        throw StateError('Missing live mobile QA input: $key.');
      }
      return value;
    }

    chat = AgentChatRef(
      chatId: requiredInput('ALERA_QA_CHAT_ID'),
      workspaceId: requiredInput('ALERA_QA_WORKSPACE_ID'),
    );
    if (!chat.workspaceId.startsWith('qa-workspace-')) {
      throw StateError('The workspace must be a dedicated QA fixture.');
    }
    final offerFile = File(requiredInput('ALERA_QA_PAIRING_OFFER_FILE'));
    cleanupFile = File(requiredInput('ALERA_QA_CLEANUP_FILE'));
    await _requirePrivateFile(offerFile);
    await _requirePrivateFile(cleanupFile);
    if (await cleanupFile.length() != 0) {
      throw StateError('The cleanup receipt must be an empty private file.');
    }
    final offer = PairingOffer.parse(await offerFile.readAsString());
    final endpoint = Uri.parse(offer.endpoint);
    if (endpoint.scheme != 'ws' ||
        endpoint.host != '127.0.0.1' ||
        !endpoint.hasPort ||
        endpoint.port == 0 ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw StateError('The pairing offer must use a loopback QA gateway.');
    }

    phase = 'pairing';
    final pairing = ConnectionAttempt(timeout: const Duration(seconds: 25));
    final credentials = await pairing
        .run(() async {
          final result = await MobileRuntimeClient.pairDevice(
            offer,
            deviceName: _deviceName,
          );
          deviceId = result.deviceId;
          await writeCleanup();
          return result;
        })
        .whenComplete(pairing.cancel);
    expect(credentials.runtimeId, offer.runtimeId);
    expect(credentials.displayName, _deviceName);

    phase = 'connect and authenticate';
    final connectedClient = await bounded(
      MobileRuntimeClient.connect(
        offer.endpoint,
        connectTimeout: const Duration(seconds: 5),
      ),
    );
    client = connectedClient;
    final hello = await bounded(
      connectedClient.authenticate(
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
      ),
    );
    expect(hello['runtimeCapabilities'], contains(AgentChatWire.capability));
    expect(
      connectedClient.runtimeCapabilities,
      contains(AgentChatWire.capability),
    );

    final observed = _ObservedTransport(
      MobileAgentChatTransport(connectedClient),
      () {
        final available = remaining();
        return available < const Duration(seconds: 5)
            ? available
            : const Duration(seconds: 5);
      },
    );
    repository = RuntimeAgentChatRepository(observed);
    final rawChanges = <int, Map<String, Object?>>{};
    final changes = <int, AgentChatChange>{};
    rawSubscription = connectedClient.events.listen((event) {
      if (event.name == AgentChatWire.changedEvent &&
          event.payload['chatId'] == chat!.chatId) {
        final cursor = event.payload['cursor'];
        if (cursor is int) rawChanges[cursor] = event.payload;
      }
    });
    chatSubscription = repository.watch(chat.chatId).listen((event) {
      if (event case AgentChatChangeReceived(:final change)) {
        changes[change.cursor] = change;
      }
    });

    phase = 'providers and chat list';
    expect(await repository.supported(), isTrue);
    final providers = await repository.providers(workspaceId: chat.workspaceId);
    final listed = await repository.list(workspaceId: chat.workspaceId);
    expect(providers, isNotEmpty);
    final summary = listed.singleWhere((entry) => entry.chatId == chat!.chatId);
    expect(summary.workspaceId, chat.workspaceId);
    expect(summary.title.startsWith(_fixturePrefix), isTrue);

    phase = 'snapshot and wire parsing';
    final before = await repository.snapshot(chat);
    _verifyParsedSnapshot(before, observed.lastSnapshot!);
    expect(before.chatId, chat.chatId);
    expect(before.workspaceId, chat.workspaceId);
    expect(before.title.startsWith(_fixturePrefix), isTrue);
    expect(before.archived, isFalse);
    expect(before.session.status, AgentChatSessionStatus.ready);
    expect(before.session.busy, isFalse);
    expect(before.pendingRequests, isEmpty);
    expect(before.queue, isEmpty);
    originalTitle = before.title;
    await writeCleanup();

    phase = 'temporary rename and live cursor event';
    final temporaryTitle = 'ALERA-QA-Mobile-${const Uuid().v4()}';
    renameAttempted = true;
    await writeCleanup();
    expect(
      await repository.rename(
        chat,
        requestId: const Uuid().v4(),
        title: temporaryTitle,
      ),
      temporaryTitle,
    );
    final nextCursor = before.cursor + 1;
    await _waitUntil(
      () =>
          changes.containsKey(nextCursor) && rawChanges.containsKey(nextCursor),
      remaining,
    );
    final change = changes[nextCursor]!;
    expect(change.workspaceId, chat.workspaceId);
    expect(change.title, temporaryTitle);
    final wireDelta = rawChanges[nextCursor]!['delta']! as Map;
    expect(wireDelta['title'], change.title);
    final outcome = AgentChatThread.fromSnapshot(before).apply(change);
    expect(outcome, isA<AgentChatApplied>());
    final reduced = (outcome as AgentChatApplied).thread.snapshot;
    final after = await repository.snapshot(chat);
    expect(after.cursor, nextCursor);
    expect(after.title, reduced.title);
    expect(
      after.pendingRequests.map((request) => request.id),
      reduced.pendingRequests.map((request) => request.id),
    );
    expect(
      after.turns.map((turn) => turn.id),
      reduced.turns.map((turn) => turn.id),
    );
  } on Object catch (error) {
    // Do not let exceptions containing a pairing payload or credential reach
    // the test reporter. Keep the phase and type, never the peer's message.
    failure = TestFailure(
      'Live mobile QA failed at $phase '
      '(${error.runtimeType}). See the private cleanup receipt.',
    );
  } finally {
    if (renameAttempted && originalTitle != null && repository != null) {
      try {
        // Cleanup uses the same real transport with its own remaining budget.
        final cleanupRepository = RuntimeAgentChatRepository(
          _ObservedTransport(MobileAgentChatTransport(client!), () {
            final available = remaining(cleanup: true);
            return available < const Duration(seconds: 5)
                ? available
                : const Duration(seconds: 5);
          }),
        );
        await cleanupRepository.rename(
          chat!,
          requestId: const Uuid().v4(),
          title: originalTitle,
        );
        final restored = await cleanupRepository.snapshot(chat);
        titleRestored = restored.title == originalTitle;
        if (!titleRestored) throw StateError('QA title restoration failed.');
      } on Object catch (error) {
        failure ??= TestFailure(
          'Live mobile QA title cleanup failed '
          '(${error.runtimeType}). Restore it using the private receipt.',
        );
      }
    }
    try {
      await writeCleanup();
    } on Object {
      failure ??= TestFailure(
        'Live mobile QA cleanup receipt could not be written.',
      );
    }
    await rawSubscription?.cancel();
    await chatSubscription?.cancel();
    await client?.dispose();
  }
  if (failure != null) throw failure;
  debugPrint(
    'Live mobile QA checks: pair, authenticate, agentChatV1, providers, '
    'list, snapshot parsing, rename event, cursor parity, title restored.',
  );
  debugPrint(
    'Live mobile QA deviceId: $deviceId; cleanup: ${cleanupFile!.path}',
  );
}

Future<void> _requirePrivateFile(File file) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  final stat = await file.stat();
  if (type != FileSystemEntityType.file || stat.mode & 0x1ff != 0x180) {
    throw StateError('Live mobile QA inputs require regular mode 600 files.');
  }
}

Future<void> _waitUntil(
  bool Function() ready,
  Duration Function() remaining,
) async {
  while (!ready()) {
    remaining();
    await Future.pause(const Duration(milliseconds: 10));
  }
}

void _verifyParsedSnapshot(
  AgentChatSnapshot snapshot,
  Map<String, Object?> wire,
) {
  final requests = wire['pendingRequests']! as List;
  final turns = wire['turns']! as List;
  expect(snapshot.pendingRequests.length, requests.length);
  expect(snapshot.turns.length, turns.length);
  expect(
    snapshot.pendingRequests.map((request) => request.id),
    requests.map((request) => (request as Map)['requestId'] ?? request['id']),
  );
  expect(
    snapshot.turns.map((turn) => turn.id),
    turns.map((turn) => (turn as Map)['turnId'] ?? turn['id']),
  );
}

final class _ObservedTransport(
  final AgentChatTransport delegate,
  final Duration Function() requestTimeout,
) implements AgentChatTransport {
  Map<String, Object?>? lastSnapshot;

  @override
  Stream<AgentChatTransportEvent> get events => delegate.events;

  @override
  Future<bool> supportsCapability(String capability) =>
      delegate.supportsCapability(capability);

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final result = await delegate.request(
      type,
      payload,
      timeout: requestTimeout(),
    );
    if (type == AgentChatWire.snapshot) lastSnapshot = result;
    return result;
  }
}
