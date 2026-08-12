import 'dart:convert';
import 'package:http/http.dart' as http;

class MobileOpenAiCompatibleProvider {
  MobileOpenAiCompatibleProvider({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  Future<String> transcribe(
      {required String baseUrl,
      required String model,
      required String audioPath,
      String? language,
      String? apiKey}) async {
    final parsed = Uri.parse(baseUrl.trim());
    final path = parsed.path.endsWith('/v1')
        ? parsed.path
        : '${parsed.path.replaceFirst(RegExp(r'\/$'), '')}/v1';
    final request = http.MultipartRequest(
        'POST', parsed.replace(path: '$path/audio/transcriptions'))
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audioPath));
    if (language?.trim().isNotEmpty == true)
      request.fields['language'] = language!.trim();
    if (apiKey?.trim().isNotEmpty == true)
      request.headers['Authorization'] = 'Bearer ${apiKey!.trim()}';
    final response =
        await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw StateError('Speech provider returned HTTP ${response.statusCode}.');
    final text = (jsonDecode(body) as Map)['text'];
    if (text is! String || text.trim().isEmpty)
      throw StateError('Speech provider returned no transcription.');
    return text.trim();
  }

  void dispose() => _client.close();
}
