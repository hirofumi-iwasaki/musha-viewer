import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ViewerSettings {
  ViewerSettings({
    this.width = 1280,
    this.height = 820,
    this.x,
    this.y,
    this.maximized = false,
    this.inspectorWidth = 340,
    this.inspectorVisible = true,
    this.theme = ThemeMode.system,
  });
  double width, height, inspectorWidth;
  double? x, y;
  bool maximized, inspectorVisible;
  ThemeMode theme;
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'window': {
      'width': width,
      'height': height,
      'x': x,
      'y': y,
      'maximized': maximized,
    },
    'inspector': {'width': inspectorWidth, 'visible': inspectorVisible},
    'theme': theme.name,
  };
  factory ViewerSettings.fromJson(Map<String, dynamic> json) {
    final w = json['window'] as Map<String, dynamic>? ?? {};
    final i = json['inspector'] as Map<String, dynamic>? ?? {};
    double number(dynamic value, double fallback, double min, double max) =>
        value is num && value.isFinite
        ? value.toDouble().clamp(min, max)
        : fallback;
    double? coordinate(dynamic value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    return ViewerSettings(
      width: number(w['width'], 1280, 320, 10000),
      height: number(w['height'], 820, 240, 10000),
      x: coordinate(w['x']),
      y: coordinate(w['y']),
      maximized: w['maximized'] == true,
      inspectorWidth: number(i['width'], 340, 240, 1000),
      inspectorVisible: i['visible'] is bool ? i['visible'] : true,
      theme:
          ThemeMode.values.where((e) => e.name == json['theme']).firstOrNull ??
          ThemeMode.system,
    );
  }
}

class SettingsStore extends ChangeNotifier {
  SettingsStore(this.file);
  final File file;
  ViewerSettings value = ViewerSettings();
  bool writable = true;
  String? warning;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['schemaVersion'] != 1) {
        writable = false;
        warning = 'Settings version is unsupported; the original file will be preserved.';
        return;
      }
      value = ViewerSettings.fromJson(data);
    } catch (_) {
      writable = false;
      warning =
          'Settings could not be read; the original file will be preserved.';
    }
  }

  void reportWarning(String message) {
    warning = message;
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    if (!writable) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () {
      unawaited(flush());
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    if (!writable) return;
    final data = const JsonEncoder.withIndent('  ').convert(value.toJson());
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(data, flush: true);
        await temp.rename(file.path);
      } catch (error) {
        warning = 'Could not save settings: $error';
        notifyListeners();
      }
    });
    await _writes;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

Future<File> settingsFile() async {
  if (Platform.isLinux) {
    final config = Platform.environment['XDG_CONFIG_HOME'];
    final home = Platform.environment['HOME'];
    if (config != null && config.startsWith('/')) {
      return File('$config/musha-viewer/settings.json');
    }
    if (home != null && home.isNotEmpty) {
      return File('$home/.config/musha-viewer/settings.json');
    }
  }
  if (Platform.isWindows) {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) {
      return File('$local\\musha-viewer\\settings.json');
    }
  }
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}settings.json');
}
