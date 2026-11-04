import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/raw_preview.dart';
import 'package:musha_viewer/viewer_controller.dart';

class _OnlineService extends ViewerService {
  _OnlineService(this.jpeg);
  final Uint8List jpeg;
  final original = Uint8List.fromList([8, 7, 6, 5]);
  final started = Completer<void>();
  final response = Completer<Map<String, dynamic>>();
  final offlineBytes = <Uint8List>[];
  final onlineBytes = <Uint8List>[];
  final onlineNames = <String>[];

  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<Uint8List> read(String path) async => jpeg;
  @override
  Future<Uint8List> readRawOriginal(String path) async => original;
  @override
  Future<RawPreview> rawPreview(String path) async =>
      RawPreview(bytes: jpeg, width: 3, height: 2);
  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async {
    offlineBytes.add(bytes);
    return {
      'status': name.startsWith('absent')
          ? 'absent'
          : name.startsWith('remote')
          ? 'remote'
          : 'present',
    };
  }

  @override
  Future<Map<String, dynamic>> c2paOnline(Uint8List bytes, String name) {
    onlineBytes.add(bytes);
    onlineNames.add(name);
    if (!started.isCompleted) started.complete();
    return response.future;
  }
}

void main() {
  testWidgets('online check is explicit and reuses the offline snapshot', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final service = _OnlineService(
        File('test/fixtures/exif.jpg').readAsBytesSync(),
      );
      final controller = ViewerController(service);
      await controller.open('present.jpg');
      expect(service.onlineBytes, isEmpty);
      expect(controller.canVerifyOnline, isTrue);
      final offline = controller.c2paResult;
      final check = controller.verifyOnline();
      await service.started.future;
      expect(controller.onlineVerifying, isTrue);
      expect(controller.canVerifyOnline, isFalse);
      await controller.verifyOnline();
      expect(service.onlineBytes, hasLength(1));
      expect(
        identical(service.onlineBytes.single, service.offlineBytes.single),
        isTrue,
      );
      expect(service.onlineNames.single, 'present.jpg');
      service.response.complete({'status': 'present', 'online_complete': true});
      await check;
      expect(
        controller.onlineStatus,
        'Requested network resources retrieved; trust and revocation remain unconfirmed',
      );
      expect(controller.c2paResult, same(offline));
      expect(controller.onlineVerifying, isFalse);
      controller.dispose();
    });
  });

  testWidgets('RAW online check uses original bytes, not the preview', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final service = _OnlineService(
        File('test/fixtures/exif.jpg').readAsBytesSync(),
      );
      final controller = ViewerController(service);
      await controller.open('remote.dng');
      expect(service.onlineBytes, isEmpty);
      expect(controller.canVerifyOnline, isTrue);
      final check = controller.verifyOnline();
      await service.started.future;
      expect(
        identical(service.onlineBytes.single, service.offlineBytes.single),
        isTrue,
      );
      expect(service.onlineBytes.single, orderedEquals(service.original));
      expect(service.onlineNames.single, 'remote.dng');
      service.response.complete({
        'status': 'remote',
        'online_complete': false,
        'online_error': 'unavailable',
      });
      await check;
      expect(controller.onlineStatus, contains('incomplete'));
      expect(controller.c2paResult?['status'], 'remote');
      controller.dispose();
    });
  });

  testWidgets('absent credentials cannot trigger an online request', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final service = _OnlineService(
        File('test/fixtures/exif.jpg').readAsBytesSync(),
      );
      final controller = ViewerController(service);
      await controller.open('absent.jpg');
      expect(controller.canVerifyOnline, isFalse);
      await controller.verifyOnline();
      expect(service.onlineBytes, isEmpty);
      controller.dispose();
    });
  });

  testWidgets('late online result is discarded after changing images', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final service = _OnlineService(
        File('test/fixtures/exif.jpg').readAsBytesSync(),
      );
      final controller = ViewerController(service);
      await controller.open('present.jpg');
      final check = controller.verifyOnline();
      await service.started.future;
      await controller.open('absent.jpg');
      service.response.complete({'status': 'present', 'online_complete': true});
      await check;
      expect(controller.name, 'absent.jpg');
      expect(controller.c2paResult?['status'], 'absent');
      expect(controller.onlineResult, isNull);
      expect(controller.onlineStatus, isNull);
      expect(controller.onlineVerifying, isFalse);
      controller.dispose();
    });
  });

  testWidgets('online errors leave offline verification intact', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final service = _OnlineService(
        File('test/fixtures/exif.jpg').readAsBytesSync(),
      );
      final controller = ViewerController(service);
      await controller.open('present.jpg');
      final offline = controller.c2paResult;
      final check = controller.verifyOnline();
      await service.started.future;
      service.response.completeError(StateError('connection failed'));
      await check;
      expect(controller.onlineStatus, contains('connection failed'));
      expect(controller.onlineResult, isNull);
      expect(controller.c2paResult, same(offline));
      expect(controller.onlineVerifying, isFalse);
      controller.dispose();
    });
  });
}
