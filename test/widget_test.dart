import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class FakeService extends ViewerService {
  final first = Completer<Uint8List>();
  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [
    MetadataEntry('File', 'Name', path),
  ];
  @override
  Future<Uint8List> read(String path) => path == 'first'
      ? first.future
      : Future.value(Uint8List.fromList([1, 2, 3]));
  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [
    const MetadataEntry('EXIF', 'Image Make', 'Example'),
  ];
}

void main() {
  testWidgets(
    'stale results are ignored and metadata survives preview failure',
    (tester) async {
      final service = FakeService();
      final controller = ViewerController(service);
      final old = controller.open('first');
      await controller.open('second');
      expect(controller.name, 'second');
      expect(controller.previewError, contains('Image preview unavailable'));
      expect(controller.fileEntries.single.value, 'second');
      expect(controller.exifEntries.single.value, 'Example');
      service.first.complete(Uint8List.fromList([1, 2, 3]));
      await old;
      expect(controller.name, 'second');
      expect(controller.fileEntries.single.value, 'second');
      controller.dispose();
    },
  );

  testWidgets('opens a real JPEG and extracts dimensions and EXIF', (
    tester,
  ) async {
    final controller = ViewerController(ViewerService());
    await tester.runAsync(() => controller.open('test/fixtures/exif.jpg'));
    expect(controller.previewError, isNull);
    expect(controller.bytes, isNotNull);
    expect(controller.imageEntries.single.value, '3 × 2 pixels');
    expect(
      controller.exifEntries.any(
        (entry) => entry.value.contains('musha test camera'),
      ),
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(home: ViewerScreen(controller: controller)),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('3 × 2 pixels'), findsOneWidget);
  });

  testWidgets('initial screen explains C2PA availability', (tester) async {
    await tester.pumpWidget(const ViewerApp());
    expect(find.text('Open an image to begin'), findsOneWidget);
    expect(
      find.text('Verification unavailable in this version.'),
      findsOneWidget,
    );
    expect(find.text('Open image'), findsOneWidget);
  });
}
