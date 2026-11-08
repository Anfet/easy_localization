import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';

class LanguageView extends StatefulWidget {
  @override
  State<LanguageView> createState() => _LanguageViewState();
}

class _LanguageViewState extends State<LanguageView> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final localization = EasyLocalization.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose language')),
      body: ValueListenableBuilder<LocalizationState>(
        valueListenable: localization.state,
        builder: (context, state, _) => ListView(
          children: [
            for (final locale in localization.supportedLocales)
              ListTile(
                title: Text(_names[locale.languageCode] ?? locale.toString()),
                selected: locale == localization.presentationLocale,
                enabled: !state.isLoading && !_busy,
                trailing: _busy && locale == localization.presentationLocale ? const CircularProgressIndicator() : null,
                onTap: () async {
                  setState(() => _busy = true);
                  try {
                    await localization.setLocale(locale);
                    final outcome = await localization.waitForPresentation();
                    if (!context.mounted) return;
                    if (outcome == LocalizationApplyOutcome.applied) {
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Language change was not applied: $outcome')));
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Language change failed: ${localization.state.value.error ?? error}')));
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  static const _names = {'ar': 'عربي', 'en': 'English', 'de': 'German', 'ru': 'Русский'};
}
