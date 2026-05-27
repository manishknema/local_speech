import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:talker/talker.dart';
import '../../core/audio/pcm_codec.dart';
import '../../core/ipc/ipc_message.dart';
import '../../core/database/database_repository.dart';
import '../../core/logging/backend_file_logger.dart';
import '../../features/transcription/data/strategies/audio_capture_strategy.dart';
import 'asr/asr_engine.dart';
import 'ai/vad_gatekeeper.dart';
import 'ai/vad_utterance_segmenter.dart';
import 'ai/lid_classifier.dart';
import 'ai/speaker_embedder.dart';
import 'routing/cloud_packet.dart';

/// Headless engine with VAD-driven Sentence Boundary Detection and Diarization.
class BackgroundAudioProcessingEngine {
  final AudioCaptureStrategy audioCaptureStrategy;
  final VadGatekeeper vadGatekeeper;
  final LidClassifier lidClassifier;
  final SpeakerEmbedder speakerEmbedder;
  final AsrEngine asrEngine;
  final DatabaseRepository databaseRepository;
  final Talker talker;

  HttpServer? _server;
  WebSocket? _activeClient;
  StreamSubscription? _audioSubscription;
  String _latestPartialTranscript = '';
  DateTime _lastVadDebugTime = DateTime.fromMillisecondsSinceEpoch(0);

  final VadUtteranceSegmenter _utteranceSegmenter = VadUtteranceSegmenter(
    sampleRate: 16000,
    preRollMs: 300,
    minSegmentMs: 1200,
    tailOverlapMs: 250,
    silenceToleranceMs: 400,
  );
  static const int _bytesPerSecondPcm16Mono = 32000;
  static const int _maxSentenceDurationMs = 15000;
  static const int _offlineAsrMaxSegmentDurationMs = 6000;
  static const int _minimumSessionWavBytes = 16000;
  static const String _singleSpeakerSignature = 'MicSpeaker';
  DateTime? _utteranceStartTime;
  // Streaming WAV writer — PCM chunks go straight to disk, never buffered in RAM.
  RandomAccessFile? _sessionWavFile;
  String? _sessionWavFilePath;
  int _sessionPcmBytesWritten = 0;

  BackgroundAudioProcessingEngine({
    required this.audioCaptureStrategy,
    required this.vadGatekeeper,
    required this.lidClassifier,
    required this.speakerEmbedder,
    required this.asrEngine,
    required this.databaseRepository,
    required this.talker,
  });

  Future<void> startIpcServer(int port) async {
    await BackendFileLogger.instance.initialize();
    BackendFileLogger.instance.log('Starting IPC server on port $port');
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    talker.info('BAPE: IPC Server listening on ws://localhost:$port');
    BackendFileLogger.instance.log('IPC server listening on ws://localhost:$port');

    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
          _activeClient = await WebSocketTransformer.upgrade(request);
          BackendFileLogger.instance.log('UI WebSocket client connected');
          _reportAllComponentStatuses();
          _sendToUi(IpcMessage.control('ENGINE_IDLE'));

        _activeClient!.listen(
          _handleClientMessage,
          onDone: () {
            talker.info('BAPE: UI Client Disconnected');
            BackendFileLogger.instance.log('UI WebSocket client disconnected');
          },
          onError: (e) {
            talker.error('BAPE: WebSocket Error: $e');
            BackendFileLogger.instance.log('WebSocket error: $e', level: 'ERROR');
          },
        );
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.close();
      }
    });

    await _initializeComponents();
  }

  final Map<String, String> _componentStatuses = {};

  Future<void> _initializeComponents() async {
    talker.info('BAPE: Initializing Components...');
    BackendFileLogger.instance.log('Initializing backend components');
    await _initComponent('VAD Engine', () => vadGatekeeper.loadModel());
    await _initComponent('LID Engine', () => lidClassifier.loadModel());
    await _initComponent('Speaker Embedder', () => speakerEmbedder.loadModel());
    await _initComponent('ASR Engine', () => asrEngine.loadModel());
    await _initComponent('Database', () => databaseRepository.initialize());
  }

  Future<void> _initComponent(String name, Future<void> Function() initAction) async {
    _updateComponentStatus(name, 'loading');
    try {
      await initAction();
      _updateComponentStatus(name, 'success');
    } catch (e) {
      _updateComponentStatus(name, 'error', error: e.toString());
      talker.error('BAPE: $name init failed', e);
      BackendFileLogger.instance.log('$name init failed: $e', level: 'ERROR');
    }
  }

  void _updateComponentStatus(String name, String status, {String? error}) {
    _componentStatuses[name] = status;
    _sendToUi(IpcMessage.modelStatus(name, status, error: error));
  }

  void _reportAllComponentStatuses() {
    _componentStatuses.forEach((name, status) => _sendToUi(IpcMessage.modelStatus(name, status)));
  }

  void _handleClientMessage(dynamic message) {
    if (message is String) {
      try {
        final ipcMsg = IpcMessage.fromJson(message);
        if (ipcMsg.type == 'CONTROL') {
          if (ipcMsg.payload['action'] == 'START_MEETING') {
            final params = ipcMsg.payload['params'] as Map<String, dynamic>?;
            final useMic = (params?['useMic'] as bool?) ?? true;
            _startCapture(useMic: useMic);
          } else if (ipcMsg.payload['action'] == 'STOP_MEETING') {
            _stopCapture();
          } else if (ipcMsg.payload['action'] == 'LIST_DEVICES') {
            final forMic = (ipcMsg.payload['params']?['forMic'] as bool?) ?? true;
            final devices = audioCaptureStrategy.listAvailableDevices(forMic: forMic);
            _sendToUi(IpcMessage.control('DEVICE_LIST', params: {
              'forMic': forMic,
              'devices': devices,
            }));
          } else if (ipcMsg.payload['action'] == 'SET_PREFERRED_DEVICE') {
            final name = ipcMsg.payload['params']?['name'] as String?;
            audioCaptureStrategy.setPreferredDevice(name);
          }
        } else if (ipcMsg.type == 'TAG_UPDATE') {
          final sig = ipcMsg.payload['signature'];
          final name = ipcMsg.payload['name'];
          if (sig != null && name != null) {
            databaseRepository.saveSpeakerTag(sig, name);
          }
        }
      } catch (e) {
        talker.error('BAPE: IPC Parse Error', e);
        BackendFileLogger.instance.log('IPC parse error: $e', level: 'ERROR');
      }
    }
  }

  DateTime _lastVolumeUpdateTime = DateTime.now();

  Future<void> _startCapture({bool useMic = true}) async {
    talker.info('BAPE: Starting Capture useMic=$useMic');
    BackendFileLogger.instance.log('Starting capture useMic=$useMic');
    _latestPartialTranscript = '';
    _sessionPcmBytesWritten = 0;
    _sessionWavFilePath = null;
    try {
      final wavDir = Directory('logs/sessions');
      await wavDir.create(recursive: true);
      final ist = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
      final ts = ist.toIso8601String().replaceAll(':', '-');
      final wavFile = File('${wavDir.path}/session_IST_$ts.wav');
      _sessionWavFile = await wavFile.open(mode: FileMode.writeOnly);
      // Write 44-byte WAV header placeholder; real sizes filled in on stop.
      await _sessionWavFile!.writeFrom(Uint8List(44));
      _sessionWavFilePath = wavFile.absolute.path;
    } catch (e) {
      BackendFileLogger.instance.log('Session WAV file open failed: $e', level: 'WARN');
      _sessionWavFile = null;
    }
    _sendToUi(IpcMessage.captureStatus(
      mode: 'calibrating',
      statusText: useMic
          ? 'Starting In-Person Meeting — microphone capture'
          : 'Starting Live Meeting — system audio capture',
      activeSources: useMic ? const ['mic'] : const ['loopback'],
    ));
    await audioCaptureStrategy.startCapture(useMic: useMic);
    final deviceName = audioCaptureStrategy.selectedDeviceName ?? 'Unknown device';
    _sendToUi(IpcMessage.control('ENGINE_ACTIVE'));
    _sendToUi(IpcMessage.captureStatus(
      mode: useMic ? 'mic' : 'loopback',
      statusText: useMic
          ? 'In-Person Meeting — $deviceName'
          : 'Live Meeting — $deviceName',
      activeSources: useMic ? const ['mic'] : const ['loopback'],
    ));
    await asrEngine.startSession();
    _utteranceSegmenter.reset();
    _utteranceStartTime = null;

    if (asrEngine.supportsStreaming) {
      _audioSubscription = audioCaptureStrategy.frameStream.listen((frame) async {
        final now = DateTime.now();
        if (now.difference(_lastVolumeUpdateTime).inMilliseconds > 50) {
          double peak = 0;
          for (final sample in frame.samples) {
            final abs = sample.abs();
            if (abs > peak) peak = abs;
          }
          _sendToUi(IpcMessage.volume(peak.clamp(0.0, 1.0)));
          _lastVolumeUpdateTime = now;
        }

        final partial = asrEngine.ingestSamples(frame.samples);
        if (partial != null && partial.text.isNotEmpty) {
          _latestPartialTranscript = partial.text;
          _sendToUi(
            IpcMessage.asrPartial(
              partial.text,
              language: partial.language,
              engineId: partial.engineId,
            ),
          );
        }
      });
      return;
    }

    _audioSubscription = audioCaptureStrategy.bytesStream.listen((bytes) async {
      if (_sessionWavFile != null && bytes.isNotEmpty) {
        try {
          await _sessionWavFile!.writeFrom(bytes);
          _sessionPcmBytesWritten += bytes.length;
        } catch (_) {}
      }
      final now = DateTime.now();
      if (now.difference(_lastVolumeUpdateTime).inMilliseconds > 50) {
        _emitVolumeLevel(bytes, now: now);
      }

      final vadDecision = await vadGatekeeper.inferDetailed(bytes);
      final isSpeech = vadDecision.isSpeech;
      if (now.difference(_lastVadDebugTime).inMilliseconds >= 250) {
        BackendFileLogger.instance.log(
          'VAD debug: prob=${vadDecision.probability.toStringAsFixed(3)} threshold=${VadGatekeeper.liveSpeechThreshold.toStringAsFixed(2)} speech=$isSpeech samples=${vadDecision.sampleCount}',
        );
        _lastVadDebugTime = now;
      }
      final previousState = _utteranceSegmenter.state;
      final completedSegment = _utteranceSegmenter.processVadFrame(bytes, isSpeech);
      final currentState = _utteranceSegmenter.state;

      if (previousState == VadUtteranceState.silence &&
          currentState == VadUtteranceState.utteranceActive) {
        _utteranceStartTime = now;
        BackendFileLogger.instance.log(
          'Speech started; opening utterance buffer with 300ms pre-roll',
        );
      }

      if (completedSegment != null) {
        await _processFullSentence(completedSegment);
        _utteranceStartTime = null;
      }

      if (_utteranceSegmenter.hasActiveUtterance && _utteranceStartTime != null) {
        final ageMs = now.difference(_utteranceStartTime!).inMilliseconds;
        final forceFlushLimitMs = asrEngine.supportsStreaming
            ? _maxSentenceDurationMs
            : _offlineAsrMaxSegmentDurationMs;
        if (ageMs >= forceFlushLimitMs) {
          BackendFileLogger.instance.log(
            'Forced flush due to max utterance age (${ageMs}ms, limit=${forceFlushLimitMs}ms)',
            level: 'WARN',
          );
          final forcedSegment = _utteranceSegmenter.forceFlush();
          _utteranceStartTime = null;
          if (forcedSegment != null) {
            await _processFullSentence(forcedSegment);
          }
        }
      }
    });
  }

  Future<void> _processFullSentence(Float32List audio) async {
    final pcmBytes = PcmCodec.float32ToPcm16Le(audio);
    final durationMs = ((pcmBytes.length / _bytesPerSecondPcm16Mono) * 1000).round();
    BackendFileLogger.instance.log(
      'Processing utterance segment (${pcmBytes.length} bytes, ~${durationMs}ms) with ASR=${asrEngine.engineId}',
    );
    AsrTranscript transcript = AsrTranscript(
      text: 'No transcript available.',
      language: 'und',
      engineId: asrEngine.engineId,
      runtimeMode: asrEngine.runtimeMode,
      topology: asrEngine.topology,
    );

    try {
      transcript = await asrEngine.transcribePcm16(pcmBytes);
    } catch (e) {
      talker.error('BAPE: AI Inference Error', e);
      BackendFileLogger.instance.log('AI inference error: $e', level: 'ERROR');
    }

    const String signature = _singleSpeakerSignature;
    final text = transcript.text.trim();
    final lang = transcript.language;
    BackendFileLogger.instance.log(
      'ASR completed: textLength=${text.length}, lang=$lang, speakerMode=single_speaker',
    );

    if (text.isEmpty) {
      BackendFileLogger.instance.log(
        'Discarding empty ASR result for bytes=${pcmBytes.length} asr=${transcript.engineId}',
        level: 'WARN',
      );
      return;
    }

    await databaseRepository.saveTranscript(text, signature, lang, DateTime.now().millisecondsSinceEpoch);
    BackendFileLogger.instance.log(
      'Transcript saved: lang=$lang signature=$signature bytes=${pcmBytes.length} asr=${transcript.engineId} runtime=${transcript.runtimeMode.name} topology=${transcript.topology.name}',
    );

    _sendToUi(IpcMessage.transcript(
      text,
      signature: signature,
      language: lang,
      translated: transcript.translated,
    ));
  }

  Future<void> _stopCapture() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (asrEngine.supportsStreaming) {
      final transcript = await asrEngine.finishSession();
      if (transcript != null && transcript.text.isNotEmpty) {
        await databaseRepository.saveTranscript(
          transcript.text,
          'live_stream',
          transcript.language,
          DateTime.now().millisecondsSinceEpoch,
        );
        _sendToUi(IpcMessage.transcript(
          transcript.text,
          signature: 'live_stream',
          language: transcript.language,
          translated: transcript.translated,
        ));
      }
      _sendToUi(IpcMessage.asrPartial('', language: 'indic', engineId: asrEngine.engineId));
    }

    final trailingSegment = _utteranceSegmenter.forceFlush();
    if (trailingSegment != null) {
      await _processFullSentence(trailingSegment);
      _utteranceStartTime = null;
    }

    await audioCaptureStrategy.stopCapture();

    // Finalise the streaming WAV file — fill in the header with real byte counts.
    final wavFile = _sessionWavFile;
    final wavPath = _sessionWavFilePath;
    final pcmBytes = _sessionPcmBytesWritten;
    _sessionWavFile = null;
    _sessionWavFilePath = null;
    _sessionPcmBytesWritten = 0;

    if (wavFile != null && wavPath != null && pcmBytes >= _minimumSessionWavBytes) {
      try {
        // Seek back and write the real WAV header now that we know total PCM size.
        await wavFile.setPosition(0);
        await wavFile.writeFrom(_buildWavHeader(pcmBytes));
        await wavFile.close();
        BackendFileLogger.instance.log('Session WAV saved: $wavPath ($pcmBytes PCM bytes)');
        _sendToUi(IpcMessage.control('SESSION_WAV_SAVED', params: {'path': wavPath}));
      } catch (e) {
        await wavFile.close().catchError((_) {});
        BackendFileLogger.instance.log('Session WAV finalise failed: $e', level: 'ERROR');
      }
    } else {
      await wavFile?.close().catchError((_) {});
    }

    _sendToUi(IpcMessage.volume(0.0));
    _sendToUi(IpcMessage.control('ENGINE_IDLE'));
    talker.info('BAPE: Capture Stopped.');
    BackendFileLogger.instance.log('Capture stopped');
    await BackendFileLogger.instance.close();
  }

  /// Builds a 44-byte PCM WAV header for 16kHz mono 16-bit audio.
  Uint8List _buildWavHeader(int pcmDataBytes) {
    final buf = ByteData(44);
    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) buf.setUint8(offset + i, s.codeUnitAt(i));
    }
    writeStr(0,  'RIFF');
    buf.setUint32(4,  36 + pcmDataBytes, Endian.little); // file size - 8
    writeStr(8,  'WAVE');
    writeStr(12, 'fmt ');
    buf.setUint32(16, 16,    Endian.little); // PCM chunk size
    buf.setUint16(20, 1,     Endian.little); // PCM format
    buf.setUint16(22, 1,     Endian.little); // channels = 1
    buf.setUint32(24, 16000, Endian.little); // sample rate
    buf.setUint32(28, 32000, Endian.little); // byte rate = 16000*1*2
    buf.setUint16(32, 2,     Endian.little); // block align
    buf.setUint16(34, 16,    Endian.little); // bits per sample
    writeStr(36, 'data');
    buf.setUint32(40, pcmDataBytes, Endian.little);
    return buf.buffer.asUint8List();
  }

  void _emitVolumeLevel(Uint8List bytes, {DateTime? now}) {
    final eventTime = now ?? DateTime.now();
    final data = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
    double peak = 0;
    for (int i = 0; i < bytes.length; i += 2) {
      if (i + 1 < bytes.length) {
        final sample = data.getInt16(i, Endian.little).abs();
        if (sample > peak) peak = sample.toDouble();
      }
    }
    _sendToUi(IpcMessage.volume(peak / 32768.0));
    _lastVolumeUpdateTime = eventTime;
  }

  void _sendToUi(IpcMessage message) {
    if (_activeClient != null && _activeClient!.readyState == WebSocket.open) {
      _activeClient!.add(message.toJson());
    }
  }
}
