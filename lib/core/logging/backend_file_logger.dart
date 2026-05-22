import 'dart:io';
import 'package:intl/intl.dart';

enum BackendLogPlatformPolicy {
  enabled,
  disabled,
}

/// Lightweight backend file logger for engine-side diagnostics.
class BackendFileLogger {
  BackendFileLogger._();
  static final BackendFileLogger instance = BackendFileLogger._();

  IOSink? _sink;
  bool _initialized = false;

  BackendLogPlatformPolicy _policyForCurrentPlatform() {
    if (Platform.isAndroid) return BackendLogPlatformPolicy.disabled;
    return BackendLogPlatformPolicy.enabled;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_policyForCurrentPlatform() == BackendLogPlatformPolicy.disabled) {
      _initialized = true;
      return;
    }

    final logDir = Directory('logs/backend');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final now = _nowIst().toIso8601String().replaceAll(':', '-');
    final file = File('${logDir.path}/engine_$now.log');
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _initialized = true;
    log('Backend file logger initialized');
  }

  void log(String message, {String level = 'INFO'}) {
    if (!_initialized || _sink == null) return;
    final ts = _tsFmt.format(_nowIst());
    _sink!.writeln('[$ts IST] [$level] $message');
  }

  Future<void> close() async {
    if (_sink != null) {
      await _sink!.flush();
      await _sink!.close();
      _sink = null;
    }
  }
}
  final DateFormat _tsFmt = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

