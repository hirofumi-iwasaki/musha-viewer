import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/directory_navigation.dart';
import 'package:musha_viewer/viewer_controller.dart';

class FormatService extends ViewerService {
  FormatService(this.original, {this.converted});
  final Uint8List original;
  final Uint8List? converted;
  Uint8List? verified;
  Uint8List? examined;
  @override
  Future<List<MetadataEntry>> fileInfo(String path) async => [];
  @override
  Future<Uint8List> read(String path) async => original;
  @override
  Future<Uint8List> platformPreview(Uint8List bytes, String path) async {
    expect(bytes, same(original));
    return converted ?? (throw const FormatException('unsupported'));
  }

  @override
  Future<List<MetadataEntry>> exif(Uint8List bytes) async {
    examined = bytes;
    return [];
  }

  @override
  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) async {
    verified = bytes;
    return {'status': 'absent'};
  }
}

void main() {
  for (final extension in ['png', 'gif', 'webp']) {
    testWidgets('decodes $extension fixture', (tester) async {
      final bytes = await tester.runAsync(
        () => File('test/fixtures/format.$extension').readAsBytes(),
      );
      expect(bytes, isNotNull);
      final service = FormatService(bytes!);
      final controller = ViewerController(service);
      await tester.runAsync(() => controller.open('image.$extension'));
      expect(controller.previewError, isNull);
      expect(
        controller.imageEntries.map((e) => e.value),
        contains('2 × 3 pixels'),
      );
      expect(service.verified, same(bytes));
      controller.dispose();
    });
  }
  testWidgets(
    'flattened preview preserves original metadata and verification',
    (tester) async {
      final original = Uint8List.fromList([0, 1, 2]);
      final png = (await tester.runAsync(
        () => File('test/fixtures/format.png').readAsBytes(),
      ))!;
      final service = FormatService(original, converted: png);
      final controller = ViewerController(service);
      await tester.runAsync(() => controller.open('image.psd'));
      expect(controller.previewError, isNull);
      expect(controller.bytes, same(png));
      expect(service.verified, same(original));
      expect(service.examined, same(original));
      expect(
        controller.imageEntries.map((e) => e.value),
        contains('Platform preview (may be downsampled)'),
      );
      controller.dispose();
    },
  );
  test('PSD, HEIF and EPS are discoverable', () {
    for (final path in ['a.PSD', 'a.HEIF', 'a.eps']) {
      expect(isSupportedImagePath(path), isTrue);
    }
  });
  test(
    'extracts bounded DOS EPS embedded TIFF without interpreting PostScript',
    () {
      final eps = Uint8List(38);
      eps.setRange(0, 4, [0xc5, 0xd0, 0xd3, 0xc6]);
      final header = ByteData.sublistView(eps);
      header.setUint32(20, 30, Endian.little);
      header.setUint32(24, 8, Endian.little);
      eps.setRange(30, 38, [0x49, 0x49, 42, 0, 0, 0, 0, 0]);
      expect(extractEpsTiffPreview(eps), orderedEquals(eps.sublist(30)));
      header.setUint32(24, 9, Endian.little);
      expect(() => extractEpsTiffPreview(eps), throwsFormatException);
      header.setUint32(24, 8, Endian.little);
      header.setUint32(20, 0xfffffff0, Endian.little);
      expect(() => extractEpsTiffPreview(eps), throwsFormatException);
      expect(
        () => extractEpsTiffPreview(Uint8List.fromList('%!PS'.codeUnits)),
        throwsFormatException,
      );
    },
  );
}
