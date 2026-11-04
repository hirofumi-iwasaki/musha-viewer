import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/c2pa.dart';

void main() {
  final release = File(
    Platform.isMacOS
        ? 'native/c2pa/target/macos/libmusha_c2pa.dylib'
        : 'native/c2pa/target/release/libmusha_c2pa.so',
  ).absolute;
  final library = release.existsSync()
      ? release
      : File('native/c2pa/target/debug/libmusha_c2pa.so').absolute;
  test(
    'DNG names use the native DNG handler',
    () async {
      final result = await verifyC2pa(
        Uint8List.fromList([73, 73, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        'original.DNG',
        libraryPath: library.path,
      );
      expect(result['status'], 'absent');
    },
    skip: !(Platform.isLinux || Platform.isMacOS) || !library.existsSync()
        ? 'Native library not built; build it first to run the integration test.'
        : false,
  );
  test(
    'NEF names use the native TIFF handler',
    () async {
      final result = await verifyC2pa(
        Uint8List.fromList([73, 73, 42, 0, 8, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        'original.NEF',
        libraryPath: library.path,
      );
      expect(result['status'], 'absent');
      final malformed = await verifyC2pa(
        Uint8List.fromList([0, 1, 2]),
        'original.nef',
        libraryPath: library.path,
      );
      expect(malformed['status'], 'error');
    },
    skip: !(Platform.isLinux || Platform.isMacOS) || !library.existsSync()
        ? 'Native library not built; build it first to run the integration test.'
        : false,
  );
  test(
    'native verification distinguishes signed and tampered snapshots',
    () async {
      final bytes = await File('native/c2pa/tests/fixtures/signed.jpg')
          .readAsBytes();
      final valid = await verifyC2pa(
        bytes,
        'signed.jpg',
        libraryPath: library.path,
      );
      expect(valid['status'], 'present');
      expect(valid['signature'], 'valid');
      expect(valid['integrity'], 'valid');
      expect(valid['trust'], 'unknown');
      expect(valid['validation_state'], 'Valid');
      final tampered = await File('native/c2pa/tests/fixtures/tampered.jpg')
          .readAsBytes();
      final changed = await verifyC2pa(
        tampered,
        'signed.jpg',
        libraryPath: library.path,
      );
      expect(changed['status'], 'present');
      expect(changed['integrity'], 'invalid');
      expect(
        changed['validation_results'].toString(),
        contains('assertion.dataHash.mismatch'),
      );
    },
    skip: !(Platform.isLinux || Platform.isMacOS) || !library.existsSync()
        ? 'Native library not built; build it first to run the integration test.'
        : false,
  );
}
