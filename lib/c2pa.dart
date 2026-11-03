import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _VerifyNative = Pointer<Utf8> Function(
  Pointer<Uint8>,
  IntPtr,
  Pointer<Utf8>,
);
typedef _VerifyDart = Pointer<Utf8> Function(
  Pointer<Uint8>,
  int,
  Pointer<Utf8>,
);
typedef _FreeNative = Void Function(Pointer<Utf8>);

Future<Map<String, dynamic>> verifyC2pa(
  Uint8List bytes,
  String name, {
  String? libraryPath,
}) => compute(_verify, (bytes, name, libraryPath));
Map<String, dynamic> _verify((Uint8List, String, String?) input) {
  final library = input.$3 != null
      ? DynamicLibrary.open(input.$3!)
      : Platform.isMacOS
      ? DynamicLibrary.open(
          '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libmusha_c2pa.dylib',
        )
      : DynamicLibrary.open(
          '${File(Platform.resolvedExecutable).parent.path}/lib/libmusha_c2pa.so',
        );
  final verify = library.lookupFunction<_VerifyNative, _VerifyDart>(
    'musha_c2pa_verify',
  );
  final free = library
      .lookupFunction<_FreeNative, void Function(Pointer<Utf8>)>(
        'musha_c2pa_free',
      );
  final data = calloc<Uint8>(input.$1.length);
  data.asTypedList(input.$1.length).setAll(0, input.$1);
  final extension = input.$2.toLowerCase().split('.').last;
  final mime =
      ({
                'jpg': 'image/jpeg',
                'jpeg': 'image/jpeg',
                'png': 'image/png',
                'webp': 'image/webp',
                'heic': 'image/heic',
                'tif': 'image/tiff',
                'tiff': 'image/tiff',
                'dng': 'image/x-adobe-dng',
              }[extension] ??
              'application/octet-stream')
          .toNativeUtf8();
  try {
    final result = verify(data, input.$1.length, mime);
    if (result == nullptr) throw StateError('C2PA engine returned no result');
    try {
      return (jsonDecode(result.toDartString()) as Map).cast<String, dynamic>();
    } finally {
      free(result);
    }
  } finally {
    calloc.free(data);
    calloc.free(mime);
  }
}
