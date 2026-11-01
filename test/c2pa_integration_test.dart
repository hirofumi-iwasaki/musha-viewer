import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/c2pa.dart';

void main() {
  final release = File('native/c2pa/target/release/libmusha_c2pa.so').absolute;
  final library = release.existsSync()
      ? release
      : File('native/c2pa/target/debug/libmusha_c2pa.so').absolute;
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
    skip: !Platform.isLinux || !library.existsSync()
        ? 'Native Linux library not built; build it first to run the integration test.'
        : false,
  );
}
