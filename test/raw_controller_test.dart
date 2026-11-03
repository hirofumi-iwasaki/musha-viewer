import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/raw_preview.dart';
import 'package:musha_viewer/viewer_controller.dart';

class RawService extends ViewerService {
  RawService(this.jpeg);
  final Uint8List jpeg;
  final original = Uint8List.fromList([1, 2, 3, 4]);
  bool failRead = false;
  final delayedPreview = Completer<RawPreview>();
  final delayedRead = Completer<Uint8List>();
  final oldReadStarted = Completer<void>();
  final reads = <String>[];
  Uint8List? verified;
  String? verifiedName;

  RawPreview get preview => RawPreview(bytes: jpeg, width: 3, height: 2);
  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<RawPreview> rawPreview(String path) =>
      path == 'old.dng' ? delayedPreview.future : Future.value(preview);
  @override
  Future<Uint8List> readRawOriginal(String path) {
    reads.add(path);
    if (path == 'old.dng') {
      oldReadStarted.complete();
      return delayedRead.future;
    }
    if (failRead) return Future.error(const FormatException('read failed'));
    return Future.value(original);
  }

  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async {
    verified = bytes;
    verifiedName = name;
    return {'status': name};
  }
}

void main() {
  late Uint8List jpeg;
  setUpAll(
    () async => jpeg = await File('test/fixtures/exif.jpg').readAsBytes(),
  );

  testWidgets('RAW preview survives an unavailable original', (tester) async {
    final service = RawService(jpeg)..failRead = true;
    final controller = ViewerController(service);
    await tester.runAsync(() => controller.open('photo.dng'));
    expect(controller.bytes, orderedEquals(jpeg));
    expect(controller.previewError, isNull);
    expect(
      controller.c2paStatus,
      contains('Original file verification unavailable'),
    );
    expect(service.verified, isNull);
    controller.dispose();
  });

  testWidgets('RAW verification receives original bytes', (tester) async {
    final service = RawService(jpeg);
    final controller = ViewerController(service);
    await tester.runAsync(() => controller.open('photo.dng'));
    expect(controller.bytes, orderedEquals(jpeg));
    expect(service.verified, orderedEquals(service.original));
    expect(service.verifiedName, 'photo.dng');
    expect(controller.c2paResult?['status'], 'photo.dng');
    controller.dispose();
  });

  testWidgets('late RAW preview and original cannot replace current image', (
    tester,
  ) async {
    late RawService service;
    late ViewerController controller;
    await tester.runAsync(() async {
      service = RawService(jpeg);
      controller = ViewerController(service);
      final old = controller.open('old.dng');
      await service.oldReadStarted.future;
      final current = controller.open('new.dng');
      await Future<void>.delayed(Duration.zero);
      expect(service.reads, ['old.dng']);
      service.delayedRead.complete(Uint8List.fromList([9]));
      service.delayedPreview.complete(service.preview);
      await Future.wait([old, current]);
    });
    expect(service.reads, ['old.dng', 'new.dng']);
    expect(controller.name, 'new.dng');
    expect(controller.bytes, orderedEquals(jpeg));
    expect(controller.c2paResult?['status'], 'new.dng');
    expect(service.verifiedName, 'new.dng');
    controller.dispose();
  });
}
