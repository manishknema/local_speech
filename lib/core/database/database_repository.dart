abstract class DatabaseRepository {
  Future<void> initialize();
  
  // Speaker Tagging
  Future<void> saveSpeakerTag(String signature, String name);
  Future<String?> getSpeakerName(String signature);
  Future<Map<String, String>> getAllSpeakerTags();
  
  // Transcripts
  Future<void> saveTranscript(String text, String signature, String language, int timestamp);
  Future<List<Map<String, dynamic>>> getSessionTranscripts();
  
  Future<void> close();
}
