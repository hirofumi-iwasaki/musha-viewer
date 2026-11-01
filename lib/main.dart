import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:exif/exif.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ViewerApp());

class MetadataEntry {
  const MetadataEntry(this.group, this.key, this.value);
  final String group;
  final String key;
  final String value;
}

/// Reads a bounded snapshot. The source file is never opened for writing.
class ViewerService {
  static const maxBytes = 64 * 1024 * 1024;
  static const maxPixels = 40 * 1000 * 1000;

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

  Future<Uint8List> read(String path) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in File(path).openRead()) {
      total += chunk.length;
      if (total > maxBytes) {
        throw const FormatException('File exceeds the 64 MiB reading limit');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<List<MetadataEntry>> exif(Uint8List bytes) =>
      compute(_extractExif, bytes);
}

Future<List<MetadataEntry>> _extractExif(Uint8List bytes) async {
  final tags = await readExifFromBytes(bytes);
  return [
    for (final tag in tags.entries)
      MetadataEntry('EXIF', tag.key, tag.value.printable),
  ];
}

class ViewerController extends ChangeNotifier {
  ViewerController(this.service);
  final ViewerService service;
  int _session = 0;
  bool _disposed = false;
  String? name;
  Uint8List? bytes;
  List<MetadataEntry> fileEntries = [], exifEntries = [], imageEntries = [];
  String? fileError, previewError, exifStatus;
  bool loading = false;

  bool _current(int id) => !_disposed && id == _session;
  void _update(int id, void Function() change) {
    if (_current(id)) {
      change();
      notifyListeners();
    }
  }

  Future<void> open(String path) async {
    final id = ++_session;
    name = path.split(Platform.pathSeparator).last;
    bytes = null;
    fileEntries = [];
    exifEntries = [];
    imageEntries = [];
    fileError = null;
    previewError = null;
    exifStatus = 'Reading EXIF…';
    loading = true;
    notifyListeners();
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
    try {
      final data = await service.read(path);
      if (!_current(id)) return;
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
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        try {
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            if (descriptor.width * descriptor.height >
                ViewerService.maxPixels) {
              throw const FormatException(
                'Image exceeds the 40 megapixel preview limit',
              );
            }
          } finally {
            descriptor.dispose();
          }
        } finally {
          buffer.dispose();
        }
        if (!_current(id)) return;
        final codec = await ui.instantiateImageCodec(data);
        try {
          final frame = await codec.getNextFrame();
          final width = frame.image.width, height = frame.image.height;
          frame.image.dispose();
          _update(id, () {
            bytes = data;
            imageEntries = [
              MetadataEntry(
                'Image',
                'Decoded dimensions',
                '$width × $height pixels',
              ),
            ];
            loading = false;
          });
        } finally {
          codec.dispose();
        }
      } catch (error) {
        _update(id, () {
          previewError = 'Image preview unavailable: $error';
          loading = false;
        });
      }
      await metadata;
    } catch (error) {
      _update(id, () {
        previewError = 'Could not read image: $error';
        exifStatus = 'EXIF unavailable because the file could not be read.';
        loading = false;
      });
    }
    await info;
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    super.dispose();
  }
}

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'musha-viewer',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff526984)),
      useMaterial3: true,
    ),
    home: ViewerScreen(controller: ViewerController(ViewerService())),
  );
}

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.controller});
  final ViewerController controller;
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final transformation = TransformationController();
  bool picking = false;
  @override
  void dispose() {
    transformation.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  Future<void> pick() async {
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
      if (file != null && mounted) {
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
            const SizedBox(width: 12),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final preview = _preview(c);
            final inspector = _inspector(c);
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
                      SizedBox(width: 340, child: inspector),
                    ],
                  );
          },
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
            const Text('Verification unavailable in this version.'),
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
