import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForLocale(WidgetTester tester, EasyLocalizationInstance localization, Locale target) async {
  const timeout = Duration(seconds: 5);
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final result = await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return true;
    });
    if (result == null) throw StateError('Could not advance asynchronous work while waiting for $target');
    await tester.pump();

    final state = localization.state.value;
    if (state.error != null) {
      throw StateError('Localization failed: ${state.error} (${state.errorStage})');
    }
    if (state.locale == target) break;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Waiting for $target: locale=${state.locale}, loading=${state.isLoading}, error=${state.error}');
    }
  }
  await tester.pumpAndSettle();
}
