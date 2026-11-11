import 'package:flutter/foundation.dart';

/// Receives a diagnostic message and its optional original stack trace.
typedef LocalizationLogCallback = void Function(String message, {StackTrace? stackTrace});

void reportLocalizationDiagnostic(LocalizationLogCallback? callback, String message, {StackTrace? stackTrace}) {
  if (callback == null) return;
  try {
    callback(message, stackTrace: stackTrace);
  } catch (error, callbackStackTrace) {
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: callbackStackTrace, library: 'easy_localization'));
  }
}
