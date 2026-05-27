import 'dart:collection';
import 'dart:typed_data';

import '../../core/audio/pcm_codec.dart';

enum VadUtteranceState { silence, utteranceActive, flushing }

class VadUtteranceSegmenter {
  VadUtteranceSegmenter({
    this.sampleRate = 16000,
    this.preRollMs = 300,
    this.minSegmentMs = 1200,
    this.tailOverlapMs = 250,
    this.silenceToleranceMs = 400,
  })  : preRollSamples = ((sampleRate * preRollMs) / 1000).round(),
        minSegmentSamples = ((sampleRate * minSegmentMs) / 1000).round(),
        tailOverlapSamples = ((sampleRate * tailOverlapMs) / 1000).round(),
        silenceToleranceSamples =
            ((sampleRate * silenceToleranceMs) / 1000).round();

  final int sampleRate;
  final int preRollMs;
  final int minSegmentMs;
  final int tailOverlapMs;
  final int silenceToleranceMs;

  final int preRollSamples;
  final int minSegmentSamples;
  final int tailOverlapSamples;
  final int silenceToleranceSamples;

  final ListQueue<double> _preRoll = ListQueue<double>();
  final List<double> _utteranceBuffer = <double>[];
  List<double>? _tailOverlap;

  VadUtteranceState _state = VadUtteranceState.silence;
  int _silenceSamples = 0;

  VadUtteranceState get state => _state;

  bool get hasActiveUtterance => _utteranceBuffer.isNotEmpty;

  Float32List? processVadFrame(Uint8List pcm16Frame, bool isSpeech) {
    final frame = PcmCodec.pcm16LeToFloat32(pcm16Frame);
    final frameSamples = frame.length;
    Float32List? completed;

    switch (_state) {
      case VadUtteranceState.silence:
        if (isSpeech) {
          _startUtterance();
          _utteranceBuffer.addAll(frame);
          _state = VadUtteranceState.utteranceActive;
        }
        break;
      case VadUtteranceState.utteranceActive:
        if (isSpeech) {
          _utteranceBuffer.addAll(frame);
        } else {
          _silenceSamples = frameSamples;
          _state = VadUtteranceState.flushing;
        }
        break;
      case VadUtteranceState.flushing:
        if (isSpeech) {
          _silenceSamples = 0;
          _utteranceBuffer.addAll(frame);
          _state = VadUtteranceState.utteranceActive;
        } else {
          // Include silence frames so trailing phonemes of the last word
          // reach the ASR model rather than being cut off at the boundary.
          _utteranceBuffer.addAll(frame);
          _silenceSamples += frameSamples;
          if (_silenceSamples >= silenceToleranceSamples) {
            completed = _finalizeUtterance();
            _state = VadUtteranceState.silence;
            _silenceSamples = 0;
          }
        }
        break;
    }

    _appendToPreRoll(frame);
    return completed;
  }

  Float32List? forceFlush() {
    if (_utteranceBuffer.isEmpty) {
      _state = VadUtteranceState.silence;
      _silenceSamples = 0;
      return null;
    }

    final completed = _finalizeUtterance();
    _state = VadUtteranceState.silence;
    _silenceSamples = 0;
    return completed;
  }

  void reset() {
    _preRoll.clear();
    _utteranceBuffer.clear();
    _tailOverlap = null;
    _silenceSamples = 0;
    _state = VadUtteranceState.silence;
  }

  void _startUtterance() {
    _utteranceBuffer.clear();
    if (_tailOverlap != null && _tailOverlap!.isNotEmpty) {
      _utteranceBuffer.addAll(_tailOverlap!);
      _tailOverlap = null;
    }
    if (_preRoll.isNotEmpty) {
      _utteranceBuffer.addAll(_preRoll);
    }
    _silenceSamples = 0;
  }

  Float32List? _finalizeUtterance() {
    if (_utteranceBuffer.length < minSegmentSamples) {
      _utteranceBuffer.clear();
      return null;
    }

    final segment = Float32List.fromList(_utteranceBuffer);
    if (_utteranceBuffer.length > tailOverlapSamples) {
      _tailOverlap = _utteranceBuffer.sublist(
        _utteranceBuffer.length - tailOverlapSamples,
      );
    } else {
      _tailOverlap = List<double>.from(_utteranceBuffer);
    }
    _utteranceBuffer.clear();
    return segment;
  }

  void _appendToPreRoll(Float32List frame) {
    for (final sample in frame) {
      _preRoll.addLast(sample);
      while (_preRoll.length > preRollSamples) {
        _preRoll.removeFirst();
      }
    }
  }
}
