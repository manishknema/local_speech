import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../core/logging/backend_file_logger.dart';

class SherpaHelperResponse {
  const SherpaHelperResponse({
    required this.ok,
    this.text = '',
    this.language = 'indic',
    this.error,
  });

  final bool ok;
  final String text;
  final String language;
  final String? error;
}

class SherpaHelperClient {
  Process? _process;
  final Map<String, Completer<SherpaHelperResponse>> _pending = {};
  Completer<void>? _readyCompleter;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  int _requestCounter = 0;

  Future<void> start({
    required String runtimeDir,
    required String modelPath,
    required String tokensPath,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    if (_process != null) {
      return;
    }

    _readyCompleter = Completer<void>();
    BackendFileLogger.instance.log(
      'Starting Sherpa helper process with model=$modelPath tokens=$tokensPath',
    );
    _process = await Process.start(
      'dart',
      [
        'run',
        'tool/sherpa_helper.dart',
        runtimeDir,
        modelPath,
        tokensPath,
      ],
      workingDirectory: Directory.current.path,
      runInShell: true,
    );

    _stdoutSubscription = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine);

    _stderrSubscription = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          BackendFileLogger.instance.log('Sherpa helper stderr: $line', level: 'WARN');
          stderr.writeln('[sherpa-helper] $line');
        });

    await _readyCompleter!.future.timeout(startupTimeout);
    BackendFileLogger.instance.log('Sherpa helper process reported ready');
  }

  Future<SherpaHelperResponse> transcribeSegment(List<int> pcmBytes) async {
    final process = _process;
    if (process == null) {
      throw StateError('Sherpa helper process not started');
    }

    final id = 'req_${DateTime.now().microsecondsSinceEpoch}_${_requestCounter++}_${Random().nextInt(1 << 16)}';
    final completer = Completer<SherpaHelperResponse>();
    _pending[id] = completer;
    BackendFileLogger.instance.log(
      'Sending segment to Sherpa helper: id=$id bytes=${pcmBytes.length}',
    );

    process.stdin.writeln(jsonEncode({
      'id': id,
      'pcm16_base64': base64Encode(pcmBytes),
    }));

    return completer.future.timeout(const Duration(seconds: 60));
  }

  Future<void> stop() async {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete(
          const SherpaHelperResponse(
            ok: false,
            error: 'Sherpa helper stopped before responding',
          ),
        );
      }
    }
    _pending.clear();

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    final process = _process;
    _process = null;
    if (process != null) {
      process.stdin.writeln(jsonEncode({'type': 'shutdown'}));
      await process.stdin.flush();
      await process.stdin.close();
      await process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 0,
      );
    }
  }

  void _handleStdoutLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }

    Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      BackendFileLogger.instance.log('Sherpa helper stdout: $line');
      stderr.writeln('[sherpa-helper][stdout] $line');
      return;
    }

    if (message['type'] == 'ready') {
      BackendFileLogger.instance.log('Sherpa helper ready handshake received');
      _readyCompleter?.complete();
      return;
    }

    final id = message['id'] as String?;
    if (id == null) {
      return;
    }

    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }

    BackendFileLogger.instance.log(
      'Sherpa helper response: id=$id ok=${message['ok'] == true} textLength=${(message['text'] as String?)?.length ?? 0}',
    );
    completer.complete(
      SherpaHelperResponse(
        ok: message['ok'] == true,
        text: message['text'] as String? ?? '',
        language: message['language'] as String? ?? 'indic',
        error: message['error'] as String?,
      ),
    );
  }
}
