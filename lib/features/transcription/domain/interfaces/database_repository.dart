import 'vigyan_transcription_service.dart' show ExportFormat;

/// Represents a single transcribed chunk.
class Transcript {
  final int? id;
  final String text;
  final String? signature;
  final int startTimeMs;
  final int endTimeMs;

  Transcript({
    this.id,
    required this.text,
    this.signature,
    required this.startTimeMs,
    required this.endTimeMs,
  });
}

/// Interface for the persistence layer.
abstract class DatabaseRepository {
  /// Initializes the database.
  Future<void> init();

  /// Saves a transcript chunk to the database.
  Future<void> saveTranscript(Transcript transcript);

  /// Updates the display name for a specific voice signature.
  Future<void> updateTag(String signature, String name);

  /// Fetches the meeting history formatted for export.
  Future<String> fetchExport(ExportFormat format);
}
