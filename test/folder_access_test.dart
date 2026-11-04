import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class FolderController extends ViewerController {
  FolderController() : super(ViewerService());
  String? path;
  bool denied = false;
  final authorized = <String>[];

  @override
  String? get currentPath => path;
  @override
  bool get directoryNeedsPermission => denied;
  @override
  Future<void> open(String value) async {
    path = value;
    denied = false;
    notifyListeners();
  }

  void accessible() => notifyListeners();

  void deny() {
    denied = true;
    notifyListeners();
  }

  @override
  Future<void> authorizeDirectory(String value) async {
    authorized.add(value);
  }
}

void main() {
  testWidgets(
    'requests the parent on denial and cancellation does not authorize',
    (tester) async {
      final controller = FolderController();
      final prompts = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerScreen(
            controller: controller,
            isMacOS: true,
            filePicker: () async => XFile('/photos/one.jpg'),
            directoryPicker: (initial) async {
              prompts.add(initial);
              return null;
            },
          ),
        ),
      );
      await tester.tap(find.text('Open image'));
      await tester.pump();
      expect(prompts, isEmpty);
      controller.deny();
      await tester.pump();
      expect(prompts, ['/photos']);
      expect(controller.authorized, isEmpty);
    },
  );

  testWidgets('manual folder picker starts at the current image parent', (
    tester,
  ) async {
    final controller = FolderController()..path = '/photos/one.jpg';
    String? initialDirectory;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          controller: controller,
          directoryPicker: (initial) async {
            initialDirectory = initial;
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('Authorize folder'));
    await tester.pump();
    expect(initialDirectory, '/photos');
  });

  testWidgets('authorizes the selected parent after access is denied', (
    tester,
  ) async {
    final controller = FolderController();
    final prompts = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          controller: controller,
          isMacOS: true,
          filePicker: () async => XFile('/photos/one.jpg'),
          directoryPicker: (initial) async {
            prompts.add(initial);
            return '/photos';
          },
        ),
      ),
    );
    await tester.tap(find.text('Open image'));
    await tester.pump();
    controller.deny();
    await tester.pump();
    expect(prompts, ['/photos']);
    expect(controller.authorized, ['/photos']);
  });

  testWidgets('does not prompt when directory access succeeds or is reused', (
    tester,
  ) async {
    final controller = FolderController();
    final prompts = <String?>[];
    var files = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          controller: controller,
          isMacOS: true,
          filePicker: () async =>
              XFile(files++ == 0 ? '/photos/one.jpg' : '/photos/two.jpg'),
          directoryPicker: (initial) async {
            prompts.add(initial);
            return initial;
          },
        ),
      ),
    );
    await tester.tap(find.text('Open image'));
    await tester.pump();
    controller.accessible();
    await tester.pump();
    await tester.tap(find.text('Open image'));
    await tester.pump();
    controller.accessible();
    await tester.pump();
    expect(prompts, isEmpty);
    expect(controller.authorized, isEmpty);
  });

  testWidgets('ignores an old folder picker after another image is opened', (
    tester,
  ) async {
    final controller = FolderController();
    final picker = Completer<String?>();
    var files = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          controller: controller,
          isMacOS: true,
          filePicker: () async =>
              XFile(files++ == 0 ? '/photos/one.jpg' : '/other/two.jpg'),
          directoryPicker: (_) => picker.future,
        ),
      ),
    );
    await tester.tap(find.text('Open image'));
    await tester.pump();
    controller.deny();
    await tester.pump();
    final openButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Open image'),
    );
    expect(openButton.onPressed, isNull);
    await controller.open('/other/two.jpg');
    await tester.pump();
    picker.complete('/photos');
    await tester.pump();
    expect(controller.currentPath, '/other/two.jpg');
    expect(controller.authorized, isEmpty);
  });
}
