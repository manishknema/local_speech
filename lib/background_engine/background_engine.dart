import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:talker/talker.dart';
import '../../core/ipc/ipc_message.dart';
import '../../core/database/database_repository.dart';
import '../../core/logging/backend_file_logger.dart';
import '../../features/transcription/data/strategies/audio_capture_strategy.dart';
import 'ai/audio_accumulator.dart';
import 'ai/vad_gatekeeper.dart';
import 'ai/lid_classifier.dart';
import 'ai/speaker_embedder.dart';
import 'ai/speaker_tracker.dart';
import 'routing/wav_packetizer.dart';
import 'routing/cloud_packet.dart';

/// Headless engine with VAD-driven Sentence Boundary Detection and Diarization.
class BackgroundAudioProcessingEngine {
  final AudioCaptureStrategy audioCaptureStrategy;
  final VadGatekeeper vadGatekeeper;
  final LidClassifier lidClassifier;
  final SpeakerEmbedder speakerEmbedder;
  final DatabaseRepository databaseRepository;
  final Talker talker;
  
  HttpServer? _server;
  WebSocket? _activeClient;
  StreamSubscription? _audioSubscription;
  
  final SpeakerTracker _speakerTracker = SpeakerTracker();
  final AudioAccumulator _vadInputBuffer = AudioAccumulator(fixedChunkBytes: 1024);
  
  final BytesBuilder _sentenceBuffer = BytesBuilder();
  int _silenceCounterMs = 0;
  static const int _sentenceSilenceThresholdMs = 800; 
  static const int _maxSentenceDurationMs = 15000;
  DateTime? _sentenceStartTime;

  BackgroundAudioProcessingEngine({
    required this.audioCaptureStrategy,
    required this.vadGatekeeper,
    required this.lidClassifier,
    required this.speakerEmbedder,
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
            _startCapture();
          } else if (ipcMsg.payload['action'] == 'STOP_MEETING') {
            _stopCapture();
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

  Future<void> _startCapture() async {
    talker.info('BAPE: Starting Capture');
    BackendFileLogger.instance.log('Starting capture');
    _sendToUi(IpcMessage.captureStatus(
      mode: 'calibrating',
      statusText: 'Calibration: Please say one sentence (about 2 seconds) so I can verify your voice path.',
      activeSources: const ['loopback', 'mic_probe'],
    ));
    await audioCaptureStrategy.startCapture();
    _sendToUi(IpcMessage.control('ENGINE_ACTIVE'));
    _sendToUi(IpcMessage.captureStatus(
      mode: 'loopback',
      statusText: 'Capture: Loopback (System Mix) - verification in progress',
      activeSources: const ['loopback'],
    ));

    _audioSubscription = audioCaptureStrategy.bytesStream.listen((bytes) async {
      final now = DateTime.now();
      if (now.difference(_lastVolumeUpdateTime).inMilliseconds > 50) {
        final data = bytes.buffer.asByteData();
        double peak = 0;
        for (int i = 0; i < bytes.length; i += 2) {
          if (i + 1 < bytes.length) {
            final sample = data.getInt16(i, Endian.little).abs();
            if (sample > peak) peak = sample.toDouble();
          }
        }
        _sendToUi(IpcMessage.volume(peak / 32768.0));
        _lastVolumeUpdateTime = now;
      }

      final vadChunk = _vadInputBuffer.addBytes(bytes);
      if (vadChunk != null) {
        bool isSpeech = await vadGatekeeper.infer(vadChunk);
        
        if (isSpeech) {
          _silenceCounterMs = 0;
          _sentenceStartTime ??= now;
          _sentenceBuffer.add(vadChunk);
        } else {
          _silenceCounterMs += 32; 
          
          if (_silenceCounterMs >= _sentenceSilenceThresholdMs && _sentenceBuffer.isNotEmpty) {
            final completeSentence = _sentenceBuffer.takeBytes();
            await _processFullSentence(completeSentence);
            _sentenceBuffer.clear();
            _sentenceStartTime = null;
          }
        }

        // Stall guardrail: force flush stale long-running sentence buffer.
        if (_sentenceBuffer.isNotEmpty && _sentenceStartTime != null) {
          final ageMs = now.difference(_sentenceStartTime!).inMilliseconds;
          if (ageMs >= _maxSentenceDurationMs) {
            BackendFileLogger.instance.log(
              'Forced flush due to max sentence age (${ageMs}ms)',
              level: 'WARN',
            );
            final forcedSentence = _sentenceBuffer.takeBytes();
            await _processFullSentence(forcedSentence);
            _sentenceBuffer.clear();
            _sentenceStartTime = null;
            _silenceCounterMs = 0;
          }
        }
      }
    });
  }
  
  Future<void> _processFullSentence(Uint8List audio) async {
    String lang = 'eng'; 
    List<double> embedding = [];
    
    try {
      lang = await lidClassifier.infer(audio);
      embedding = await speakerEmbedder.infer(audio);
    } catch (e) {
      talker.error('BAPE: AI Inference Error', e);
      BackendFileLogger.instance.log('AI inference error: $e', level: 'ERROR');
    }
    
    final String signature = _speakerTracker.matchSpeaker(embedding);

    final text = lang == 'eng' 
        ? "Recognized English sentence (${audio.length ~/ 32000}s)."
        : "Recognized Indic ($lang) sentence. Routing to cloud...";

    await databaseRepository.saveTranscript(text, signature, lang, DateTime.now().millisecondsSinceEpoch);
    BackendFileLogger.instance.log(
      'Transcript saved: lang=$lang signature=$signature bytes=${audio.length}',
    );
    
    _sendToUi(IpcMessage.transcript(
      text, 
      signature: signature,
      language: lang,
      translated: lang != 'eng',
    ));
  }

  Future<void> _stopCapture() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    
    if (_sentenceBuffer.isNotEmpty) {
      await _processFullSentence(_sentenceBuffer.takeBytes());
      _sentenceStartTime = null;
    }
    
    await audioCaptureStrategy.stopCapture();
    _sendToUi(IpcMessage.volume(0.0));
    _sendToUi(IpcMessage.control('ENGINE_IDLE'));
    talker.info('BAPE: Capture Stopped.');
    BackendFileLogger.instance.log('Capture stopped');
    await BackendFileLogger.instance.close();
  }

  void _sendToUi(IpcMessage message) {
    if (_activeClient != null && _activeClient!.readyState == WebSocket.open) {
      _activeClient!.add(message.toJson());
    }
  }
}
