import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';

import 'c2pa.dart';

class MetadataEntry {
  const MetadataEntry(this.group, this.key, this.value);
  final String group;
  final String key;
  final String value;
}

/// Reads a bounded snapshot. The source file is never opened for writing.
class ViewerService {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxPixels = 40 * 1000 * 1000;

  Future<List<MetadataEntry>> fileInfo(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FileSystemException('Not a regular file');
    }
    return [
      MetadataEntry('File', 'Name', path.split(Platform.pathSeparator).last),
      MetadataEntry('File', 'Size', '${stat.size} bytes'),
      MetadataEntry('File', 'Modified', stat.modified.toLocal().toString()),
    ];
  }

  Future<Uint8List> read(String path) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in File(path).openRead()) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const FormatException('File exceeds the 64 MiB reading limit');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) =>
      verifyC2pa(bytes, name);

  Future<List<MetadataEntry>> exif(Uint8List bytes) =>
      compute(_extractExif, bytes);
}

Future<List<MetadataEntry>> _extractExif(Uint8List bytes) async {
  final tags = await readExifFromBytes(bytes);
  return [
    for (final tag in tags.entries)
      MetadataEntry('EXIF', tag.key, tag.value.printable),
  ];
}

class ViewerController extends ChangeNotifier {
  ViewerController(this.service);
  final ViewerService service;
  int _session = 0;
  bool _disposed = false;
  String? name;
  Uint8List? bytes;
  List<MetadataEntry> fileEntries = [], exifEntries = [], imageEntries = [];
  String? fileError, previewError, exifStatus;
  bool loading = false;
  Map<String, dynamic>? c2paResult;
  String c2paStatus = 'Select an image to verify.';

  bool _current(int id) => !_disposed && id == _session;
  void _update(int id, void Function() change) {
    if (_current(id)) {
      change();
      notifyListeners();
    }
  }

  Future<void> open(String path) async {
    final id = ++_session;
    name = path.split(Platform.pathSeparator).last;
    bytes = null;
    fileEntries = [];
    exifEntries = [];
    imageEntries = [];
    fileError = null;
    previewError = null;
    exifStatus = 'Reading EXIF…';
    loading = true;
    c2paResult = null;
    c2paStatus = 'Verifying…';
    notifyListeners();
    final info = service
        .fileInfo(path)
        .then(
          (value) {
            _update(id, () => fileEntries = value);
          },
          onError: (Object error) {
            _update(
              id,
              () => fileError = 'File information unavailable: $error',
            );
          },
        );
    try {
      final data = await service.read(path);
      if (!_current(id)) return;
      final verification = service
          .c2pa(data, name!)
          .then(
            (value) {
              _update(id, () {
                c2paResult = value;
                c2paStatus = 'Offline verification';
              });
            },
            onError: (Object error) {
              _update(
                id,
                () => c2paStatus = 'Verification unavailable: $error',
              );
            },
          );
      final metadata = service
          .exif(data)
          .then(
            (value) {
              _update(id, () {
                exifEntries = value;
                exifStatus = value.isEmpty
                    ? 'No EXIF tags returned by the parser.'
                    : null;
              });
            },
            onError: (Object error) {
              _update(id, () => exifStatus = 'EXIF could not be read: $error');
            },
          );
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            if (descriptor.width * descriptor.height >
                ViewerService.maxPixels) {
              throw const FormatException(
                'Image exceeds the 40 megapixel preview limit',
              );
            }
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
        if (!_current(id)) return;
        final codec = await ui.instantiateImageCodec(data);
        try {
          final frame = await codec.getNextFrame();
          final width = frame.image.width, height = frame.image.height;
          frame.image.dispose();
          _update(id, () {
            bytes = data;
            imageEntries = [
              MetadataEntry(
                'Image',
                'Decoded dimensions',
                '$width × $height pixels',
              ),
            ];
            loading = false;
          });
        } finally {
          codec.dispose();
        }
      } catch (error) {
        _update(id, () {
          previewError = 'Image preview unavailable: $error';
          loading = false;
        });
      }
      await Future.wait([metadata, verification]);
    } catch (error) {
      _update(id, () {
        previewError = 'Could not read image: $error';
        exifStatus = 'EXIF unavailable because the file could not be read.';
        c2paStatus =
            'Verification unavailable because the file could not be read.';
        loading = false;
      });
    }
    await info;
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    super.dispose();
  }
}
