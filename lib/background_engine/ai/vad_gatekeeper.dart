import 'dart:typed_data';
import 'dart:io';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:flutter/services.dart';
import '../../features/transcription/domain/interfaces/onnx_processor.dart';

/// Implements Voice Activity Detection using the Silero VAD ONNX model.
class VadGatekeeper implements OnnxProcessor<Uint8List, bool> {
  final String modelPath;
  OrtSession? _session;
  
  // Silero VAD v4 state [2, 1, 128] float32
  Float32List _hState = Float32List(256); 
  
  VadGatekeeper({this.modelPath = 'assets/models/silero_vad.onnx'});

  @override
  Future<void> loadModel() async {
    _hState = Float32List(256); // Reset state on load
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
           throw Exception("VAD Model not found");
        }
      }
    }
    
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromBuffer(bytes, sessionOptions);
  }

  @override
  Future<bool> infer(Uint8List pcmBytes) async {
    if (_session == null) throw Exception("VAD Session not initialized");

    // PRODUCTION FIX: Precise Normalization using ByteData view to avoid alignment issues
    final floatList = _normalizeInt16ToFloat32(pcmBytes);
    
    // Silero VAD v4 requires exactly 512, 1024, or 1536 samples.
    if (floatList.length < 512) return false;

    try {
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        floatList, 
        [1, floatList.length]
      );
      
      final srTensor = OrtValueTensor.createTensorWithDataList(Int64List.fromList([16000]), [1]);
      final stateTensor = OrtValueTensor.createTensorWithDataList(_hState, [2, 1, 128]);
      
      final inputs = {
        'input': inputTensor,
        'sr': srTensor,
        'state': stateTensor,
      };
      
      final runOptions = OrtRunOptions();
      final outputs = _session!.run(runOptions, inputs);
      
      bool isSpeech = false;
      if (outputs.isNotEmpty && outputs[0] != null) {
          final probValue = outputs[0]!.value as List<List<double>>;
          final probability = probValue[0][0];
          isSpeech = probability > 0.4; // Responsive threshold

          // Update internal state from output index 1 [2, 1, 128]
          if (outputs.length > 1 && outputs[1] != null) {
            final newState = outputs[1]!.value as List<dynamic>;
            int idx = 0;
            for (var row in newState) {
              for (var col in row) {
                for (var val in col) {
                  _hState[idx++] = (val as double).toDouble();
                }
              }
            }
          }
      }

      inputTensor.release();
      srTensor.release();
      stateTensor.release();
      runOptions.release();
      for (var element in outputs) {
        element?.release();
      }

      return isSpeech;
    } catch (e) {
      print("VAD Inference Error: $e");
      return false;
    }
  }

  /// SURGICAL PRODUCTION FIX:
  /// Use ByteData for byte-perfect Int16 -> Float32 [-1.0, 1.0] extraction.
  Float32List _normalizeInt16ToFloat32(Uint8List bytes) {
    final byteData = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.length);
    final count = bytes.length ~/ 2;
    final float32 = Float32List(count);
    
    for (int i = 0; i < count; i++) {
      // Explicitly read as Little Endian Int16 (standard PCM)
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
