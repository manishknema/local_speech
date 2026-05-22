import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

enum PerformanceTier {
  edge,     // < 4GB RAM, Low power
  standard, // 4-8GB RAM
  high      // > 8GB RAM, High power
}

class HardwareProfileManager {
  static final HardwareProfileManager _instance = HardwareProfileManager._internal();
  factory HardwareProfileManager() => _instance;
  HardwareProfileManager._internal();

  /// Probes host OS for specs to determine performance tier
  Future<PerformanceTier> getPerformanceTier() async {
    // Note: Accurate RAM detection in Flutter/Dart often requires platform-specific 
    // code or the 'system_info_plus' package. For this Phase 1, we use 
    // a simplified architecture probe.
    
    if (Platform.isAndroid || Platform.isIOS) {
      return PerformanceTier.edge;
    }
    
    // Windows/Desktop default
    return PerformanceTier.standard;
  }

  /// Determines which ONNX Execution Provider to use for acceleration
  String getExecutionProvider() {
    if (Platform.isMacOS || Platform.isIOS) {
      return "CoreML";
    } else if (Platform.isWindows) {
      return "DirectML";
    } else if (Platform.isAndroid) {
      return "NNAPI";
    }
    return "CPU";
  }

  String getArchitecture() {
    return Platform.version.contains('arm64') ? 'ARM64' : 'x86_64';
  }
}
