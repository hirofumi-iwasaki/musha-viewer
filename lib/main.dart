import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization.dart';

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
      title: 'Musha Viewer',
      supportedLocales: const [Locale('en'), Locale('ja')],
      localeListResolutionCallback: (locales, _) =>
          locales != null &&
              locales.isNotEmpty &&
              locales.first.languageCode == 'ja'
          ? const Locale('ja')
          : const Locale('en'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  const ViewerScreen({
    super.key,
    required this.controller,
    this.settings,
    this.directoryPicker,
    this.filePicker,
    this.isMacOS,
  });
  final ViewerController controller;
  final SettingsStore? settings;
  final Future<String?> Function(String? initialDirectory)? directoryPicker;
  final Future<XFile?> Function()? filePicker;
  final bool? isMacOS;
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

String? dropRejection(List<DropItem> files) =>
    files.length != 1 || files.single is DropItemDirectory
    ? 'Drop one image file; folders and multiple files are not supported.'
    : null;

class _ViewerScreenState extends State<ViewerScreen> {
  final transformation = TransformationController();
  int activePickers = 0;
  bool get picking => activePickers > 0;
  bool dragging = false;
  int selection = 0;
  double swipeDistance = 0;
  double swipeVertical = 0;
  double scrollHorizontal = 0;
  double scrollVertical = 0;
  bool panZoomEligible = false;
  Timer? scrollTimer;
  final Set<int> touchPointers = {};
  bool touchGestureEligible = false;
  Size previewSize = Size.zero;
  bool get zoomed => (transformation.value.entry(0, 0).abs() - 1).abs() > .001;

  String? pendingFolderPath;
  int? pendingFolderSelection;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkFolderAccess);
  }

  Future<String?> _selectDirectory(String? initialDirectory) =>
      widget.directoryPicker?.call(initialDirectory) ??
      getDirectoryPath(initialDirectory: initialDirectory);

  void _checkFolderAccess() {
    final path = pendingFolderPath;
    final request = pendingFolderSelection;
    if (path == null ||
        request != selection ||
        widget.controller.currentPath != path ||
        !widget.controller.directoryNeedsPermission) {
      return;
    }
    pendingFolderPath = null;
    pendingFolderSelection = null;
    unawaited(_requestParentFolder(path, request!));
  }

  Future<void> _requestParentFolder(String path, int request) async {
    final parent = File(path).parent.absolute.path;
    setState(() => activePickers++);
    try {
      final selected = await _selectDirectory(parent);
      if (!mounted ||
          request != selection ||
          widget.controller.currentPath != path ||
          selected == null ||
          Directory(selected).absolute.path != parent) {
        return;
      }
      await widget.controller.authorizeDirectory(selected);
    } catch (error) {
      if (mounted &&
          request == selection &&
          widget.controller.currentPath == path) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Could not open folder: $error'))),
        );
      }
    } finally {
      if (mounted) setState(() => activePickers--);
    }
  }

  void _openSelected(String path, int request) {
    if (widget.isMacOS ?? Platform.isMacOS) {
      pendingFolderPath = path;
      pendingFolderSelection = request;
    }
    transformation.value = Matrix4.identity();
  }

  void navigate(bool forward) {
    selection++;
    pendingFolderPath = null;
    pendingFolderSelection = null;
    scrollTimer?.cancel();
    scrollHorizontal = scrollVertical = 0;
    transformation.value = Matrix4.identity();
    unawaited(
      forward ? widget.controller.next() : widget.controller.previous(),
    );
  }

  Future<void> pickFolder() async {
    final request = ++selection;
    setState(() => activePickers++);
    try {
      final currentPath = widget.controller.currentPath;
      final path = await _selectDirectory(
        currentPath == null ? null : File(currentPath).parent.absolute.path,
      );
      if (path != null && mounted && request == selection) {
        await widget.controller.authorizeDirectory(path);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'Could not open folder: $error'))),
        );
      }
    } finally {
      if (mounted) setState(() => activePickers--);
    }
  }

  Future<void> actualSize() async {
    final bytes = widget.controller.bytes;
    if (bytes == null || previewSize.isEmpty) return;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      var width = frame.image.width.toDouble();
      var height = frame.image.height.toDouble();
      if (const [5, 6, 7, 8].contains(widget.controller.previewOrientation)) {
        final originalWidth = width;
        width = height;
        height = originalWidth;
      }
      frame.image.dispose();
      if (!mounted || widget.controller.bytes != bytes) return;
      final fit = (previewSize.width / width).clamp(0.0, double.infinity);
      final scale =
          1 /
          ((fit < previewSize.height / height
                  ? fit
                  : previewSize.height / height) *
              pixelRatio);
      transformation.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setEntry(0, 3, previewSize.width * (1 - scale) / 2)
        ..setEntry(1, 3, previewSize.height * (1 - scale) / 2);
      setState(() {});
    } finally {
      codec.dispose();
    }
  }

  late final SettingsStore settings =
      widget.settings ??
      SettingsStore(File('/tmp/musha-viewer-test-settings.json'));
  Future<void> dropped(List<DropItem> files) async {
    final request = ++selection;
    final rejection = dropRejection(files);
    if (rejection != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(context, rejection))));
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
      _openSelected(item.path, request);
      await widget.controller.open(item.path);
      await widget.controller.waitForDirectoryDiscovery();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Could not open dropped file: $error')),
          ),
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
    widget.controller.removeListener(_checkFolderAccess);
    if (widget.settings == null) settings.dispose();
    scrollTimer?.cancel();
    transformation.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final request = ++selection;
    setState(() => activePickers++);
    try {
      final images = XTypeGroup(
        label: tr(context, 'Images'),
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
          'dng',
          'nef',
        ],
      );
      final file =
          await (widget.filePicker?.call() ??
              openFile(acceptedTypeGroups: [images]));
      if (file != null && mounted && request == selection) {
        _openSelected(file.path, request);
        unawaited(widget.controller.open(file.path));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Could not open file picker: $error')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => activePickers--);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus != null &&
              focus.findAncestorWidgetOfExactType<EditableText>() != null) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            navigate(false);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            navigate(true);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          appBar: AppBar(
            bottom: c.directoryStatus == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(36),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(tr(context, c.directoryStatus!)),
                    ),
                  ),
            title: Text(
              c.name == null
                  ? 'Musha Viewer'
                  : '${c.name}${c.imageCount > 0 && c.currentIndex >= 0 ? '  ${c.currentIndex + 1} / ${c.imageCount}' : ''}',
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: tr(context, 'Previous image'),
                onPressed: c.canPrevious ? () => navigate(false) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: tr(context, 'Next image'),
                onPressed: c.canNext ? () => navigate(true) : null,
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton.icon(
                onPressed: picking ? null : pickFolder,
                icon: const Icon(Icons.folder),
                label: Text(tr(context, 'Authorize folder')),
              ),
              TextButton.icon(
                onPressed: picking ? null : pick,
                icon: const Icon(Icons.folder_open),
                label: Text(tr(context, 'Open image')),
              ),
              IconButton(
                tooltip: tr(context, 'Toggle inspector'),
                onPressed: () {
                  settings.value.inspectorVisible =
                      !settings.value.inspectorVisible;
                  settings.changed();
                },
                icon: const Icon(Icons.view_sidebar),
              ),
              PopupMenuButton<ThemeMode>(
                tooltip: tr(context, 'Appearance'),
                onSelected: (theme) {
                  settings.value.theme = theme;
                  settings.changed();
                },
                itemBuilder: (_) => [
                  for (final mode in ThemeMode.values)
                    PopupMenuItem(
                      value: mode,
                      child: Text(tr(context, mode.name)),
                    ),
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
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color(0x88526984),
                        child: Center(
                          child: Text(
                            tr(context, 'Drop one image'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    previewSize = constraints.biggest;
                    return Listener(
                      onPointerDown: (event) {
                        if (event.kind != PointerDeviceKind.touch) return;
                        touchPointers.add(event.pointer);
                        if (touchPointers.length == 1) {
                          swipeDistance = 0;
                          swipeVertical = 0;
                          touchGestureEligible = !zoomed;
                        } else {
                          touchGestureEligible = false;
                        }
                      },
                      onPointerMove: (event) {
                        if (touchGestureEligible &&
                            touchPointers.contains(event.pointer)) {
                          swipeDistance += event.delta.dx;
                          swipeVertical += event.delta.dy;
                        }
                      },
                      onPointerUp: (event) {
                        if (touchGestureEligible &&
                            !zoomed &&
                            swipeDistance.abs() > 80 &&
                            swipeDistance.abs() > swipeVertical.abs()) {
                          navigate(swipeDistance < 0);
                        }
                        touchPointers.remove(event.pointer);
                        touchGestureEligible = false;
                      },
                      onPointerCancel: (event) {
                        touchPointers.remove(event.pointer);
                        touchGestureEligible = false;
                      },
                      onPointerPanZoomStart: (_) {
                        swipeDistance = swipeVertical = 0;
                        panZoomEligible = !zoomed;
                      },
                      onPointerPanZoomUpdate: (event) {
                        if (zoomed || (event.scale - 1).abs() >= .01) {
                          panZoomEligible = false;
                          swipeDistance = swipeVertical = 0;
                        } else if (panZoomEligible) {
                          swipeDistance += event.panDelta.dx;
                          swipeVertical += event.panDelta.dy;
                        }
                      },
                      onPointerPanZoomEnd: (_) {
                        if (panZoomEligible &&
                            !zoomed &&
                            swipeDistance.abs() > 60 &&
                            swipeDistance.abs() > swipeVertical.abs()) {
                          navigate(swipeDistance < 0);
                        }
                        swipeDistance = swipeVertical = 0;
                        panZoomEligible = false;
                      },
                      onPointerSignal: (event) {
                        if (event is! PointerScrollEvent || zoomed) return;
                        scrollHorizontal += event.scrollDelta.dx;
                        scrollVertical += event.scrollDelta.dy;
                        scrollTimer?.cancel();
                        scrollTimer = Timer(
                          const Duration(milliseconds: 180),
                          () {
                            final horizontal = scrollHorizontal;
                            final vertical = scrollVertical;
                            scrollHorizontal = scrollVertical = 0;
                            if (mounted &&
                                !zoomed &&
                                horizontal.abs() > 30 &&
                                horizontal.abs() > vertical.abs()) {
                              navigate(horizontal > 0);
                            }
                          },
                        );
                      },
                      child: InteractiveViewer(
                        transformationController: transformation,
                        panEnabled: zoomed,
                        minScale: 0.01,
                        maxScale: 100,
                        onInteractionEnd: (_) => setState(() {}),
                        child: SizedBox.expand(
                          child: _orientedPreview(
                            c,
                            Image.memory(
                              c.bytes!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, error, _) => Text(
                                tr(context, 'Image display failed: $error'),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr(context, c.previewError ?? 'Open an image to begin'),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      setState(() => transformation.value = Matrix4.identity()),
                  icon: const Icon(Icons.fit_screen),
                  label: Text(tr(context, 'Fit')),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: actualSize,
                  child: const Text('100%'),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _orientedPreview(ViewerController c, Widget image) {
    final orientation = c.previewOrientation ?? 1;
    final turns = switch (orientation) {
      3 || 4 => 2,
      6 || 7 => 1,
      5 || 8 => 3,
      _ => 0,
    };
    final mirrored =
        orientation == 2 ||
        orientation == 4 ||
        orientation == 5 ||
        orientation == 7;
    return RotatedBox(
      quarterTurns: turns,
      child: mirrored ? Transform.flip(flipX: true, child: image) : image,
    );
  }

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
            Text(
              tr(context, 'Inspector'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (c.c2paVisibility) ...[
              Text(
                tr(context, 'Content Credentials (C2PA)'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(tr(context, c.c2paStatus)),
              if (c.c2paResult case final result?) ...[
                Text(
                  tr(
                    context,
                    'Credentials: ${switch (result['status']) {
                      'present' => 'present',
                      'absent' => 'not detected',
                      'remote' => 'remote reference',
                      _ => 'unknown',
                    }}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Parsing: ${switch (result['status']) {
                      'present' => 'completed',
                      'absent' => 'no embedded manifest found',
                      'remote' => 'remote manifest not fetched',
                      'unsupported' => 'unsupported format',
                      'error' => 'failed',
                      _ => 'unknown',
                    }}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Asset integrity: ${result['integrity'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Claim integrity: ${result['claim_integrity'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'SDK validation: ${result['validation_state'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(context, 'Signature: ${result['signature'] ?? 'unknown'}'),
                ),
                Text(
                  tr(
                    context,
                    'Trust: ${result['trust'] ?? 'unknown'} (no general C2PA trust list configured)',
                  ),
                ),
                Text(tr(context, 'Offline verification: no online lookup')),
                if (result['error'] != null)
                  SelectableText(tr(context, 'Error: ${result['error']}')),
                if (result['error_code'] != null)
                  SelectableText(tr(context, 'Code: ${result['error_code']}')),
                Material(
                  color: Colors.transparent,
                  child: ExpansionTile(
                    title: Text(tr(context, 'Verification details')),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(result),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (c.canVerifyOnline ||
                c.onlineVerifying ||
                c.onlineStatus != null ||
                c.onlineResult != null) ...[
              const SizedBox(height: 12),
              Text(
                tr(context, 'Online verification'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: c.canVerifyOnline && !c.onlineVerifying
                      ? () => unawaited(c.verifyOnline())
                      : null,
                  child: Text(
                    tr(
                      context,
                      c.onlineVerifying ? 'Verifying online…' : 'Verify online',
                    ),
                  ),
                ),
              ),
              if (c.onlineStatus != null) Text(tr(context, c.onlineStatus!)),
              if (c.onlineResult case final online?) ...[
                if (online['online_complete'] == false)
                  Text(
                    tr(context, 'Online verification incomplete'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (online['online_request_count'] is num)
                  Text(
                    tr(
                      context,
                      'Online request attempts: ${online['online_request_count']}',
                    ),
                  ),
                if (online['online_hosts'] is List)
                  Text(
                    tr(
                      context,
                      'Requested hosts (may not have been contacted): '
                      '${(online['online_hosts'] as List).whereType<String>().where((host) => RegExp(r'^[a-zA-Z0-9.:-]+$').hasMatch(host)).join(', ')}',
                    ),
                  ),
                Text(
                  tr(
                    context,
                    'Online credentials: ${online['status'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Online asset integrity: ${online['integrity'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Online claim integrity: ${online['claim_integrity'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Embedded/local SDK validation: ${online['validation_state'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Online signature: ${online['signature'] ?? 'unknown'}',
                  ),
                ),
                Text(
                  tr(
                    context,
                    'Online trust: ${online['trust'] ?? 'unknown'} (no general C2PA trust list configured)',
                  ),
                ),
                if (online['error'] != null)
                  SelectableText(
                    tr(context, 'Online error: ${online['error']}'),
                  ),
                if (online['error_code'] != null)
                  SelectableText(
                    tr(context, 'Online code: ${online['error_code']}'),
                  ),
                Material(
                  color: Colors.transparent,
                  child: ExpansionTile(
                    title: Text(tr(context, 'Online verification details')),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent('  ').convert(online),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (settings.warning != null) Text(tr(context, settings.warning!)),
            const Divider(height: 32),
            Text(
              tr(context, 'Metadata'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (c.name == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(tr(context, 'No image selected.')),
              ),
            if (c.fileError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr(context, c.fileError!)),
              ),
            if (c.exifStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr(context, c.exifStatus!)),
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
                        '${tr(context, entry.group)} · ${entry.group == 'EXIF' ? entry.key : tr(context, entry.key)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelectableText(
                        entry.group == 'Image' ||
                                (entry.group == 'File' && entry.key == 'Size')
                            ? tr(context, entry.value)
                            : entry.value,
                      ),
                    ),
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
