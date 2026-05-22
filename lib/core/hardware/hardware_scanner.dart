import 'dart:io';

enum PerformanceTier { edge, standard, high }

class HardwareCapabilityProfile {
  final String os;
  final PerformanceTier tier;
  final List<String> preferredExecutionProviders;
  final bool gpuAvailable;
  final bool npuAvailable;

  const HardwareCapabilityProfile({
    required this.os,
    required this.tier,
    required this.preferredExecutionProviders,
    required this.gpuAvailable,
    required this.npuAvailable,
  });
}

abstract class HardwareScanner {
  Future<HardwareCapabilityProfile> scan();
  Future<PerformanceTier> getTier();
  Future<String> getExecutionProvider();
  Future<Map<String, dynamic>> getHardwareSpecs();
}

class WindowsHardwareScanner implements HardwareScanner {
  @override
  Future<HardwareCapabilityProfile> scan() async {
    return const HardwareCapabilityProfile(
      os: 'Windows',
      tier: PerformanceTier.high,
      preferredExecutionProviders: <String>['oneAPI_SYCL', 'OpenVINO', 'DirectML', 'CPU'],
      gpuAvailable: true,
      npuAvailable: true,
    );
  }

  @override
  Future<PerformanceTier> getTier() async => (await scan()).tier;

  @override
  Future<String> getExecutionProvider() async => (await scan()).preferredExecutionProviders.first;

  @override
  Future<Map<String, dynamic>> getHardwareSpecs() async {
    final p = await scan();
    return <String, dynamic>{
      'os': p.os,
      'accelerator': p.preferredExecutionProviders.first,
      'providers': p.preferredExecutionProviders,
      'gpu': p.gpuAvailable,
      'npu': p.npuAvailable,
    };
  }
}

class MacHardwareScanner implements HardwareScanner {
  @override
  Future<HardwareCapabilityProfile> scan() async {
    return const HardwareCapabilityProfile(
      os: 'macOS',
      tier: PerformanceTier.high,
      preferredExecutionProviders: <String>['CoreML', 'CPU'],
      gpuAvailable: true,
      npuAvailable: true,
    );
  }

  @override
  Future<PerformanceTier> getTier() async => (await scan()).tier;

  @override
  Future<String> getExecutionProvider() async => (await scan()).preferredExecutionProviders.first;

  @override
  Future<Map<String, dynamic>> getHardwareSpecs() async {
    final p = await scan();
    return <String, dynamic>{
      'os': p.os,
      'accelerator': p.preferredExecutionProviders.first,
      'providers': p.preferredExecutionProviders,
      'gpu': p.gpuAvailable,
      'npu': p.npuAvailable,
    };
  }
}

class LinuxHardwareScanner implements HardwareScanner {
  @override
  Future<HardwareCapabilityProfile> scan() async {
    return const HardwareCapabilityProfile(
      os: 'Linux',
      tier: PerformanceTier.high,
      preferredExecutionProviders: <String>['OpenVINO', 'DirectML', 'CPU'],
      gpuAvailable: true,
      npuAvailable: false,
    );
  }

  @override
  Future<PerformanceTier> getTier() async => (await scan()).tier;

  @override
  Future<String> getExecutionProvider() async => (await scan()).preferredExecutionProviders.first;

  @override
  Future<Map<String, dynamic>> getHardwareSpecs() async {
    final p = await scan();
    return <String, dynamic>{
      'os': p.os,
      'accelerator': p.preferredExecutionProviders.first,
      'providers': p.preferredExecutionProviders,
      'gpu': p.gpuAvailable,
      'npu': p.npuAvailable,
    };
  }
}

class HardwareScannerFactory {
  static HardwareScanner getScanner() {
    if (Platform.isWindows) return WindowsHardwareScanner();
    if (Platform.isMacOS || Platform.isIOS) return MacHardwareScanner();
    return LinuxHardwareScanner();
  }
}
