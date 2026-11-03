import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/viewer_controller.dart';

class _Service extends ViewerService {
  @override
  Future<Uint8List> read(String path) async => Uint8List(0);
  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async => {};
}

Future<void> _waitFor(
  ViewerController controller,
  bool Function() predicate,
) async {
  if (predicate()) return;
  final done = Completer<void>();
  void listener() {
    if (predicate() && !done.isCompleted) done.complete();
  }

  controller.addListener(listener);
  try {
    if (predicate()) return;
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    controller.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening an image discovers siblings in natural order and stops at boundaries', () async {
    final dir = await Directory.systemTemp.createTemp('controller_navigation');
    final controller = ViewerController(_Service());
    try {
      for (final name in [
        'image1.jpg',
        'image2.jpg',
        'image10.jpg',
        'ignore.txt',
      ]) {
        await File('${dir.path}/$name').writeAsBytes([]);
      }
      await controller.open('${dir.path}/image2.jpg');
      await _waitFor(controller, () => controller.imageCount == 3);
      expect(controller.currentIndex, 1);
      expect(controller.canPrevious, isTrue);
      expect(controller.canNext, isTrue);
      await controller.previous();
      expect(controller.name, 'image1.jpg');
      expect(controller.canPrevious, isFalse);
      await controller.previous();
      expect(controller.name, 'image1.jpg');
      await controller.next();
      await controller.next();
      expect(controller.name, 'image10.jpg');
      expect(controller.canNext, isFalse);
      await controller.next();
      expect(controller.name, 'image10.jpg');
    } finally {
      controller.dispose();
      await dir.delete(recursive: true);
    }
  });

  test(
    'explicit folder authorization replaces the discovered folder',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'controller_authorize',
      );
      final controller = ViewerController(_Service());
      try {
        final first = await Directory('${root.path}/first').create();
        final second = await Directory('${root.path}/second').create();
        await File('${first.path}/a.jpg').writeAsBytes([]);
        await File('${second.path}/2.jpg').writeAsBytes([]);
        await File('${second.path}/10.jpg').writeAsBytes([]);
        await controller.open('${first.path}/a.jpg');
        await controller.authorizeDirectory(second.path);
        expect(controller.name, '2.jpg');
        expect(controller.imageCount, 2);
        expect(controller.currentIndex, 0);
        await controller.next();
        expect(controller.name, '10.jpg');
      } finally {
        controller.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
