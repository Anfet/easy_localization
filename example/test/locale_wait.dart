import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForLocale(WidgetTester tester, EasyLocalizationInstance localization, Locale target) async {
  final result = await tester.runAsync(() async {
    final finished = Completer<Object?>();
    void observe() {
      final state = localization.state.value;
      if (state.error != null && !finished.isCompleted) {
        finished.complete(StateError('Localization failed: ${state.error} (${state.errorStage})'));
      } else if (state.locale == target && !finished.isCompleted) {
        finished.complete(null);
      }
    }

    localization.state.addListener(observe);
    try {
      observe();
      return await finished.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          final state = localization.state.value;
          return TimeoutException('Waiting for $target: locale=${state.locale}, loading=${state.isLoading}, error=${state.error}');
        },
      );
    } finally {
      localization.state.removeListener(observe);
    }
  });
  if (result != null) throw result;
  await tester.pumpAndSettle();
}
