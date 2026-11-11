import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForLocale(WidgetTester tester, EasyLocalizationInstance localization, Locale target) async {
  const timeout = Duration(seconds: 5);
  var elapsed = Duration.zero;
  while (elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 10));
    elapsed += const Duration(milliseconds: 10);
    final state = localization.state.value;
    if (state.error != null) {
      throw StateError('Localization failed: ${state.error} (${state.errorStage})');
    }
    if (state.locale == target) break;
  }
  final state = localization.state.value;
  if (state.locale != target) {
    throw TimeoutException('Waiting for $target: locale=${state.locale}, loading=${state.isLoading}, error=${state.error}');
  }
  await tester.pumpAndSettle();
}
