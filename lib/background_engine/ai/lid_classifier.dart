import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:flutter/services.dart';
import '../../core/audio/pcm_codec.dart';
import '../../features/transcription/domain/interfaces/onnx_processor.dart';

/// Implements Language Identification using the Meta MMS-LID ONNX model.
class LidClassifier implements OnnxProcessor<Uint8List, String> {
  final String modelPath;
  OrtSession? _session;
  
  // OFFICIAL Meta MMS-LID-126 Index Mapping (Verified from facebook/mms-lid-126 config.json)
  static const Map<int, String> _idToLang = {
    0: "ara", 1: "cmn", 2: "eng", 3: "spa", 4: "fra", 5: "mlg", 6: "swe", 7: "por", 
    8: "vie", 9: "ful", 10: "sun", 11: "asm", 12: "ben", 13: "zlm", 14: "kor", 15: "ind", 
    16: "hin", 17: "tuk", 18: "urd", 19: "aze", 20: "slv", 21: "mon", 22: "hau", 23: "tel", 
    24: "swh", 25: "bod", 26: "rus", 27: "tur", 28: "heb", 29: "mar", 30: "som", 31: "tgl", 
    32: "tat", 33: "tha", 34: "cat", 35: "ron", 36: "mal", 37: "bel", 38: "pol", 39: "yor", 
    40: "nld", 41: "bul", 42: "hat", 43: "afr", 44: "isl", 45: "amh", 46: "tam", 47: "hun", 
    48: "hrv", 49: "lit", 50: "cym", 51: "fas", 52: "mkd", 53: "ell", 54: "bos", 55: "deu", 
    56: "sqi", 57: "jav", 58: "nob", 59: "uzb", 60: "snd", 61: "lat", 62: "nya", 63: "grn", 
    64: "mya", 65: "orm", 66: "lin", 67: "hye", 68: "yue", 69: "pan", 70: "jpn", 71: "kaz", 
    72: "npi", 73: "kat", 74: "guj", 75: "kan", 76: "tgk", 77: "ukr", 78: "ces", 79: "lav", 
    80: "bak", 81: "khm", 82: "fao", 83: "glg", 84: "ltz", 85: "lao", 86: "mlt", 87: "sin", 
    88: "sna", 89: "ita", 90: "srp", 91: "mri", 92: "nno", 93: "pus", 94: "eus", 95: "ory", 
    96: "lug", 97: "bre", 98: "luo", 99: "slk", 100: "fin", 101: "dan", 102: "yid", 103: "est", 
    104: "ceb", 105: "war", 106: "san", 107: "kir", 108: "oci", 109: "wol", 110: "haw", 111: "kam", 
    112: "umb", 113: "xho", 114: "epo", 115: "zul", 116: "ibo", 117: "abk", 118: "ckb", 119: "nso", 
    120: "gle", 121: "kea", 122: "ast", 123: "sco", 124: "glv", 125: "ina"
  };

  LidClassifier({this.modelPath = 'assets/models/mms_lid.onnx'});

  @override
  Future<void> loadModel() async {
    Uint8List bytes;
    try {
      final rawModel = await rootBundle.load(modelPath);
      bytes = rawModel.buffer.asUint8List();
    } catch (e) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final assetPath = "$exeDir/data/flutter_assets/$modelPath";
      final file = File(assetPath);
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      } else {
        final debugFile = File(modelPath);
        if (await debugFile.exists()) {
          bytes = await debugFile.readAsBytes();
        } else {
          throw Exception("LID Model not found");
        }
      }
    }
    
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromBuffer(bytes, sessionOptions);
  }

  @override
  Future<String> infer(Uint8List pcmBytes) async {
    if (_session == null) throw Exception("LID Session not initialized");

    // Legacy entrypoint during migration; canonical path should call inferFromFloat32.
    final floatList = PcmCodec.pcm16LeToFloat32(pcmBytes);
    return _inferFromFloat32(floatList);
  }

  Future<String> inferFromFloat32(Float32List floatList) async {
    if (_session == null) throw Exception("LID Session not initialized");
    final predictions = await inferTopKFromFloat32(floatList, k: 1);
    return predictions.first.language;
  }

  Future<List<LanguagePrediction>> inferTopKFromFloat32(
    Float32List floatList, {
    int k = 5,
  }) async {
    if (_session == null) throw Exception("LID Session not initialized");
    return _inferTopKFromFloat32(floatList, k: k);
  }

  Future<String> _inferFromFloat32(Float32List floatList) async {
    if (_session == null) throw Exception("LID Session not initialized");
    final predictions = await _inferTopKFromFloat32(floatList, k: 1);
    return predictions.first.language;
  }

  Future<List<LanguagePrediction>> _inferTopKFromFloat32(
    Float32List floatList, {
    required int k,
  }) async {
    if (_session == null) throw Exception("LID Session not initialized");
    
    try {
      final inputValues = _normalizeWav2Vec2Input(floatList);
      final shape = [1, inputValues.length];
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputValues,
        shape
      );
      
      final inputs = {'input_values': inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);
      
      List<LanguagePrediction> predictions = const [
        LanguagePrediction(language: 'eng', score: 0),
      ];
      
      if (outputs.isNotEmpty && outputs[0] != null) {
          final row = _firstLogitRow(outputs[0]!.value);
          final ranked = <LanguagePrediction>[];
          for (int i = 0; i < row.length; i++) {
            ranked.add(
              LanguagePrediction(
                language: _idToLang[i] ?? 'LID_$i',
                score: row[i],
              ),
            );
          }
          ranked.sort((a, b) => b.score.compareTo(a.score));
          predictions = ranked.take(k.clamp(1, ranked.length)).toList(growable: false);
      }

      inputTensor.release();
      runOptions.release();
      for (var element in outputs) {
        element?.release();
      }

      return predictions;
    } catch (e) {
      print("LID Inference Error: $e");
      return const [LanguagePrediction(language: 'eng', score: 0)];
    }
  }

  Float32List _normalizeWav2Vec2Input(Float32List samples) {
    if (samples.isEmpty) return samples;

    double sum = 0;
    for (final sample in samples) {
      sum += sample;
    }
    final mean = sum / samples.length;

    double variance = 0;
    for (final sample in samples) {
      final centered = sample - mean;
      variance += centered * centered;
    }
    final scale = sqrt((variance / samples.length) + 1e-7);

    final normalized = Float32List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      normalized[i] = (samples[i] - mean) / scale;
    }
    return normalized;
  }

  List<double> _firstLogitRow(Object? value) {
    if (value is List<List<double>>) {
      return value.first;
    }
    if (value is List<List<num>>) {
      return value.first.map((v) => v.toDouble()).toList(growable: false);
    }
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is List) {
        return first.map((v) => (v as num).toDouble()).toList(growable: false);
      }
      return value.map((v) => (v as num).toDouble()).toList(growable: false);
    }
    throw StateError('Unexpected LID logits type: ${value.runtimeType}');
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
  }
}

class LanguagePrediction {
  final String language;
  final double score;

  const LanguagePrediction({
    required this.language,
    required this.score,
  });

  @override
  String toString() => '$language(${score.toStringAsFixed(3)})';
}
