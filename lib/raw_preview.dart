import 'dart:io';
import 'dart:typed_data';

/// An embedded JPEG preview, not a developed RAW image.
class RawPreview {
  const RawPreview({
    required this.bytes,
    required this.width,
    required this.height,
    this.orientation,
    this.iccProfile,
    this.hasJpegExifOrientation = false,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  /// TIFF orientation (1–8), when present.
  final int? orientation;

  /// TIFF ICC profile, when present and within the size limit.
  final Uint8List? iccProfile;

  /// Whether the JPEG itself specifies an EXIF orientation.
  final bool hasJpegExifOrientation;
}

class RawPreviewException implements Exception {
  const RawPreviewException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads classic TIFF-based DNG/NEF IFDs and returns the largest valid JPEG.
/// File data is accessed by range; neither the RAW file nor untrusted TIFF
/// counts are loaded wholesale. BigTIFF and non-JPEG previews are unsupported.
Future<RawPreview> extractRawPreview(String path) async {
  final file = await File(path).open();
  try {
    return await _Reader(file, await file.length()).extract();
  } finally {
    await file.close();
  }
}

class _Reader {
  _Reader(this.file, this.length);
  final RandomAccessFile file;
  final int length;
  static const maxPreviewBytes = 64 * 1024 * 1024;
  static const maxProfileBytes = 4 * 1024 * 1024;
  static const maxIfds = 128;
  static const maxEntries = 512;
  late Endian endian;

  Future<Uint8List> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw const RawPreviewException('Invalid RAW TIFF offset or length.');
    }
    await file.setPosition(offset);
    final bytes = await file.read(count);
    if (bytes.length != count) {
      throw const RawPreviewException('Truncated RAW file.');
    }
    return bytes;
  }

  int u16(Uint8List b, int o) => ByteData.sublistView(b).getUint16(o, endian);
  int u32(Uint8List b, int o) => ByteData.sublistView(b).getUint32(o, endian);

  Future<RawPreview> extract() async {
    final h = await read(0, 8);
    if (h[0] == 0x49 && h[1] == 0x49) {
      endian = Endian.little;
    } else if (h[0] == 0x4d && h[1] == 0x4d) {
      endian = Endian.big;
    } else {
      throw const RawPreviewException('Invalid RAW TIFF header.');
    }
    if (u16(h, 2) != 42) {
      throw const RawPreviewException('Unsupported RAW TIFF format.');
    }
    final pending = <int>[u32(h, 4)];
    final visited = <int>{};
    final candidates = <_Candidate>[];
    int? rootOrientation;
    Uint8List? rootIcc;
    while (pending.isNotEmpty) {
      final offset = pending.removeLast();
      if (offset == 0 || !visited.add(offset)) continue;
      if (visited.length > maxIfds) {
        throw const RawPreviewException(
          'RAW contains too many TIFF directories.',
        );
      }
      final count = u16(await read(offset, 2), 0);
      if (count > maxEntries) {
        throw const RawPreviewException('RAW TIFF directory is too large.');
      }
      final entries = await read(offset + 2, count * 12 + 4);
      int? jpegOffset,
          jpegLength,
          orientation,
          compression,
          stripOffset,
          stripLength;
      Uint8List? icc;
      for (var i = 0; i < count; i++) {
        final o = i * 12;
        final tag = u16(entries, o),
            type = u16(entries, o + 2),
            n = u32(entries, o + 4);
        if (tag == 34675 &&
            (type == 1 || type == 7) &&
            n > 0 &&
            n <= maxProfileBytes) {
          icc = n <= 4
              ? Uint8List.fromList(entries.sublist(o + 8, o + 8 + n))
              : await read(u32(entries, o + 8), n);
        }
        if (!const {
              0x0112,
              0x0103,
              0x0201,
              0x0202,
              0x0111,
              0x0117,
              0x014a,
              0x8769,
            }.contains(tag) ||
            (type != 3 && type != 4)) {
          continue;
        }
        final size = type == 3 ? 2 : 4;
        if (n == 0 || n > maxEntries) continue;
        final data = n * size <= 4
            ? Uint8List.sublistView(entries, o + 8, o + 8 + n * size)
            : await read(u32(entries, o + 8), n * size);
        int value(int j) =>
            type == 3 ? u16(data, j * size) : u32(data, j * size);
        switch (tag) {
          case 0x0112:
            orientation = value(0);
            break;
          case 0x0103:
            compression = value(0);
            break;
          case 0x0201:
            jpegOffset = value(0);
            break;
          case 0x0202:
            jpegLength = value(0);
            break;
          case 0x0111:
            if (n == 1) stripOffset = value(0);
            break;
          case 0x0117:
            if (n == 1) stripLength = value(0);
            break;
          case 0x014a:
          case 0x8769:
            for (var j = 0; j < n; j++) {
              pending.add(value(j));
            }
            break;
        }
      }
      if (visited.length == 1) {
        rootOrientation = orientation;
        rootIcc = icc;
      }
      final next = u32(entries, count * 12);
      if (next != 0) pending.add(next);
      if (jpegOffset != null && jpegLength != null) {
        candidates.add(_Candidate(jpegOffset, jpegLength, orientation, icc));
      } else if ((compression == 6 || compression == 7) &&
          stripOffset != null &&
          stripLength != null) {
        candidates.add(_Candidate(stripOffset, stripLength, orientation, icc));
      }
    }
    RawPreview? best;
    for (final c in candidates) {
      if (c.size < 4 ||
          c.size > maxPreviewBytes ||
          c.offset > length ||
          c.size > length - c.offset) {
        continue;
      }
      final bytes = await read(c.offset, c.size);
      final dimensions = _jpegDimensions(bytes);
      if (dimensions == null) continue;
      final orientation = c.orientation ?? rootOrientation;
      final preview = RawPreview(
        bytes: bytes,
        width: dimensions.$1,
        height: dimensions.$2,
        orientation: orientation != null && orientation >= 1 && orientation <= 8
            ? orientation
            : null,
        iccProfile: c.icc ?? rootIcc,
        hasJpegExifOrientation: _hasJpegExifOrientation(bytes),
      );
      if (best == null ||
          preview.width * preview.height > best.width * best.height) {
        best = preview;
      }
    }
    if (best == null) {
      throw const RawPreviewException(
        'No valid embedded JPEG preview found in RAW file.',
      );
    }
    return best;
  }
}

class _Candidate {
  _Candidate(this.offset, this.size, this.orientation, this.icc);
  final int offset, size;
  final int? orientation;
  final Uint8List? icc;
}

(int, int)? _jpegDimensions(Uint8List b) {
  if (b.length < 4 ||
      b[0] != 0xff ||
      b[1] != 0xd8 ||
      b[b.length - 2] != 0xff ||
      b.last != 0xd9) {
    return null;
  }
  var p = 2;
  while (p + 1 < b.length) {
    if (b[p++] != 0xff) return null;
    while (p < b.length && b[p] == 0xff) {
      p++;
    }
    if (p >= b.length) return null;
    final marker = b[p++];
    if (marker == 0xd9 || marker == 0xda) return null;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (p + 2 > b.length) return null;
    final size = (b[p] << 8) | b[p + 1];
    if (size < 2 || p + size > b.length) return null;
    if ((marker >= 0xc0 && marker <= 0xc3) ||
        (marker >= 0xc5 && marker <= 0xc7) ||
        (marker >= 0xc9 && marker <= 0xcb) ||
        (marker >= 0xcd && marker <= 0xcf)) {
      if (size < 8) return null;
      final height = (b[p + 3] << 8) | b[p + 4],
          width = (b[p + 5] << 8) | b[p + 6];
      return width > 0 && height > 0 ? (width, height) : null;
    }
    p += size;
  }
  return null;
}

// Inspect only the JPEG APP1 EXIF IFD0. All offsets are relative to the APP1
// TIFF header and must remain within that marker's declared payload.
bool _hasJpegExifOrientation(Uint8List b) {
  var p = 2;
  while (p + 4 <= b.length && b[p] == 0xff) {
    while (p < b.length && b[p] == 0xff) {
      p++;
    }
    if (p >= b.length) return false;
    final marker = b[p++];
    if (marker == 0xda || marker == 0xd9) return false;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (p + 2 > b.length) return false;
    final size = (b[p] << 8) | b[p + 1];
    final end = p + size;
    if (size < 2 || end > b.length) return false;
    final start = p + 2;
    if (marker == 0xe1 &&
        end - start >= 14 &&
        b[start] == 0x45 &&
        b[start + 1] == 0x78 &&
        b[start + 2] == 0x69 &&
        b[start + 3] == 0x66 &&
        b[start + 4] == 0 &&
        b[start + 5] == 0) {
      final tiff = start + 6;
      Endian? order;
      if (b[tiff] == 0x49 && b[tiff + 1] == 0x49) order = Endian.little;
      if (b[tiff] == 0x4d && b[tiff + 1] == 0x4d) order = Endian.big;
      if (order != null) {
        final data = ByteData.sublistView(b);
        if (data.getUint16(tiff + 2, order) == 42) {
          final offset = data.getUint32(tiff + 4, order);
          final ifd = tiff + offset;
          if (offset >= 8 && ifd + 2 <= end) {
            final count = data.getUint16(ifd, order);
            if (count <= (end - ifd - 2) ~/ 12) {
              for (var i = 0; i < count; i++) {
                final entry = ifd + 2 + i * 12;
                if (data.getUint16(entry, order) == 0x0112 &&
                    data.getUint16(entry + 2, order) == 3 &&
                    data.getUint32(entry + 4, order) == 1) {
                  final orientation = data.getUint16(entry + 8, order);
                  if (orientation >= 1 && orientation <= 8) return true;
                }
              }
            }
          }
        }
      }
    }
    p = end;
  }
  return false;
}
