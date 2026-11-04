import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/directory_navigation.dart';

void main() {
  test('supports picker extensions case insensitively', () {
    final nav = DirectoryNavigation(['/a/1.HEIC', '/a/2.tif', '/a/3.TIFF']);
    expect(nav.paths, ['/a/1.HEIC', '/a/2.tif', '/a/3.TIFF']);
  });

  test('natural ordering, supported extensions and navigation boundaries', () {
    final nav = DirectoryNavigation([
      '/a/image10.NEF',
      '/a/image2.jpg',
      '/a/image1.dng',
      '/a/notes.txt',
      '/a/image99999999999999999999999999999.png',
    ], current: '/a/image2.jpg');
    expect(nav.paths.map((p) => p.split('/').last), [
      'image1.dng',
      'image2.jpg',
      'image10.NEF',
      'image99999999999999999999999999999.png',
    ]);
    expect(nav.index, 1);
    expect(nav.movePrevious(), '/a/image1.dng');
    expect(nav.movePrevious(), isNull);
    expect(nav.current, '/a/image1.dng');
    expect(nav.select('/missing'), isFalse);
    expect(nav.select('/a/image99999999999999999999999999999.png'), isTrue);
    expect(nav.moveNext(), isNull);
    expect(nav.index, 3);
    final missing = DirectoryNavigation(['/a/x.jpg'], current: '/missing');
    expect(missing.moveNext(), isNull);
  });

  test('directory listing does not recurse or include directories', () async {
    final dir = await Directory.systemTemp.createTemp('navigation_test');
    try {
      await File('${dir.path}/2.jpg').writeAsBytes([]);
      await File('${dir.path}/10.DNG').writeAsBytes([]);
      final nested = await Directory('${dir.path}/1.jpg').create();
      await File('${nested.path}/nested.jpg').writeAsBytes([]);
      final nav = await DirectoryNavigation.fromDirectory(
        dir.path,
        current: '${dir.path}/2.jpg',
      );
      expect(nav.paths, ['${dir.path}/2.jpg', '${dir.path}/10.DNG']);
      expect(nav.next, '${dir.path}/10.DNG');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test(
    'cache respects count and byte bounds, skips oversized previews',
    () async {
      final cache = AdjacentPreviewCache<Uint8List>(
        sizeOf: (v) => v.length,
        maxEntries: 2,
        maxBytes: 5,
      );
      await cache.prefetch([
        'a',
        'b',
        'c',
      ], (path) async => Uint8List(path == 'a' ? 3 : 4));
      expect(cache.length, 1);
      expect(cache.bytes, 4);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), isNotNull);
      expect(cache.get('c'), isNull);
      await cache.prefetch(['large'], (_) async => Uint8List(6));
      expect(cache.length, 0);
      expect(cache.bytes, 0);
    },
  );

  test('late loads cannot populate a newer navigation session', () async {
    final cache = AdjacentPreviewCache<Uint8List>(sizeOf: (v) => v.length);
    final old = Completer<Uint8List>();
    final pending = cache.prefetch(['old'], (_) => old.future);
    final next = cache.prefetch(['new'], (_) async => Uint8List(1));
    old.complete(Uint8List(2));
    await pending;
    await next;
    expect(cache.get('old'), isNull);
    expect(cache.get('new'), isNotNull);
    final later = Completer<Uint8List>();
    final pending2 = cache.prefetch(['later'], (_) => later.future);
    cache.invalidate();
    later.complete(Uint8List(1));
    await pending2;
    expect(cache.length, 0);
    expect(cache.bytes, 0);
  });

  test(
    'overlapping prefetches serialize and skip superseded targets',
    () async {
      final cache = AdjacentPreviewCache<Uint8List>(sizeOf: (v) => v.length);
      final first = Completer<Uint8List>();
      final loaded = <String>[];
      var active = 0;
      var maxActive = 0;
      Future<Uint8List> load(String path) async {
        loaded.add(path);
        active++;
        if (active > maxActive) maxActive = active;
        try {
          return path == 'first' ? await first.future : Uint8List(1);
        } finally {
          active--;
        }
      }

      final a = cache.prefetch(['first'], load);
      final b = cache.prefetch(['superseded'], load);
      final c = cache.prefetch(['latest'], load);
      expect(loaded, ['first']);
      first.complete(Uint8List(1));
      await Future.wait([a, b, c]);
      expect(maxActive, 1);
      expect(loaded, ['first', 'latest']);
      expect(cache.get('first'), isNull);
      expect(cache.get('latest'), isNotNull);
    },
  );
}
