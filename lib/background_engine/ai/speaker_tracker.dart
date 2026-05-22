import 'dart:math';
import 'dart:typed_data';

class SpeakerTracker {
  // Map of VoiceID -> Average Embedding Vector
  final Map<String, List<double>> _knownVoices = {};
  
  // Similarity threshold (80% for high-end speaker models)
  static const double threshold = 0.82;

  String matchSpeaker(List<double> newVector) {
    if (newVector.isEmpty || newVector.every((v) => v == 0)) return "Unknown";

    double bestSim = -1.0;
    String? bestId;

    for (var entry in _knownVoices.entries) {
      double sim = _cosineSimilarity(newVector, entry.value);
      if (sim > bestSim) {
        bestSim = sim;
        bestId = entry.key;
      }
    }

    if (bestSim >= threshold) {
      // Update running average for the voice profile
      _updateVoiceAverage(bestId!, newVector);
      return bestId;
    } else {
      // New Speaker
      final newId = "Voice_${_knownVoices.length + 1}";
      _knownVoices[newId] = List.from(newVector);
      return newId;
    }
  }

  void _updateVoiceAverage(String id, List<double> newVector) {
    final current = _knownVoices[id]!;
    for (int i = 0; i < current.length; i++) {
      // 90/10 weighted average to allow slight drift but maintain stability
      current[i] = (current[i] * 0.9) + (newVector[i] * 0.1);
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0, magA = 0.0, magB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    double denom = sqrt(magA) * sqrt(magB);
    return denom == 0 ? 0 : dot / denom;
  }
}
