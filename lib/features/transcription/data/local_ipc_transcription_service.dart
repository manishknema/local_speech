import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../core/ipc/ipc_message.dart';
import '../domain/interfaces/vigyan_transcription_service.dart';

/// The UI-side client that connects to the BackgroundAudioProcessingEngine.
class LocalIpcTranscriptionService implements VigyanTranscriptionService {
  final int port;
  WebSocketChannel? _channel;
  
  final StreamController<String> _transcriptController = StreamController<String>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();
  final StreamController<String> _rawMessageController = StreamController<String>.broadcast();

  LocalIpcTranscriptionService({this.port = 8080});

  @override
  Stream<String> get transcriptStream => _transcriptController.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  Stream<String> get rawMessageStream => _rawMessageController.stream;

  @override
  Future<void> connect() async {
    _logController.add('[UI INFO] Connecting to IPC Engine on port $port...');
    
    int attempts = 0;
    while (attempts < 5) {
      try {
        _channel = WebSocketChannel.connect(
          Uri.parse('ws://localhost:$port'),
        );
        
        await _channel!.ready; 
        
        _channel!.stream.listen(
          _handleIncomingMessage,
          onError: (e) {
            _logController.add('[UI ERROR] WebSocket stream error: $e');
          },
          onDone: () {
            _logController.add('[UI INFO] WebSocket disconnected.');
          }
        );
        
        _logController.add('[UI INFO] Connected to IPC Engine.');
        return;
      } catch (e) {
        attempts++;
        _logController.add('[UI WARNING] Connection attempt $attempts failed. Retrying in 2s...');
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    
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
  Future<void> startMeeting() async {
    _sendControlMessage('START_MEETING');
  }

  @override
  Future<void> stopMeeting() async {
    _sendControlMessage('STOP_MEETING');
  }
  
  void _sendControlMessage(String action, {Map<String, dynamic>? params}) {
    if (_channel != null) {
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
    if (_channel != null) {
      _channel!.sink.add(IpcMessage.updateTag(signature, name).toJson());
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _transcriptController.close();
    _logController.close();
    _rawMessageController.close();
  }
}
