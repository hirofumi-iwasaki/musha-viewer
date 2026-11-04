import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musha_viewer/main.dart';

class OnlineController extends ViewerController {
  OnlineController() : super(ViewerService()) {
    name = 'image.jpg';
    c2paStatus = 'Offline verification';
    c2paResult = {'status': 'remote'};
  }

  bool eligible = true;
  bool checking = false;
  String? status;
  Map<String, dynamic>? result;
  int requests = 0;
  final pending = Completer<void>();

  @override
  bool get canVerifyOnline => eligible;
  @override
  bool get onlineVerifying => checking;
  @override
  String? get onlineStatus => status;
  @override
  Map<String, dynamic>? get onlineResult => result;
  @override
  Future<void> verifyOnline() async {
    requests++;
    checking = true;
    notifyListeners();
    await pending.future;
    checking = false;
    status = 'Online checks did not complete';
    result = {
      'status': 'present',
      'integrity': 'valid',
      'online_complete': false,
      'validation_state': 'Valid',
      'online_request_count': 2,
      'online_hosts': [
        'example.org',
        'https://example.org/private?token=secret',
      ],
    };
    notifyListeners();
  }
}

void main() {
  testWidgets('online verification requires a click and shows its result', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OnlineController();
    await tester.pumpWidget(
      MaterialApp(home: ViewerScreen(controller: controller)),
    );
    expect(controller.requests, 0);
    expect(find.text('Offline verification'), findsOneWidget);
    expect(
      find.textContaining('GET requests to remote resources'),
      findsOneWidget,
    );
    expect(find.textContaining('source image is not uploaded'), findsOneWidget);
    expect(find.textContaining('ocsp.leica.systems'), findsOneWidget);
    expect(find.textContaining('certificate identifiers'), findsOneWidget);
    expect(find.textContaining('network intermediaries'), findsOneWidget);
    await tester.ensureVisible(find.text('Verify online'));
    await tester.tap(find.text('Verify online'));
    await tester.pump();
    expect(controller.requests, 1);
    expect(find.text('Verifying online…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Verifying online…'),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    controller.pending.complete();
    await tester.pump();
    expect(find.text('Online checks did not complete'), findsOneWidget);
    expect(find.text('Online verification incomplete'), findsOneWidget);
    expect(find.text('Embedded/local SDK validation: Valid'), findsOneWidget);
    expect(find.text('Online SDK validation: Valid'), findsNothing);
    expect(find.text('Online request attempts: 2'), findsOneWidget);
    expect(
      find.text('Requested hosts (may not have been contacted): example.org'),
      findsOneWidget,
    );
    expect(find.textContaining('token=secret'), findsNothing);
    expect(find.text('Online asset integrity: valid'), findsOneWidget);
    expect(find.text('Offline verification'), findsOneWidget);
  });
}
