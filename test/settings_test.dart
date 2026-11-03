import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/settings.dart';
import 'package:musha_viewer/main.dart' show flushWindowSettings;

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('musha-settings-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  test('shutdown flushes even when window capture fails', () async {
    var flushed = false;
    await flushWindowSettings(
      Future.value(),
      () async => throw StateError('window unavailable'),
      () async {
        flushed = true;
      },
    );
    expect(flushed, isTrue);
  });
  test('round trips settings with serialized writes', () async {
    final file = File('${temp.path}/settings.json');
    final store = SettingsStore(file);
    store.value.theme = ThemeMode.dark;
    store.value.inspectorWidth = 420;
    store.value.x = -100;
    store.changed();
    await store.flush();
    final loaded = SettingsStore(file);
    await loaded.load();
    expect(loaded.value.theme, ThemeMode.dark);
    expect(loaded.value.inspectorWidth, 420);
    expect(loaded.value.x, -100);
    store.dispose();
    loaded.dispose();
  });
  test('corrupt and future versions are preserved', () async {
    final file = File('${temp.path}/settings.json');
    for (final content in ['{bad', '{"schemaVersion":99,"extra":true}']) {
      await file.writeAsString(content);
      final store = SettingsStore(file);
      await store.load();
      expect(store.writable, false);
      expect(store.warning, isNotNull);
      store.changed();
      await store.flush();
      expect(await file.readAsString(), content);
      store.dispose();
    }
  });
}
