import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/ipc/ipc_message.dart';
import '../domain/interfaces/vigyan_transcription_service.dart';

/// The UI-side client that connects to the BackgroundAudioProcessingEngine.
class LocalIpcTranscriptionService implements VigyanTranscriptionService {
  final int port;
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  bool _isConnected = false;
  Future<void>? _connectInFlight;
  
  final StreamController<String> _transcriptController = StreamController<String>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<String> _rawMessageController = StreamController<String>.broadcast();
  final StreamController<bool> _connectionStateController = StreamController<bool>.broadcast();

  LocalIpcTranscriptionService({this.port = 8080});

  @override
  Stream<String> get transcriptStream => _transcriptController.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  Stream<String> get rawMessageStream => _rawMessageController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected && _channel != null) {
      return;
    }
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    _connectInFlight = _connectInternal();
    try {
      await _connectInFlight;
    } finally {
      _connectInFlight = null;
    }
  }

  Future<void> _connectInternal() async {
    _logController.add('[UI INFO] Connecting to IPC Engine on port $port...');
    await _closeChannel();
    
    int attempts = 0;
    while (attempts < 5) {
      try {
        _channel = WebSocketChannel.connect(
          Uri.parse('ws://localhost:$port'),
        );
        
        await _channel!.ready; 
        
        _channelSubscription = _channel!.stream.listen(
          _handleIncomingMessage,
          onError: (e) {
            _logController.add('[UI ERROR] WebSocket stream error: $e');
            _markDisconnected();
          },
          onDone: () {
            _logController.add('[UI INFO] WebSocket disconnected.');
            _markDisconnected();
          },
        );

        _isConnected = true;
        _connectionStateController.add(true);
        _logController.add('[UI INFO] Connected to IPC Engine.');
        return;
      } catch (e) {
        attempts++;
        _markDisconnected();
        _logController.add('[UI WARNING] Connection attempt $attempts failed. Retrying in 2s...');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    
    _markDisconnected();
    _logController.add('[UI ERROR] Failed to connect after multiple attempts.');
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is String) {
      _rawMessageController.add(message);
      try {
        final ipcMsg = IpcMessage.fromJson(message);
        
        if (ipcMsg.type == 'TRANSCRIPT') {
          final text = ipcMsg.payload['text'] as String?;
          if (text != null) {
            _transcriptController.add(text);
          }
        } else if (ipcMsg.type == 'LOG') {
          final level = ipcMsg.payload['level'] ?? 'INFO';
          final msg = ipcMsg.payload['message'] ?? '';
          _logController.add('[$level] $msg');
        }
      } catch (e) {
        _logController.add('[UI ERROR] Failed to parse message: $e');
      }
    }
  }

  @override
  Future<void> startMeeting({bool useMic = true}) async {
    await connect();
    _sendControlMessage('START_MEETING', params: {'useMic': useMic});
  }

  @override
  Future<void> stopMeeting() async {
    _sendControlMessage('STOP_MEETING');
  }

  Future<void> listDevices({required bool forMic}) async {
    await connect();
    _sendControlMessage('LIST_DEVICES', params: {'forMic': forMic});
  }

  void setPreferredDevice(String? name) {
    _sendControlMessage('SET_PREFERRED_DEVICE', params: {'name': name});
  }

  
  void _sendControlMessage(String action, {Map<String, dynamic>? params}) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(IpcMessage.control(action, params: params).toJson());
    } else {
      _logController.add('[UI ERROR] Cannot send command, not connected.');
    }
  }

  @override
  Future<String> exportData(ExportFormat format) async {
    return "Exporter triggered via UI.";
  }

  @override
  Future<void> updateTag(String signature, String name) async {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(IpcMessage.updateTag(signature, name).toJson());
    }
  }

  void _markDisconnected() {
    if (_isConnected) {
      _isConnected = false;
      _connectionStateController.add(false);
    }
    _channel = null;
  }

  Future<void> _closeChannel() async {
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }

  @override
  void dispose() {
    unawaited(_closeChannel());
    _transcriptController.close();
    _logController.close();
    _rawMessageController.close();
    _connectionStateController.close();
  }
}
