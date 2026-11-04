import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class _VerificationService extends ViewerService {
  final first = Completer<Map<String, dynamic>>();
  final started = Completer<void>();

  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];

  @override
  Future<Uint8List> read(String path) async => Uint8List.fromList([1, 2, 3]);

  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];

  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) {
    if (name == 'first.jpg') {
      started.complete();
      return first.future;
    }
    return Future.value({'status': 'absent'});
  }
}

void main() {
  testWidgets('inspector has no heading in English or Japanese', (
    tester,
  ) async {
    for (final locale in [const Locale('en'), const Locale('ja')]) {
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ja')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: ViewerScreen(controller: ViewerController(ViewerService())),
        ),
      );
      expect(find.text('Inspector'), findsNothing);
      expect(find.text('インスペクター'), findsNothing);
    }
  });

  testWidgets('inspector shows only actionable C2PA results', (tester) async {
    Future<void> check(
      Map<String, dynamic>? result,
      String status,
      bool visible,
    ) async {
      final controller = ViewerController(ViewerService())
        ..c2paResult = result
        ..c2paStatus = status;
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: ViewerScreen(controller: controller),
        ),
      );
      await tester.pump();
      expect(controller.c2paVisibility, visible, reason: '$result / $status');
      expect(
        find.text('Content Credentials (C2PA)'),
        visible ? findsOneWidget : findsNothing,
        reason: '$result / $status',
      );
    }

    await check(null, 'Select an image to verify.', false);
    await check(null, 'Verifying…', false);
    await check({'status': 'absent'}, 'Offline verification', false);
    await check({'status': 'unsupported'}, 'Offline verification', false);
    await check({'status': 'present'}, 'Offline verification', true);
    await check({'status': 'remote'}, 'Offline verification', true);
    await check(
      {'status': 'error', 'error': 'bad manifest'},
      'Offline verification',
      true,
    );
    expect(find.text('Error: bad manifest'), findsOneWidget);
    await check(null, 'Verification unavailable: engine failure', true);
    expect(
      find.text('Verification unavailable: engine failure'),
      findsOneWidget,
    );
    await check(
      null,
      'Original file verification unavailable: read failure',
      true,
    );
  });

  testWidgets('late verification cannot reveal credentials for a newer image', (
    tester,
  ) async {
    late _VerificationService service;
    late ViewerController controller;
    await tester.runAsync(() async {
      service = _VerificationService();
      controller = ViewerController(service);
    });
    await tester.pumpWidget(
      MaterialApp(home: ViewerScreen(controller: controller)),
    );

    late Future<void> first;
    await tester.runAsync(() async {
      first = controller.open('first.jpg');
      await service.started.future;
    });
    await tester.pump();
    expect(controller.c2paVisibility, isFalse);
    expect(find.text('Content Credentials (C2PA)'), findsNothing);

    await tester.runAsync(() => controller.open('second.jpg'));
    await tester.pump();
    expect(controller.c2paResult?['status'], 'absent');
    expect(find.text('Content Credentials (C2PA)'), findsNothing);

    await tester.runAsync(() async {
      service.first.complete({'status': 'present'});
      await first;
    });
    await tester.pump();
    expect(controller.name, 'second.jpg');
    expect(controller.c2paResult?['status'], 'absent');
    expect(controller.c2paVisibility, isFalse);
    expect(find.text('Content Credentials (C2PA)'), findsNothing);
  });
}
