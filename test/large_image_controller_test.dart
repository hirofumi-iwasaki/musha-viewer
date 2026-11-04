import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/raw_preview.dart';
import 'package:musha_viewer/viewer_controller.dart';

class LargeImageService extends ViewerService {
  LargeImageService(this.image);
  final Uint8List image;
  final original = Uint8List.fromList([1, 2, 3]);
  Uint8List? verified;

  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<Uint8List> read(String path) async => image;
  @override
  Future<RawPreview> rawPreview(String path) async =>
      RawPreview(bytes: image, width: 6401, height: 6250);
  @override
  Future<Uint8List> readRawOriginal(String path) async => original;
  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async => [];
  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async {
    verified = bytes;
    return {'status': 'verified'};
  }
}

void main() {
  late Uint8List image;
  setUpAll(() async {
    image = await File('test/fixtures/large_dimensions.jpg').readAsBytes();
  });

  for (final path in ['large.jpg', 'large.dng']) {
    testWidgets('opens a preview over 40 megapixels: $path', (tester) async {
      final service = LargeImageService(image);
      final controller = ViewerController(service);
      await tester.runAsync(() => controller.open(path));
      expect(controller.previewError, isNull);
      expect(controller.bytes, orderedEquals(image));
      expect(
        controller.imageEntries.map((entry) => entry.value),
        contains('6401 × 6250 pixels'),
      );
      expect(
        service.verified,
        orderedEquals(path.endsWith('.dng') ? service.original : image),
      );
      expect(controller.c2paResult?['status'], 'verified');
      controller.dispose();
    });
  }
}
