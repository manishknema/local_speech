import 'dart:io';

class SherpaRuntimeLocator {
  const SherpaRuntimeLocator._();

  static String? locateWindowsRuntimeDir() {
    final candidates = <String>[
      'assets/runtime/sherpa/windows',
      '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\assets\\runtime\\sherpa\\windows',
      '${Directory.current.path}\\assets\\runtime\\sherpa\\windows',
    ];

    for (final candidate in candidates) {
      final dir = Directory(candidate);
      if (!dir.existsSync()) {
        continue;
      }

      final dll = File('${dir.path}\\sherpa-onnx-c-api.dll');
      final ort = File('${dir.path}\\onnxruntime.dll');
      if (dll.existsSync() && ort.existsSync()) {
        return dir.path;
      }
    }

    return null;
  }
}
