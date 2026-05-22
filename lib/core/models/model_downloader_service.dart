import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class ModelDownloaderService {
  static final ModelDownloaderService _instance = ModelDownloaderService._internal();
  factory ModelDownloaderService() => _instance;
  ModelDownloaderService._internal();

  static const String _manifestPath = 'assets/models/models_manifest.json';
  static const String _modelsDirPath = 'assets/models';
  Map<String, _ModelEntry>? _modelsByName;

  Future<Map<String, _ModelEntry>> _loadModelMap() async {
    if (_modelsByName != null) return _modelsByName!;
    final file = File(_manifestPath);
    if (!file.existsSync()) {
      throw Exception('Model manifest not found at $_manifestPath');
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final models = (raw['models'] as List<dynamic>)
        .map((e) => _ModelEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    _modelsByName = {for (final m in models) m.name: m};
    return _modelsByName!;
  }

  Future<List<String>> requiredModelNames() async {
    final map = await _loadModelMap();
    return map.keys.toList(growable: false);
  }

  Future<String> getModelPath(String modelName) async {
    final map = await _loadModelMap();
    final model = map[modelName];
    if (model == null) throw Exception('Unknown model: $modelName');
    return '$_modelsDirPath/${model.fileName}';
  }

  Future<bool> isModelPresent(String modelName) async {
    final path = await getModelPath(modelName);
    return File(path).existsSync();
  }

  Future<Map<String, bool>> ensureModelsCached() async {
    final map = await _loadModelMap();
    final results = <String, bool>{};
    for (final entry in map.entries) {
      final name = entry.key;
      final model = entry.value;
      final path = await getModelPath(name);
      final file = File(path);
      bool ok = file.existsSync();
      if (ok && model.sha256.isNotEmpty) {
        ok = await _verifyChecksum(file, model.sha256);
      }
      if (!ok) {
        await for (final _ in downloadModel(name)) {}
      }
      if (model.sha256.isNotEmpty) {
        results[name] = await _verifyChecksum(File(path), model.sha256);
      } else {
        results[name] = File(path).existsSync();
      }
    }
    return results;
  }

  Stream<double> downloadModel(String modelName) async* {
    final map = await _loadModelMap();
    final model = map[modelName];
    if (model == null) throw Exception('Unknown model: $modelName');

    final savePath = await getModelPath(modelName);
    final file = File(savePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    final client = http.Client();
    final request = http.Request('GET', Uri.parse(model.url));
    final response = await client.send(request);

    if (response.statusCode != 200) {
      throw Exception("Failed to download $modelName: ${response.statusCode}");
    }

    final int totalBytes = response.contentLength ?? 0;
    int receivedBytes = 0;

    final List<int> bytes = [];
    await for (var chunk in response.stream) {
      bytes.addAll(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) {
        yield receivedBytes / totalBytes;
      }
    }

    await file.writeAsBytes(bytes);
    if (model.sha256.isNotEmpty) {
      final valid = await _verifyChecksum(file, model.sha256);
      if (!valid) {
        throw Exception('Checksum mismatch for $modelName');
      }
    }
    client.close();
  }

  Future<bool> _verifyChecksum(File file, String expectedSha256) async {
    if (!file.existsSync()) return false;
    final digest = sha256.convert(await file.readAsBytes()).toString().toLowerCase();
    return digest == expectedSha256.toLowerCase();
  }
}

class _ModelEntry {
  final String name;
  final String fileName;
  final String url;
  final String sha256;

  _ModelEntry({
    required this.name,
    required this.fileName,
    required this.url,
    required this.sha256,
  });

  factory _ModelEntry.fromJson(Map<String, dynamic> json) {
    return _ModelEntry(
      name: json['name'] as String,
      fileName: json['file_name'] as String,
      url: json['url'] as String,
      sha256: (json['sha256'] as String?) ?? '',
    );
  }
}
