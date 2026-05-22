// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:talker/talker.dart';
import 'package:vigyanbytes_transcribe/features/transcription/presentation/ui/transcription_dashboard.dart';

import 'package:vigyanbytes_transcribe/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      VigyanTranscribeApp(
        talker: Talker(),
        ipcPort: 8080,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TranscriptionDashboard), findsOneWidget);
  });
}
