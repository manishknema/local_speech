import 'dart:isolate';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:talker/talker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'background_engine/background_engine.dart';
import 'background_engine/asr/meetsync_indic_helper_asr_engine.dart';
import 'background_engine/ai/vad_gatekeeper.dart';
import 'background_engine/ai/lid_classifier.dart';
import 'background_engine/ai/speaker_embedder.dart';
import 'core/database/sqlite_database_repository.dart';
import 'features/transcription/data/strategies/windows_audio_strategy.dart';
import 'features/transcription/presentation/ui/transcription_dashboard.dart';

import 'package:onnxruntime/onnxruntime.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize ONNX Runtime Environment
  OrtEnv.instance.init();

  // Initialize SQLite for Desktop
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize central logging
  final talker = TalkerFlutter.init();

  // Capture Root Isolate Token for asset loading in background isolate
  final RootIsolateToken rootToken = RootIsolateToken.instance!;

  // Use a fixed port for reliability during testing
  const int ipcPort = 8080;

  // Start the background engine in a separate Isolate
  await Isolate.spawn(_startBackgroundEngine, [ipcPort, rootToken]);

  runApp(VigyanTranscribeApp(talker: talker, ipcPort: ipcPort));
}

/// Entry point for the Background Engine Isolate
void _startBackgroundEngine(List<dynamic> args) async {
  final int port = args[0] as int;
  final RootIsolateToken rootToken = args[1] as RootIsolateToken;

  // Initialize Flutter background isolate bindings
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  
  // Initialize SQLite for the isolate
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Ensure plugins are registered in this isolate
  DartPluginRegistrant.ensureInitialized();

  // Talker instance for the background isolate (Pure Dart version)
  final isolateTalker = Talker();
  
  final strategy = WindowsAudioStrategy();
  final vad = VadGatekeeper();
  final lid = LidClassifier();
  final embedder = SpeakerEmbedder();
  final asr = MeetsyncIndicHelperAsrEngine();
  final database = SqliteDatabaseRepository();
  
  final engine = BackgroundAudioProcessingEngine(
    audioCaptureStrategy: strategy,
    vadGatekeeper: vad,
    lidClassifier: lid,
    speakerEmbedder: embedder,
    asrEngine: asr,
    databaseRepository: database,
    talker: isolateTalker,
  );
  
  await engine.startIpcServer(port);
}

class VigyanTranscribeApp extends StatelessWidget {
  final Talker talker;
  final int ipcPort;

  const VigyanTranscribeApp({super.key, required this.talker, required this.ipcPort});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vigyan Transcribe',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: TranscriptionDashboard(talker: talker, ipcPort: ipcPort),
    );
  }
}
