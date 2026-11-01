import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';
import 'viewer_controller.dart';
export 'viewer_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SettingsStore settings;
  try {
    settings = SettingsStore(await settingsFile());
    await settings.load();
  } catch (error) {
    settings = SettingsStore(
      File(
        '${Directory.systemTemp.path}/musha-viewer-unavailable-settings.json',
      ),
    );
    settings.writable = false;
    settings.warning = 'Settings are unavailable: $error';
  }
  var windowReady = false;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowReady = true;
    await restoreWindow(settings.value);
  } catch (error) {
    settings.warning = 'Window restoration unavailable: $error';
    if (windowReady) {
      try {
        await windowManager.show();
      } catch (_) {}
    }
  }
  runApp(ViewerApp(settings: settings, windowReady: windowReady));
}

Future<void> restoreWindow(ViewerSettings settings) async {
  final displays = await screenRetriever.getAllDisplays();
  if (displays.isNotEmpty) {
    final requested = Rect.fromLTWH(
      settings.x ?? 0,
      settings.y ?? 0,
      settings.width,
      settings.height,
    );
    final display =
        displays
            .where(
              (d) =>
                  (Offset(
                            d.visiblePosition?.dx ?? 0,
                            d.visiblePosition?.dy ?? 0,
                          ) &
                          (d.visibleSize ?? d.size))
                      .overlaps(requested),
            )
            .firstOrNull ??
        displays.first;
    final area =
        (display.visiblePosition ?? Offset.zero) &
        (display.visibleSize ?? display.size);
    final w = settings.width.clamp(
          area.width < 320 ? area.width : 320.0,
          area.width,
        ),
        h = settings.height.clamp(
          area.height < 240 ? area.height : 240.0,
          area.height,
        );
    final x = (settings.x ?? area.left).clamp(area.left, area.right - w),
        y = (settings.y ?? area.top).clamp(area.top, area.bottom - h);
    await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
  }
  if (settings.maximized) await windowManager.maximize();
  await windowManager.show();
}

Future<void> flushWindowSettings(
  Future<void> pending,
  Future<void> Function() saveWindow,
  Future<void> Function() flush,
) async {
  try {
    await pending;
    await saveWindow();
  } catch (error) {
    debugPrint('Could not capture window settings: $error');
  }
  try {
    await flush();
  } catch (error) {
    debugPrint('Could not save settings: $error');
  }
}

AppLifecycleListener registerExitHandler(Future<void> Function() prepare) =>
    AppLifecycleListener(
      onExitRequested: () async {
        await prepare();
        return AppExitResponse.exit;
      },
    );

class ViewerApp extends StatefulWidget {
  const ViewerApp({super.key, this.settings, this.windowReady = false});
  final SettingsStore? settings;
  final bool windowReady;
  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> with WindowListener {
  late final SettingsStore settings =
      widget.settings ??
      SettingsStore(File('/tmp/musha-viewer-test-settings.json'));
  late final ViewerController controller = ViewerController(ViewerService());
  AppLifecycleListener? lifecycle;
  bool closing = false;
  Future<void> windowUpdates = Future.value();
  @override
  void initState() {
    super.initState();
    if (widget.windowReady) {
      windowManager.addListener(this);
      lifecycle = registerExitHandler(prepareForQuit);
    }
  }

  Future<void> saveWindow() async {
    final maximized = await windowManager.isMaximized();
    settings.value.maximized = maximized;
    if (!maximized && !await windowManager.isFullScreen()) {
      final bounds = await windowManager.getBounds();
      settings.value.width = bounds.width;
      settings.value.height = bounds.height;
      settings.value.x = bounds.left;
      settings.value.y = bounds.top;
    }
    settings.changed();
  }

  void scheduleWindowSave() {
    if (closing) return;
    windowUpdates = windowUpdates.then((_) async {
      try {
        await saveWindow();
      } catch (error) {
        settings.reportWarning('Window settings unavailable: $error');
      }
    });
  }

  @override
  void onWindowMoved() => scheduleWindowSave();
  @override
  void onWindowResized() => scheduleWindowSave();
  @override
  void onWindowMaximize() => scheduleWindowSave();
  @override
  void onWindowUnmaximize() => scheduleWindowSave();
  @override
  void onWindowClose() {
    if (!closing) {
      closing = true;
      unawaited(_close());
    }
  }

  Future<void> prepareForQuit() async {
    closing = true;
    await flushWindowSettings(windowUpdates, saveWindow, settings.flush);
  }

  Future<void> _close() async {
    try {
      await prepareForQuit();
    } finally {
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    if (widget.windowReady) {
      windowManager.removeListener(this);
      lifecycle?.dispose();
    }
    settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => MaterialApp(
      title: 'musha-viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526984)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff526984),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: settings.value.theme,
      home: ViewerScreen(controller: controller, settings: settings),
    ),
  );
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.controller, this.settings});
  final ViewerController controller;
  final SettingsStore? settings;
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

String? dropRejection(List<DropItem> files) =>
    files.length != 1 || files.single is DropItemDirectory
    ? 'Drop one image file; folders and multiple files are not supported.'
    : null;

class _ViewerScreenState extends State<ViewerScreen> {
  final transformation = TransformationController();
  bool picking = false;
  bool dragging = false;
  int selection = 0;
  late final SettingsStore settings =
      widget.settings ??
      SettingsStore(File('/tmp/musha-viewer-test-settings.json'));
  Future<void> dropped(List<DropItem> files) async {
    final request = ++selection;
    final rejection = dropRejection(files);
    if (rejection != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(rejection)));
      }
      return;
    }
    final item = files.single;
    final bookmark = item.extraAppleBookmark;
    var scoped = false;
    try {
      if (Platform.isMacOS && bookmark != null && bookmark.isNotEmpty) {
        scoped = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
        if (!scoped) {
          throw StateError(
            'Permission to read the dropped file was not granted',
          );
        }
      }
      if (!mounted || request != selection) return;
      transformation.value = Matrix4.identity();
      await widget.controller.open(item.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open dropped file: $error')),
        );
      }
    } finally {
      if (scoped) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark!,
        );
      }
    }
  }

  @override
  void dispose() {
    if (widget.settings == null) settings.dispose();
    transformation.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final request = ++selection;
    setState(() => picking = true);
    try {
      const images = XTypeGroup(
        label: 'Images',
        extensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'heic',
          'tif',
          'tiff',
        ],
      );
      final file = await openFile(acceptedTypeGroups: [images]);
      if (file != null && mounted && request == selection) {
        transformation.value = Matrix4.identity();
        unawaited(widget.controller.open(file.path));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            c.name ?? 'musha-viewer',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton.icon(
              onPressed: picking ? null : pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open image'),
            ),
            IconButton(
              tooltip: 'Toggle inspector',
              onPressed: () {
                settings.value.inspectorVisible =
                    !settings.value.inspectorVisible;
                settings.changed();
              },
              icon: const Icon(Icons.view_sidebar),
            ),
            PopupMenuButton<ThemeMode>(
              tooltip: 'Appearance',
              onSelected: (theme) {
                settings.value.theme = theme;
                settings.changed();
              },
              itemBuilder: (_) => [
                for (final mode in ThemeMode.values)
                  PopupMenuItem(value: mode, child: Text(mode.name)),
              ],
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: DropTarget(
          onDragEntered: (_) => setState(() => dragging = true),
          onDragExited: (_) => setState(() => dragging = false),
          onDragDone: (details) {
            setState(() => dragging = false);
            unawaited(dropped(details.files));
          },
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final preview = _preview(c);
                  final inspector = _inspector(c);
                  if (!settings.value.inspectorVisible) return preview;
                  return constraints.maxWidth < 650
                      ? Column(
                          children: [
                            Expanded(child: preview),
                            SizedBox(
                              height: constraints.maxHeight * .42,
                              child: inspector,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: preview),
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeColumn,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) {
                                  setState(() {
                                    settings.value.inspectorWidth =
                                        (settings.value.inspectorWidth -
                                                details.delta.dx)
                                            .clamp(
                                              240,
                                              (constraints.maxWidth - 200)
                                                  .clamp(240, 1000),
                                            );
                                    settings.changed();
                                  });
                                },
                                child: const SizedBox(width: 8),
                              ),
                            ),
                            SizedBox(
                              width: settings.value.inspectorWidth.clamp(
                                240,
                                constraints.maxWidth - 200,
                              ),
                              child: inspector,
                            ),
                          ],
                        );
                },
              ),
              if (dragging)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Color(0x88526984),
                      child: Center(
                        child: Text(
                          'Drop one image',
                          style: TextStyle(color: Colors.white, fontSize: 28),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _preview(ViewerController c) => ColoredBox(
    color: const Color(0xff20252b),
    child: Stack(
      children: [
        Positioned.fill(
          child: c.loading
              ? const Center(child: CircularProgressIndicator())
              : c.bytes != null
              ? InteractiveViewer(
                  transformationController: transformation,
                  minScale: 0.2,
                  maxScale: 8,
                  child: SizedBox.expand(
                    child: Image.memory(
                      c.bytes!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, error, _) => Text(
                        'Image display failed: $error',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      c.previewError ?? 'Open an image to begin',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
        ),
        if (c.bytes != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.tonalIcon(
              onPressed: () => transformation.value = Matrix4.identity(),
              icon: const Icon(Icons.fit_screen),
              label: const Text('Fit'),
            ),
          ),
      ],
    ),
  );

  Widget _inspector(ViewerController c) {
    final entries = [...c.fileEntries, ...c.imageEntries, ...c.exifEntries];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Builder(
        builder: (context) {
          final header = <Widget>[
            Text('Inspector', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
              'Content Credentials (C2PA)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(c.c2paStatus),
            if (c.c2paResult case final result?) ...[
              Text(
                'Credentials: ${switch (result['status']) {
                  'present' => 'present',
                  'absent' => 'not detected',
                  'remote' => 'remote reference',
                  _ => 'unknown',
                }}',
              ),
              Text(
                'Parsing: ${switch (result['status']) {
                  'present' => 'completed',
                  'absent' => 'no embedded manifest found',
                  'remote' => 'remote manifest not fetched',
                  'unsupported' => 'unsupported format',
                  'error' => 'failed',
                  _ => 'unknown',
                }}',
              ),
              Text('Asset integrity: ${result['integrity'] ?? 'unknown'}'),
              Text(
                'Claim integrity: ${result['claim_integrity'] ?? 'unknown'}',
              ),
              Text(
                'SDK validation: ${result['validation_state'] ?? 'unknown'}',
              ),
              Text('Signature: ${result['signature'] ?? 'unknown'}'),
              Text(
                'Trust: ${result['trust'] ?? 'unknown'} (no trust list configured)',
              ),
              const Text('Online lookup: disabled'),
              if (result['error'] != null)
                SelectableText('Error: ${result['error']}'),
              if (result['error_code'] != null)
                SelectableText('Code: ${result['error_code']}'),
              Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  title: const Text('Verification details'),
                  children: [
                    SelectableText(
                      const JsonEncoder.withIndent('  ').convert(result),
                    ),
                  ],
                ),
              ),
            ],
            if (settings.warning != null) Text(settings.warning!),
            const Divider(height: 32),
            Text('Metadata', style: Theme.of(context).textTheme.titleMedium),
            if (c.name == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No image selected.'),
              ),
            if (c.fileError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.fileError!),
              ),
            if (c.exifStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(c.exifStatus!),
              ),
          ];
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: header.length + entries.length,
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              final entry = entries[index - header.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        '${entry.group} · ${entry.key}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: SelectableText(entry.value)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
