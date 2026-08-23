import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:alera_mobile/src/features/ai_dictation/domain/speech_model_descriptor.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MobileAiDictationModel extends SpeechModelDescriptor {
  MobileAiDictationModel({
    required super.id,
    required super.label,
    required super.description,
    String? fileName,
    String? uri,
    String? sha256,
    int? sizeBytes,
    List<SpeechModelArtifact>? artifacts,
    super.languages = const <String>[],
    super.supportsAutomaticLanguageDetection = true,
    super.supportsInitialPrompt = true,
    super.supportedProviders = const <SpeechExecutionProvider>{
      SpeechExecutionProvider.cpu,
    },
    super.preferredProvider,
    super.storageVersion = 1,
    super.runtime = SpeechModelRuntime.whisperCpp,
    super.mode = SpeechRecognitionMode.batch,
  }) : super(
         artifacts:
             artifacts ??
             <SpeechModelArtifact>[
               SpeechModelArtifact(
                 id: 'primary',
                 relativePath: fileName!,
                 uri: uri!,
                 sha256: sha256!,
                 sizeBytes: sizeBytes!,
               ),
             ],
       );

  SpeechModelArtifact get primaryArtifact => artifacts.first;
  String get fileName => primaryArtifact.relativePath;
  String get uri => primaryArtifact.uri;
  String get sha256 => primaryArtifact.sha256;
  int get sizeBytes => primaryArtifact.sizeBytes;
  int get totalBytes =>
      artifacts.fold<int>(0, (total, artifact) => total + artifact.sizeBytes);
}

class MobileAiDictationModelStore {
  MobileAiDictationModelStore({
    http.Client Function()? clientFactory,
    Future<Directory> Function()? supportDirectory,
    List<MobileAiDictationModel>? catalog,
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _supportDirectory =
           supportDirectory ?? (() => getApplicationSupportDirectory()),
       catalog = catalog ?? models;

  static final models = <MobileAiDictationModel>[
    MobileAiDictationModel(
      id: 'whisper-tiny',
      label: 'Whisper Tiny',
      description: 'Fastest and lightest, with lower accuracy.',
      fileName: 'ggml-tiny.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      sizeBytes: 77691713,
    ),
    MobileAiDictationModel(
      id: 'whisper-base',
      label: 'Whisper Base',
      description: 'Balanced speed and accuracy. Recommended.',
      fileName: 'ggml-base.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
      sizeBytes: 147951465,
    ),
    MobileAiDictationModel(
      id: 'whisper-small',
      label: 'Whisper Small',
      description: 'More accurate, with higher memory and battery use.',
      fileName: 'ggml-small.bin',
      uri:
          'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
      sizeBytes: 487601967,
    ),
  ];

  final http.Client Function() _clientFactory;
  final Future<Directory> Function() _supportDirectory;
  final List<MobileAiDictationModel> catalog;
  http.Client? _activeClient;
  String? _activeModelId;
  Completer<void>? _activeFinished;
  bool _cancelRequested = false;

  MobileAiDictationModel modelFor(String id) => catalog.firstWhere(
    (model) => model.id == id,
    orElse: () => catalog.firstWhere((model) => model.id == 'whisper-base'),
  );

  Future<Directory> _modelRoot(String id) async {
    final support = await _supportDirectory();
    return Directory(p.join(support.path, 'models', 'ai-dictation', id));
  }

  Future<Directory> _versionDirectory(String id) async {
    final model = modelFor(id);
    return Directory(
      p.join((await _modelRoot(id)).path, '${model.storageVersion}'),
    );
  }

  Future<Directory> _stagingDirectory(String id) async {
    final model = modelFor(id);
    return Directory(
      p.join((await _modelRoot(id)).path, '${model.storageVersion}.installing'),
    );
  }

  Future<String> artifactPath(String id, SpeechModelArtifact artifact) async {
    return p.join((await _versionDirectory(id)).path, artifact.relativePath);
  }

  Future<String> modelPath(String id) async =>
      artifactPath(id, modelFor(id).primaryArtifact);

  Future<String> partialPath(String id) async {
    final model = modelFor(id);
    final root = model.artifacts.length == 1
        ? (await _versionDirectory(id)).path
        : (await _stagingDirectory(id)).path;
    return p.join(root, '${model.primaryArtifact.relativePath}.part');
  }

  Future<String> intentPath(String id) async => p.join(
    (await _modelRoot(id)).path,
    '${modelFor(id).storageVersion}.resume.json',
  );

  Future<bool> isInstalled(String id) async {
    final model = modelFor(id);
    final directory = await _versionDirectory(id);
    final marker = File(p.join(directory.path, '.installed.json'));
    if (model.artifacts.length == 1) {
      final artifact = model.primaryArtifact;
      final destination = File(p.join(directory.path, artifact.relativePath));
      final legacyMarker = File('${destination.path}.sha256');
      if (!await destination.exists() ||
          await destination.length() != artifact.sizeBytes) {
        return false;
      }
      final markerFile = await marker.exists() ? marker : legacyMarker;
      if (!await markerFile.exists()) return false;
      final markerValue = await markerFile.readAsString();
      return markerValue.trim() == artifact.sha256 ||
          markerValue.contains('"${artifact.sha256}"');
    }
    if (!await marker.exists()) return false;
    return _verifyRoot(model, directory);
  }

  Future<int> partialBytes(String id) async {
    final model = modelFor(id);
    final root = model.artifacts.length == 1
        ? (await _versionDirectory(id)).path
        : (await _stagingDirectory(id)).path;
    var total = 0;
    for (final artifact in model.artifacts) {
      final partial = File(p.join(root, '${artifact.relativePath}.part'));
      if (await partial.exists()) total += await partial.length();
    }
    return total;
  }

  Future<Set<String>> resumableModelIds() async {
    final result = <String>{};
    for (final model in catalog) {
      if (await File(await intentPath(model.id)).exists()) result.add(model.id);
    }
    return result;
  }

  Future<String> download(
    String id, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (_activeClient != null) {
      throw StateError('Another speech model download is already active.');
    }
    final model = modelFor(id);
    final root = model.artifacts.length == 1
        ? (await _versionDirectory(id)).path
        : (await _stagingDirectory(id)).path;
    await Directory(root).create(recursive: true);
    await _writeResumeIntent(model);
    final client = _clientFactory();
    _activeClient = client;
    _activeModelId = id;
    final finished = Completer<void>();
    _activeFinished = finished;
    _cancelRequested = false;
    try {
      final total = model.artifacts.fold<int>(
        0,
        (sum, item) => sum + item.sizeBytes,
      );
      var completed = 0;
      for (final artifact in model.artifacts) {
        if (model.artifacts.length > 1) {
          final installedArtifact = File(p.join(root, artifact.relativePath));
          if (await installedArtifact.exists()) {
            try {
              await _verifyFile(installedArtifact, artifact);
              completed += artifact.sizeBytes;
              onProgress?.call(completed, total);
              continue;
            } on Object {
              if (await installedArtifact.exists()) {
                await installedArtifact.delete();
              }
            }
          }
        }
        final partial = File(p.join(root, '${artifact.relativePath}.part'));
        final received = await _downloadArtifact(
          client,
          artifact,
          partial,
          completed,
          total,
          onProgress,
        );
        completed += received;
        await _verifyFile(partial, artifact);
        if (model.artifacts.length == 1) {
          final destination = File(p.join(root, artifact.relativePath));
          await destination.parent.create(recursive: true);
          if (await destination.exists()) await destination.delete();
          await partial.rename(destination.path);
          await File(
            '${destination.path}.sha256',
          ).writeAsString(artifact.sha256, flush: true);
        } else {
          final destination = File(p.join(root, artifact.relativePath));
          await destination.parent.create(recursive: true);
          await partial.rename(destination.path);
        }
        onProgress?.call(completed, total);
      }
      if (model.artifacts.length > 1) {
        final staging = await _stagingDirectory(id);
        final destination = await _versionDirectory(id);
        await destination.parent.create(recursive: true);
        if (await destination.exists()) {
          await destination.delete(recursive: true);
        }
        await staging.rename(destination.path);
        await File(p.join(destination.path, '.installed.json')).writeAsString(
          jsonEncode(<String, Object?>{
            'modelId': model.id,
            'storageVersion': model.storageVersion,
            'artifacts': {
              for (final artifact in model.artifacts)
                artifact.id: <String, Object?>{
                  'expectedBytes': artifact.sizeBytes,
                  'sha256': artifact.sha256,
                },
            },
          }),
          flush: true,
        );
      }
      final intent = File(await intentPath(id));
      if (await intent.exists()) await intent.delete();
      onProgress?.call(total, total);
      return modelPath(id);
    } on Object {
      if (_cancelRequested) throw const MobileAiModelDownloadCancelled();
      rethrow;
    } finally {
      client.close();
      _activeClient = null;
      _activeModelId = null;
      _activeFinished = null;
      if (!finished.isCompleted) finished.complete();
    }
  }

  Future<void> cancel(String id) async {
    if (_activeModelId == id) {
      _cancelRequested = true;
      _activeClient?.close();
      await _activeFinished?.future;
    }
    final staging = await _stagingDirectory(id);
    final intent = File(await intentPath(id));
    if (await intent.exists()) await intent.delete();
    if (await staging.exists()) await staging.delete(recursive: true);
    final model = modelFor(id);
    if (model.artifacts.length == 1) {
      final version = await _versionDirectory(id);
      for (final artifact in model.artifacts) {
        final partial = File(
          p.join(version.path, '${artifact.relativePath}.part'),
        );
        if (await partial.exists()) await partial.delete();
      }
    }
  }

  Future<void> remove(String id) async {
    await cancel(id);
    final root = await _modelRoot(id);
    if (await root.exists()) await root.delete(recursive: true);
  }

  Future<bool> verify(String id) async => isInstalled(id);

  Future<int> _downloadArtifact(
    http.Client client,
    SpeechModelArtifact artifact,
    File partial,
    int completed,
    int total,
    void Function(int received, int total)? onProgress,
  ) async {
    await partial.parent.create(recursive: true);
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > artifact.sizeBytes) {
      await partial.delete();
      offset = 0;
    }
    if (offset == artifact.sizeBytes) return offset;
    final request = http.Request('GET', Uri.parse(artifact.uri));
    if (offset > 0) request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';
    final response = await client.send(request);
    if (offset > 0 && response.statusCode == HttpStatus.partialContent) {
      _validateContentRange(response, offset, artifact.sizeBytes);
    } else if (offset > 0) {
      if (await partial.exists()) await partial.delete();
      offset = 0;
    }
    if (!<int>[
      HttpStatus.ok,
      HttpStatus.partialContent,
    ].contains(response.statusCode)) {
      throw HttpException(
        'Model download failed with HTTP ${response.statusCode}.',
      );
    }
    final sink = partial.openWrite(
      mode: offset == 0 ? FileMode.write : FileMode.append,
    );
    var received = offset;
    try {
      await for (final chunk in response.stream) {
        if (_cancelRequested) throw const MobileAiModelDownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(completed + received, total);
      }
    } finally {
      await sink.close();
    }
    return received;
  }

  Future<void> _writeResumeIntent(SpeechModelDescriptor model) async {
    final intent = File(await intentPath(model.id));
    await intent.parent.create(recursive: true);
    await intent.writeAsString(
      jsonEncode(<String, Object?>{
        'modelId': model.id,
        'storageVersion': model.storageVersion,
        'artifacts': {
          for (final artifact in model.artifacts)
            artifact.id: <String, Object?>{
              'expectedBytes': artifact.sizeBytes,
              'sha256': artifact.sha256,
            },
        },
      }),
      flush: true,
    );
  }

  Future<void> _verifyFile(File file, SpeechModelArtifact artifact) async {
    if (!await file.exists() || await file.length() != artifact.sizeBytes) {
      throw StateError(
        'The model artifact download ended before it was complete.',
      );
    }
    final digest = await Isolate.run(
      () async => (await sha256.bind(file.openRead()).first).toString(),
    );
    if (digest != artifact.sha256) {
      await file.delete();
      throw StateError('The downloaded model artifact failed verification.');
    }
  }

  Future<bool> _verifyRoot(
    SpeechModelDescriptor model,
    Directory directory,
  ) async {
    for (final artifact in model.artifacts) {
      final file = File(p.join(directory.path, artifact.relativePath));
      try {
        await _verifyFile(file, artifact);
      } on Object {
        return false;
      }
    }
    return true;
  }
}

class MobileAiModelDownloadCancelled implements Exception {
  const MobileAiModelDownloadCancelled();
}

void _validateContentRange(
  http.StreamedResponse response,
  int expectedStart,
  int expectedTotal,
) {
  final value = response.headers[HttpHeaders.contentRangeHeader];
  final match = value == null
      ? null
      : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
  if (match == null ||
      int.parse(match.group(1)!) != expectedStart ||
      int.parse(match.group(3)!) != expectedTotal) {
    throw const HttpException('The model resume response was invalid.');
  }
}
