import 'dart:convert';

/// Represents a standardized message sent across the IPC boundary.
class IpcMessage {
  final String type;
  final Map<String, dynamic> payload;

  IpcMessage({required this.type, required this.payload});

  factory IpcMessage.fromJson(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    return IpcMessage(
      type: data['type'] as String,
      payload: data['payload'] as Map<String, dynamic>? ?? {},
    );
  }

  String toJson() {
    return jsonEncode({
      'type': type,
      'payload': payload,
    });
  }

  // --- Convenience Factories for Standardized Messages ---
  
  static IpcMessage log(String level, String message) {
    return IpcMessage(
      type: 'LOG',
      payload: {
        'level': level,
        'message': message,
      },
    );
  }

  static IpcMessage volume(double level) {
    return IpcMessage(
      type: 'VOLUME',
      payload: {'level': level}, // 0.0 to 1.0
    );
  }

  static IpcMessage modelStatus(String modelName, String status, {double? progress, String? error}) {
    return IpcMessage(
      type: 'MODEL_STATUS',
      payload: {
        'modelName': modelName,
        'status': status, // 'loading', 'success', 'error', 'missing', 'downloading'
        if (progress != null) 'progress': progress,
        if (error != null) 'error': error,
      },
    );
  }

  static IpcMessage transcript(String text, {String? signature, String? language, int? startTime, int? endTime, bool translated = false}) {
    return IpcMessage(
      type: 'TRANSCRIPT',
      payload: {
        'text': text,
        if (signature != null) 'signature': signature,
        if (language != null) 'language': language,
        if (startTime != null) 'startTimeMs': startTime,
        if (endTime != null) 'endTimeMs': endTime,
        'translated': translated,
      },
    );
  }

  static IpcMessage updateTag(String signature, String name) {
    return IpcMessage(
      type: 'TAG_UPDATE',
      payload: {
        'signature': signature,
        'name': name,
      },
    );
  }

  static IpcMessage control(String action, {Map<String, dynamic>? params}) {
    return IpcMessage(
      type: 'CONTROL',
      payload: {
        'action': action,
        if (params != null) ...params,
      },
    );
  }

  static IpcMessage captureStatus({
    required String mode,
    required String statusText,
    bool nearEndInLoopback = false,
    List<String>? activeSources,
  }) {
    return IpcMessage(
      type: 'CAPTURE_STATUS',
      payload: {
        'mode': mode,
        'statusText': statusText,
        'nearEndInLoopback': nearEndInLoopback,
        'activeSources': activeSources ?? const <String>[],
      },
    );
  }
}
