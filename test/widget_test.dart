import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class FakeService extends ViewerService {
  final first = Completer<Uint8List>();
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async => {
    'status': name,
  };
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

class RealImageService extends ViewerService {
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async => {
    'status': 'absent',
  };
}

class DelayedVerificationService extends ViewerService {
  final delayed = Completer<Map<String, dynamic>>();
  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<Uint8List> read(String path) async => Uint8List.fromList([1, 2, 3]);
  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) =>
      name == 'first' ? delayed.future : Future.value({'status': 'second'});
}

void main() {
  testWidgets('lifecycle exit waits for settings flush', (tester) async {
    final done = Completer<void>();
    final listener = registerExitHandler(() => done.future);
    var returned = false;
    final result = tester.binding.handleRequestAppExit().then((value) {
      returned = true;
      return value;
    });
    await tester.pump();
    expect(returned, false);
    done.complete();
    await tester.pump();
    expect(await result, AppExitResponse.exit);
    listener.dispose();
  });
  test('drop validation rejects multiple items and folders', () {
    expect(dropRejection([]), isNotNull);
    expect(dropRejection([DropItemDirectory('/tmp/folder', [])]), isNotNull);
    expect(dropRejection([DropItemFile('/a'), DropItemFile('/b')]), isNotNull);
    expect(dropRejection([DropItemFile('/a')]), isNull);
  });
  testWidgets('late C2PA result cannot replace current file', (tester) async {
    final service = DelayedVerificationService();
    final controller = ViewerController(service);
    final first = controller.open('first');
    await tester.pump();
    await controller.open('second');
    service.delayed.complete({'status': 'first'});
    await first;
    expect(controller.c2paResult?['status'], 'second');
    controller.dispose();
  });
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
    final controller = ViewerController(RealImageService());
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
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('3 × 2 pixels'), findsOneWidget);
  });

  testWidgets('initial screen explains C2PA availability', (tester) async {
    await tester.pumpWidget(const ViewerApp());
    expect(find.text('Open an image to begin'), findsOneWidget);
    expect(find.text('Select an image to verify.'), findsOneWidget);
    expect(find.text('Open image'), findsOneWidget);
  });
}
