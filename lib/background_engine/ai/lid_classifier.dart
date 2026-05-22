import 'dart:typed_data';
import 'dart:io';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:flutter/services.dart';
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
    final floatList = _normalizeInt16ToFloat32(pcmBytes);
    return _inferFromFloat32(floatList);
  }

  Future<String> inferFromFloat32(Float32List floatList) async {
    if (_session == null) throw Exception("LID Session not initialized");
    return _inferFromFloat32(floatList);
  }

  Future<String> _inferFromFloat32(Float32List floatList) async {
    if (_session == null) throw Exception("LID Session not initialized");
    
    try {
      final shape = [1, floatList.length];
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        floatList, 
        shape
      );
      
      final inputs = {'input_values': inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);
      
      String detectedLang = 'eng'; 
      
      if (outputs.isNotEmpty && outputs[0] != null) {
          final logits = outputs[0]!.value as List<List<double>>;
          final row = logits[0];
          
          // Find ArgMax
          int maxIdx = 0;
          double maxVal = -double.infinity;
          for (int i = 0; i < row.length; i++) {
            if (row[i] > maxVal) {
              maxVal = row[i];
              maxIdx = i;
            }
          }
          
          detectedLang = _idToLang[maxIdx] ?? "LID_$maxIdx";
          
      }

      inputTensor.release();
      runOptions.release();
      for (var element in outputs) {
        element?.release();
      }

      return detectedLang;
    } catch (e) {
      print("LID Inference Error: $e");
      return 'eng';
    }
  }

  /// PRO FIX: Safe Int16 -> Float32 Normalization
  Float32List _normalizeInt16ToFloat32(Uint8List bytes) {
    final byteData = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final count = bytes.length ~/ 2;
    final float32 = Float32List(count);
    
    for (int i = 0; i < count; i++) {
      // Explicitly read as Little Endian Int16
      final int sample = byteData.getInt16(i * 2, Endian.little);
      // Precise scale to [-1.0, 1.0]
      float32[i] = sample / 32768.0;
    }
    return float32;
  }

  @override
  void dispose() {
    _session?.release();
    _session = null;
  }
}
