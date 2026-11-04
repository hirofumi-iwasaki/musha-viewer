import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'c2pa.dart';
import 'directory_navigation.dart';
import 'raw_preview.dart';

class MetadataEntry {
  const MetadataEntry(this.group, this.key, this.value);
  final String group;
  final String key;
  final String value;
}

/// Reads a bounded snapshot. The source file is never opened for writing.
class ViewerService {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxRawBytes = 256 * 1024 * 1024;

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

  Future<Uint8List> read(String path) => _readBounded(path, maxBytes);
  Future<Uint8List> readRawOriginal(String path) =>
      _readBounded(path, maxRawBytes);

  Future<Uint8List> _readBounded(String path, int limit) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in File(path).openRead()) {
      total += chunk.length;
      if (total > limit) {
        throw FormatException(
          'File exceeds the ${limit ~/ (1024 * 1024)} MiB reading limit',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<RawPreview> rawPreview(String path) => extractRawPreview(path);

  /// Decode the first flattened image using macOS ImageIO, where available.
  /// Original bytes remain the input to metadata and verification.
  Future<Uint8List?> platformPreview(Uint8List bytes, String path) async {
    if (!Platform.isMacOS ||
        !RegExp(r'\.(tiff?|psd|eps)$', caseSensitive: false).hasMatch(path)) {
      return null;
    }
    final input = RegExp(r'\.eps$', caseSensitive: false).hasMatch(path)
        ? extractEpsTiffPreview(bytes)
        : bytes;
    return await const MethodChannel('musha_viewer/image_preview')
            .invokeMethod<Uint8List>('decode', input) ??
        (throw const FormatException('No platform preview returned'));
  }

  Future<Map<String, dynamic>> c2pa(Uint8List bytes, String name) =>
      verifyC2pa(bytes, name);

  Future<Map<String, dynamic>> c2paOnline(Uint8List bytes, String name) =>
      verifyC2paOnline(bytes, name);

  Future<List<MetadataEntry>> exif(Uint8List bytes) =>
      compute(_extractExif, bytes);
}

/// Returns the embedded TIFF from a binary DOS EPS. PostScript is never run.
Uint8List extractEpsTiffPreview(Uint8List bytes) {
  if (bytes.length < 30 ||
      bytes[0] != 0xc5 ||
      bytes[1] != 0xd0 ||
      bytes[2] != 0xd3 ||
      bytes[3] != 0xc6) {
    throw const FormatException('EPS has no embedded TIFF preview');
  }
  final header = ByteData.sublistView(bytes);
  final offset = header.getUint32(20, Endian.little);
  final length = header.getUint32(24, Endian.little);
  if (offset < 30 ||
      length < 8 ||
      offset > bytes.length ||
      length > bytes.length - offset) {
    throw const FormatException('EPS has no valid embedded TIFF preview');
  }
  final tiff = Uint8List.sublistView(bytes, offset, offset + length);
  final little = tiff[0] == 0x49 && tiff[1] == 0x49;
  final big = tiff[0] == 0x4d && tiff[1] == 0x4d;
  if (!little && !big) {
    throw const FormatException('EPS has no valid embedded TIFF preview');
  }
  final magic = ByteData.sublistView(tiff)
      .getUint16(2, little ? Endian.little : Endian.big);
  if (magic != 42 && magic != 43) {
    throw const FormatException('EPS has no valid embedded TIFF preview');
  }
  return tiff;
}

Future<List<MetadataEntry>> _extractExif(Uint8List bytes) async {
  final tags = await readExifFromBytes(bytes);
  return [
    for (final tag in tags.entries)
      MetadataEntry('EXIF', tag.key, tag.value.printable),
  ];
}

// Validate that the first frame can be decoded without holding a second
// full-resolution copy alongside the image used by the viewer.
Future<({int width, int height})> _validatePreview(Uint8List data) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(data);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final dimensions = (width: descriptor.width, height: descriptor.height);
      final codec = await descriptor.instantiateCodec(
        targetWidth: 1,
        targetHeight: 1,
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      return dimensions;
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

class ViewerController extends ChangeNotifier {
  ViewerController(this.service);
  final ViewerService service;
  static Future<void> _rawWork = Future.value();
  int _session = 0;
  int _directorySession = 0;
  DirectoryNavigation? _directory;
  final _previewCache = AdjacentPreviewCache<_CachedPreview>(
    sizeOf: (p) => p.bytes.length + (p.raw?.iccProfile?.length ?? 0),
  );
  int? previewOrientation;
  Future<void>? _directoryDiscovery;
  Future<void> waitForDirectoryDiscovery() async {
    await _directoryDiscovery;
  }

  String? directoryStatus;
  String? get currentPath => _currentPath;
  bool get directoryNeedsPermission => directoryStatus == _directoryAccessError;
  static const _directoryAccessError =
      'Folder access unavailable. Use Authorize folder to navigate adjacent images.';
  bool get c2paVisibility =>
      c2paResult != null &&
          c2paResult!['status'] != 'absent' &&
          c2paResult!['status'] != 'unsupported' ||
      c2paResult == null && c2paStatus.startsWith('Verification unavailable') ||
      c2paResult == null &&
          c2paStatus.startsWith('Original file verification unavailable');
  int get currentIndex => _directory?.index ?? -1;
  int get imageCount => _directory?.paths.length ?? 0;
  bool get canPrevious => _directory?.previous != null;
  bool get canNext => _directory?.next != null;

  Future<void> authorizeDirectory(String path) async {
    final id = ++_directorySession;
    final openSession = _session;
    final directory = await DirectoryNavigation.fromDirectory(
      path,
      current: _currentPath,
    );
    if (_disposed || id != _directorySession || openSession != _session) return;
    _directory = directory;
    directoryStatus = directory.paths.isEmpty
        ? 'No supported images in this folder.'
        : null;
    _previewCache.invalidate();
    if (directory.index < 0 && directory.paths.isNotEmpty) {
      directory.select(directory.paths.first);
      await open(directory.paths.first);
    } else {
      notifyListeners();
      _prefetch();
    }
  }

  Future<void> _discoverDirectory(String path, int session, int request) async {
    try {
      final directory = await DirectoryNavigation.fromDirectory(
        File(path).parent.path,
        current: path,
      );
      if (!_current(session) || request != _directorySession) return;
      if (directory.index < 0) {
        throw const FileSystemException(
          'Image not present in accessible folder',
        );
      }
      _directory = directory;
      directoryStatus = null;
      notifyListeners();
      _prefetch();
    } catch (_) {
      if (!_current(session) || request != _directorySession) return;
      directoryStatus = _directoryAccessError;
      notifyListeners();
    }
  }

  Future<void> previous() async {
    final path = _directory?.movePrevious();
    if (path != null) await open(path);
  }

  Future<void> next() async {
    final path = _directory?.moveNext();
    if (path != null) await open(path);
  }

  String? _currentPath;
  bool _isRaw(String path) =>
      RegExp(r'\.(dng|nef)$', caseSensitive: false).hasMatch(path);
  Future<_CachedPreview> _loadPreview(String path) async {
    final before = await File(path).stat();
    if (before.type != FileSystemEntityType.file) {
      throw const FileSystemException('Not a regular file');
    }
    final raw = _isRaw(path) ? await service.rawPreview(path) : null;
    final data = raw?.bytes ?? await service.read(path);
    final after = await File(path).stat();
    if (before.size != after.size || before.modified != after.modified) {
      throw const FileSystemException('File changed during prefetch');
    }
    return _CachedPreview(data, raw, after.size, after.modified);
  }

  void _prefetch() {
    final directory = _directory;
    if (directory == null) return;
    unawaited(
      _previewCache.prefetch([
        if (directory.previous != null) directory.previous!,
        if (directory.next != null) directory.next!,
      ], _loadPreview),
    );
  }

  bool _disposed = false;
  String? name;
  Uint8List? bytes;
  List<MetadataEntry> fileEntries = [], exifEntries = [], imageEntries = [];
  String? fileError, previewError, exifStatus;
  bool loading = false;
  Map<String, dynamic>? c2paResult;
  Map<String, dynamic>? onlineResult;
  String? onlineStatus;
  bool onlineVerifying = false;
  Uint8List? _onlineBytes;
  bool get canVerifyOnline => _onlineBytes != null && !onlineVerifying;

  Future<void> verifyOnline() async {
    final snapshot = _onlineBytes;
    final currentName = name;
    if (snapshot == null || currentName == null || onlineVerifying) return;
    final id = _session;
    onlineVerifying = true;
    onlineStatus = 'Online verification in progress…';
    onlineResult = null;
    notifyListeners();
    final previous = _rawWork;
    final operation = previous.catchError((Object _) {}).then((_) async {
      if (!_current(id)) return;
      try {
        final value = await service.c2paOnline(snapshot, currentName);
        _update(id, () {
          onlineResult = value;
          onlineStatus =
              value['online_complete'] != true ||
                  value['status'] == 'error' ||
                  value['status'] == 'remote'
              ? 'Online check incomplete: ${value['online_error'] ?? 'Some information was unavailable.'}'
              : value['online_ocsp_status'] == 'revoked'
              ? 'Live Leica revocation check: revoked; trust remains unknown'
              : value['online_ocsp_status'] == 'good'
              ? 'Live certificate revocation check passed; overall trust remains unknown'
              : 'Requested network resources retrieved; trust and revocation remain unconfirmed';
          onlineVerifying = false;
        });
      } catch (error) {
        _update(id, () {
          onlineStatus = 'Online check unavailable: $error';
          onlineVerifying = false;
        });
      }
    });
    _rawWork = operation;
    await operation;
  }

  void _retainOnlineSnapshot(Uint8List data, Map<String, dynamic> result) {
    final status = result['status'];
    _onlineBytes = status == 'present' || status == 'remote' ? data : null;
  }

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
    _currentPath = path;
    if (_directory != null && !_directory!.select(path)) {
      _directory = null;
      _directorySession++;
      _previewCache.invalidate();
    }
    var cached = _previewCache.get(path);
    if (cached != null) {
      try {
        final stat = await File(path).stat();
        if (!_current(id)) return;
        if (stat.type != FileSystemEntityType.file ||
            stat.size != cached.size ||
            stat.modified != cached.modified) {
          cached = null;
        }
      } catch (_) {
        cached = null;
      }
    }
    _prefetch();
    previewOrientation = null;
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
    onlineResult = null;
    onlineStatus = null;
    onlineVerifying = false;
    _onlineBytes = null;
    c2paStatus = 'Verifying…';
    directoryStatus = null;
    notifyListeners();
    _directoryDiscovery = null;
    if (_directory == null) {
      final request = ++_directorySession;
      _directoryDiscovery = _discoverDirectory(path, id, request);
    }
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
    if (_isRaw(path)) {
      await _openRaw(path, id, cached);
      await info;
      return;
    }
    try {
      final data = cached?.bytes ?? await service.read(path);
      if (!_current(id)) return;
      final verification = service
          .c2pa(data, name!)
          .then(
            (value) {
              _update(id, () {
                c2paResult = value;
                _retainOnlineSnapshot(data, value);
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
        var preview = data;
        var converted = false;
        late ({int width, int height}) dimensions;
        try {
          dimensions = await _validatePreview(preview);
        } catch (error, stack) {
          final platformPreview = await service.platformPreview(data, path);
          if (platformPreview == null) Error.throwWithStackTrace(error, stack);
          preview = platformPreview;
          dimensions = await _validatePreview(preview);
          converted = true;
        }
        _update(id, () {
          bytes = preview;
          imageEntries = [
            if (converted)
              const MetadataEntry(
                'Image',
                'Preview',
                'Platform preview (may be downsampled)',
              ),
            MetadataEntry(
              'Image',
              'Decoded dimensions',
              '${dimensions.width} × ${dimensions.height} pixels',
            ),
          ];
          loading = false;
        });
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

  Future<void> _openRaw(String path, int id, _CachedPreview? cached) async {
    // The preview is independent of whole-file verification: large RAW files
    // can still be displayed when the bounded original snapshot is unavailable.
    final previousRawWork = _rawWork;
    final original = previousRawWork.catchError((Object _) {}).then((_) async {
      if (!_current(id)) return;
      await service
          .readRawOriginal(path)
          .then(
            (data) async {
              if (!_current(id)) return;
              await Future.wait([
                service
                    .exif(data)
                    .then(
                      (entries) {
                        _update(id, () {
                          exifEntries = entries;
                          exifStatus = entries.isEmpty
                              ? 'No EXIF tags returned by the parser.'
                              : null;
                        });
                      },
                      onError: (Object error) {
                        _update(
                          id,
                          () => exifStatus = 'EXIF could not be read: $error',
                        );
                      },
                    ),
                service
                    .c2pa(data, name!)
                    .then(
                      (value) {
                        _update(id, () {
                          c2paResult = value;
                          _retainOnlineSnapshot(data, value);
                          c2paStatus = 'Offline verification of original file';
                        });
                      },
                      onError: (Object error) {
                        _update(
                          id,
                          () => c2paStatus = 'Verification unavailable: $error',
                        );
                      },
                    ),
              ]);
            },
            onError: (Object error) {
              _update(id, () {
                exifStatus = 'EXIF unavailable: $error';
                c2paStatus = 'Original file verification unavailable: $error';
              });
            },
          );
    });
    _rawWork = original;
    try {
      final preview = cached?.raw ?? await service.rawPreview(path);
      if (!_current(id)) return;
      final dimensions = await _validatePreview(preview.bytes);
      _update(id, () {
        bytes = preview.bytes;
        previewOrientation = preview.hasJpegExifOrientation
            ? null
            : preview.orientation;
        imageEntries = [
          MetadataEntry(
            'Image',
            'Preview source',
            'Embedded RAW JPEG (not developed RAW)',
          ),
          MetadataEntry(
            'Image',
            'Decoded preview dimensions',
            '${dimensions.width} × ${dimensions.height} pixels',
          ),
          if (preview.orientation != null)
            MetadataEntry(
              'Image',
              'TIFF orientation',
              '${preview.orientation}',
            ),
          MetadataEntry(
            'Image',
            'TIFF ICC profile',
            preview.iccProfile == null
                ? 'Not present or unsupported'
                : 'Present; not applied separately',
          ),
        ];
        loading = false;
      });
    } catch (error) {
      _update(id, () {
        previewError = 'Embedded RAW preview unavailable: $error';
        loading = false;
      });
    }
    await original;
  }

  @override
  void dispose() {
    _disposed = true;
    _onlineBytes = null;
    _session++;
    _directorySession++;
    _previewCache.invalidate();
    super.dispose();
  }
}

class _CachedPreview {
  const _CachedPreview(this.bytes, this.raw, this.size, this.modified);
  final Uint8List bytes;
  final RawPreview? raw;
  final int size;
  final DateTime modified;
}
