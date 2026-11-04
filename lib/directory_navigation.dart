import 'dart:async';
import 'dart:io';

const supportedImageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
  'tif',
  'tiff',
  'psd',
  'eps',
  'dng',
  'nef',
};

String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

bool isSupportedImagePath(String path) {
  final name = _basename(path);
  final dot = name.lastIndexOf('.');
  return dot >= 0 &&
      supportedImageExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Compares digit runs by numeric value without parsing potentially huge numbers.
int naturalFilenameCompare(String a, String b) {
  final aa = _basename(a).toLowerCase();
  final bb = _basename(b).toLowerCase();
  var i = 0, j = 0;
  bool digit(int c) => c >= 48 && c <= 57;
  while (i < aa.length && j < bb.length) {
    if (digit(aa.codeUnitAt(i)) && digit(bb.codeUnitAt(j))) {
      var ai = i, bj = j;
      while (ai < aa.length && digit(aa.codeUnitAt(ai))) {
        ai++;
      }
      while (bj < bb.length && digit(bb.codeUnitAt(bj))) {
        bj++;
      }
      var az = i, bz = j;
      while (az < ai && aa.codeUnitAt(az) == 48) {
        az++;
      }
      while (bz < bj && bb.codeUnitAt(bz) == 48) {
        bz++;
      }
      final lengthOrder = (ai - az).compareTo(bj - bz);
      if (lengthOrder != 0) return lengthOrder;
      final valueOrder = aa.substring(az, ai).compareTo(bb.substring(bz, bj));
      if (valueOrder != 0) return valueOrder;
      i = ai;
      j = bj;
    } else {
      final order = aa.codeUnitAt(i).compareTo(bb.codeUnitAt(j));
      if (order != 0) return order;
      i++;
      j++;
    }
  }
  final order = (aa.length - i).compareTo(bb.length - j);
  return order != 0 ? order : a.compareTo(b);
}

/// A snapshot of supported files in one directory. Navigation never wraps.
class DirectoryNavigation {
  DirectoryNavigation(Iterable<String> paths, {String? current})
    : paths = List.unmodifiable(
        paths.where(isSupportedImagePath).toList()
          ..sort(naturalFilenameCompare),
      ) {
    _index = current == null ? -1 : this.paths.indexOf(current);
  }

  static Future<DirectoryNavigation> fromDirectory(
    String directory, {
    String? current,
  }) async {
    final paths = <String>[];
    await for (final entity in Directory(directory).list(followLinks: false)) {
      if (entity is File && isSupportedImagePath(entity.path)) {
        paths.add(entity.path);
      }
    }
    return DirectoryNavigation(paths, current: current);
  }

  final List<String> paths;
  late int _index;
  int get index => _index;
  String? get current => _index < 0 ? null : paths[_index];
  String? get previous => _index > 0 ? paths[_index - 1] : null;
  String? get next =>
      _index >= 0 && _index + 1 < paths.length ? paths[_index + 1] : null;
  bool select(String path) {
    final index = paths.indexOf(path);
    if (index < 0) return false;
    _index = index;
    return true;
  }

  String? movePrevious() {
    final path = previous;
    if (path != null) _index--;
    return path;
  }

  String? moveNext() {
    final path = next;
    if (path != null) _index++;
    return path;
  }
}

/// LRU cache for prefetched previews, bounded by entry count and total size.
/// A new prefetch or invalidation makes outstanding loads ineligible to cache.
class AdjacentPreviewCache<T> {
  AdjacentPreviewCache({
    required this.sizeOf,
    this.maxEntries = 2,
    this.maxBytes = 32 * 1024 * 1024,
  }) : assert(maxEntries >= 0),
       assert(maxBytes >= 0);
  final int Function(T) sizeOf;
  final int maxEntries;
  final int maxBytes;
  final _entries = <String, T>{};
  int _bytes = 0;
  int _generation = 0;
  Future<void>? _busy;
  int get length => _entries.length;
  int get bytes => _bytes;
  T? get(String path) {
    final value = _entries.remove(path);
    if (value != null) _entries[path] = value;
    return value;
  }

  void invalidate() {
    _generation++;
    _entries.clear();
    _bytes = 0;
  }

  /// Only the first [maxEntries] distinct paths are considered. Loading is
  /// serialized across calls; individual failures are ignored. Superseded
  /// requests waiting for an active loader are skipped.
  Future<void> prefetch(
    Iterable<String> paths,
    Future<T> Function(String) loader,
  ) async {
    final generation = ++_generation;
    final targets = paths.toSet().take(maxEntries).toSet();
    for (final key in _entries.keys.toList()) {
      if (!targets.contains(key)) _bytes -= sizeOf(_entries.remove(key) as T);
    }
    while (_busy != null) {
      await _busy;
      if (generation != _generation) return;
    }
    if (generation != _generation) return;
    final done = Completer<void>();
    _busy = done.future;
    try {
      for (final path in targets) {
        if (generation != _generation) return;
        if (get(path) != null) continue;
        try {
          final value = await loader(path);
          if (generation != _generation) return;
          final size = sizeOf(value);
          if (size < 0 || size > maxBytes) continue;
          while (_entries.isNotEmpty &&
              (_entries.length >= maxEntries || _bytes + size > maxBytes)) {
            final oldest = _entries.keys.first;
            _bytes -= sizeOf(_entries.remove(oldest) as T);
          }
          if (maxEntries > 0) {
            _entries[path] = value;
            _bytes += size;
          }
        } catch (_) {
          // A failed adjacent preview must not interrupt navigation.
        }
      }
    } finally {
      _busy = null;
      done.complete();
    }
  }
}
