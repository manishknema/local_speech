import 'dart:async';

/// Defines the formats available for exporting transcripts.
enum ExportFormat {
  srt,
  json,
  txt
}

/// The main interface for the frontend to communicate with the background transcription engine.
abstract class VigyanTranscriptionService {
  /// Stream of incoming text chunks (incremental transcripts).
  Stream<String> get transcriptStream;

  /// Stream of log messages from the background isolate.
  Stream<String> get logStream;

  /// Connects to the background IPC server.
  Future<void> connect();

  /// Starts the audio capture and transcription process.
  Future<void> startMeeting();

  /// Stops the active meeting.
  Future<void> stopMeeting();

  /// Exports the persistent data in the specified format.
  Future<String> exportData(ExportFormat format);

  /// Updates the speaker tag for a given signature.
  Future<void> updateTag(String signature, String name);
  
  /// Cleans up resources.
  void dispose();
}
