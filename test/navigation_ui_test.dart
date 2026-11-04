import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class NavigationController extends ViewerController {
  NavigationController() : super(ViewerService()) {
    name = 'image2.jpg';
  }
  int index = 1;
  @override
  int get currentIndex => index;
  @override
  int get imageCount => 3;
  @override
  bool get canPrevious => index > 0;
  @override
  bool get canNext => index < 2;
  @override
  Future<void> previous() async {
    if (canPrevious) index--;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    if (canNext) index++;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'arrow keys and buttons navigate with visible position and boundaries',
    (tester) async {
      final controller = NavigationController();
      await tester.pumpWidget(
        MaterialApp(home: ViewerScreen(controller: controller)),
      );
      await tester.pump();
      expect(find.text('image2.jpg  2 / 3'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(find.text('image2.jpg  3 / 3'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Next image',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Previous image'));
      await tester.pump();
      expect(find.text('image2.jpg  2 / 3'), findsOneWidget);
    },
  );
  testWidgets('focused selectable text retains arrow keys', (tester) async {
    final controller = NavigationController()
      ..c2paResult = {'status': 'error', 'error': 'example error'};
    await tester.pumpWidget(
      MaterialApp(home: ViewerScreen(controller: controller)),
    );
    await tester.pump();
    await tester.tap(find.text('Error: example error'));
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.index, 1);
  });

  testWidgets(
    '100 percent uses physical pixels and zoom blocks swipe navigation',
    (tester) async {
      final controller = NavigationController()
        ..bytes = File('test/fixtures/exif.jpg').readAsBytesSync();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              devicePixelRatio: 2,
            ),
            child: ViewerScreen(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final size = tester.getSize(viewer);
      await tester.drag(viewer, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 2);
      await tester.runAsync(() async {
        await tester.tap(find.text('100%'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final matrix = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!
          .value;
      final fit = size.width / 3 < size.height / 2
          ? size.width / 3
          : size.height / 2;
      expect(matrix.entry(0, 0).abs(), closeTo(1 / (fit * 2), .0001));
      await tester.drag(viewer, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(controller.index, 2);
    },
  );
}
