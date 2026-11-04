import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/raw_preview.dart';

Uint8List fixture({
  Endian endian = Endian.little,
  int? offset,
  int? size,
  int orientation = 6,
}) {
  final jpeg = <int>[
    0xff,
    0xd8,
    0xff,
    0xc0,
    0,
    11,
    8,
    0,
    3,
    0,
    5,
    1,
    1,
    0x11,
    0,
    0xff,
    0xd9,
  ];
  final b = Uint8List(80 + jpeg.length);
  final d = ByteData.sublistView(b);
  b[0] = b[1] = endian == Endian.little ? 0x49 : 0x4d;
  d.setUint16(2, 42, endian);
  d.setUint32(4, 8, endian);
  d.setUint16(8, 4, endian);
  void entry(int i, int tag, int type, int count, int value) {
    final o = 10 + i * 12;
    d.setUint16(o, tag, endian);
    d.setUint16(o + 2, type, endian);
    d.setUint32(o + 4, count, endian);
    if (type == 3 && count == 1) {
      d.setUint16(o + 8, value, endian);
    } else {
      d.setUint32(o + 8, value, endian);
    }
  }

  entry(0, 0x201, 4, 1, offset ?? 80);
  entry(1, 0x202, 4, 1, size ?? jpeg.length);
  entry(2, 0x112, 3, 1, orientation);
  entry(3, 34675, 7, 4, 0x04030201);
  b.setRange(80, b.length, jpeg);
  return b;
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('raw-preview-test');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<RawPreview> extract(Uint8List bytes) async {
    final f = File('${dir.path}/fixture.dng');
    await f.writeAsBytes(bytes);
    return extractRawPreview(f.path);
  }

  for (final endian in [Endian.little, Endian.big]) {
    test('extracts JPEG and TIFF metadata in $endian byte order', () async {
      final preview = await extract(fixture(endian: endian));
      expect((preview.width, preview.height), (5, 3));
      expect(preview.orientation, 6);
      expect(preview.iccProfile, hasLength(4));
      expect(preview.bytes.first, 0xff);
    });
    test('follows SubIFD pointers with TIFF IFD type in $endian', () async {
      final original = fixture(endian: endian);
      final data = Uint8List(120 + original.length - 80);
      final d = ByteData.sublistView(data);
      data.setRange(0, 8, original);
      d.setUint16(8, 1, endian);
      d.setUint16(10, 0x014a, endian);
      d.setUint16(12, 13, endian);
      d.setUint32(14, 1, endian);
      d.setUint32(18, 32, endian);
      data.setRange(32, 32 + 54, original, 8);
      d.setUint32(42, 120, endian);
      data.setRange(120, data.length, original, 80);
      expect((await extract(data)).width, 5);
    });
  }
  test('combines TIFF JPEG tables with a single JPEG strip', () async {
    final original = fixture();
    final data = Uint8List(200 + original.length - 80);
    data.setRange(0, 8, original);
    final d = ByteData.sublistView(data);
    const order = Endian.little;
    d.setUint16(8, 4, order);
    void entry(int index, int tag, int type, int count, int value) {
      final o = 10 + index * 12;
      d.setUint16(o, tag, order);
      d.setUint16(o + 2, type, order);
      d.setUint32(o + 4, count, order);
      if (type == 3) {
        d.setUint16(o + 8, value, order);
      } else {
        d.setUint32(o + 8, value, order);
      }
    }
    entry(0, 0x103, 3, 1, 7);
    entry(1, 0x111, 4, 1, 200);
    entry(2, 0x117, 4, 1, original.length - 80);
    // An abbreviated tables stream, with one DQT marker segment.
    final tables = <int>[
      0xff, 0xd8, 0xff, 0xdb, 0, 67, 0,
      ...List.filled(64, 1),
      0xff, 0xd9,
    ];
    entry(3, 347, 7, tables.length, 100);
    data.setRange(100, 100 + tables.length, tables);
    data.setRange(200, data.length, original, 80);
    final preview = await extract(data);
    expect(preview.bytes.sublist(0, 7), tables.sublist(0, 7));
    expect((preview.width, preview.height), (5, 3));
    data[105] = 250; // Invalid DQT segment length.
    await expectLater(extract(data), throwsA(isA<RawPreviewException>()));
  });
  test(
    'detects JPEG EXIF orientation separately from TIFF orientation',
    () async {
      expect((await extract(fixture())).hasJpegExifOrientation, isFalse);
      // APP1: Exif identifier followed by a little-endian TIFF IFD0.
      final app1 = <int>[
        0xff,
        0xe1,
        0,
        34,
        0x45,
        0x78,
        0x69,
        0x66,
        0,
        0,
        0x49,
        0x49,
        42,
        0,
        8,
        0,
        0,
        0,
        1,
        0,
        0x12,
        0x01,
        3,
        0,
        1,
        0,
        0,
        0,
        6,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ];
      final original = fixture();
      final data = Uint8List.fromList([
        ...original.sublist(0, 82),
        ...app1,
        ...original.sublist(82),
      ]);
      ByteData.sublistView(data).setUint32(30, data.length - 80, Endian.little);
      expect((await extract(data)).hasJpegExifOrientation, isTrue);
      // Invalid EXIF orientation values must not suppress TIFF orientation.
      data[82 + 28] = 9;
      expect((await extract(data)).hasJpegExifOrientation, isFalse);
    },
  );
  test('rejects invalid preview ranges and oversized previews', () async {
    for (final data in [
      fixture(offset: 9999),
      fixture(size: 65 * 1024 * 1024),
    ]) {
      await expectLater(extract(data), throwsA(isA<RawPreviewException>()));
    }
  });
  test(
    'rejects invalid headers, directory offsets, and excessive counts',
    () async {
      final invalid = fixture()..[0] = 0;
      final badOffset = fixture();
      ByteData.sublistView(badOffset).setUint32(4, 9999, Endian.little);
      final count = fixture();
      ByteData.sublistView(count).setUint16(8, 513, Endian.little);
      for (final data in [invalid, badOffset, count]) {
        await expectLater(extract(data), throwsA(isA<RawPreviewException>()));
      }
    },
  );
  test('rejects malformed JPEG', () async {
    final bytes = fixture()..[80] = 0;
    await expectLater(extract(bytes), throwsA(isA<RawPreviewException>()));
  });
  test('stops at JPEG EOI before nonzero strip padding', () async {
    final original = fixture();
    final scan = <int>[
      0xff, 0xda, 0, 2, // Start of scan.
      0x12, 0xff, 0, 0xd9, 0xff, 0xd0, 0x34,
      0xff, 0xd9,
    ];
    final padding = <int>[3, 0xff, 0xd9, 5];
    final data = Uint8List.fromList([
      ...original.sublist(0, original.length - 2),
      ...scan,
      ...padding,
    ]);
    ByteData.sublistView(data).setUint32(30, data.length - 80, Endian.little);
    final preview = await extract(data);
    expect(preview.bytes.length, data.length - 80 - padding.length);
    expect(preview.bytes.sublist(preview.bytes.length - 2), [0xff, 0xd9]);
  });
  test('does not choose lossless JPEG RAW data as a preview', () async {
    final data = fixture()..[83] = 0xc3;
    await expectLater(extract(data), throwsA(isA<RawPreviewException>()));
  });
}
