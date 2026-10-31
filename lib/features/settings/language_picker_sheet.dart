import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/iso_languages.dart';
import '../../data/models/library.dart';
import '../../data/models/tag_category.dart';
import '../../data/operations/settings_operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/search_field.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';

/// Settings › Languages you read: add a language, from "+ Add language"
/// on Settings › Books.
Future<void> showLanguagePicker(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const LanguagePickerSheet());

/// A language the sheet lists, with why it is suggested ("Phone", "In your
/// library") when it is.
typedef LanguageChoice = ({IsoLanguage language, String? why});

/// The Suggested group (DESIGN.md section 4): the phone's system languages
/// in the phone's order, then the languages the library's Languages tags
/// name ([TagCategory.languages]: a tag is the language's English name in
/// lowercase), each once.
List<LanguageChoice> suggestedLanguages(
  List<String> systemLanguages,
  Library? library,
) {
  final seen = <String>{};
  final out = <LanguageChoice>[];
  for (final code in systemLanguages) {
    final language = isoLanguage(code);
    if (language != null && seen.add(language.code)) {
      out.add((language: language, why: 'Phone'));
    }
  }
  final tags = library?.tags[TagCategory.languages] ?? const <String>[];
  for (final tag in tags) {
    for (final language in isoLanguages) {
      if (language.name.toLowerCase() == tag && seen.add(language.code)) {
        out.add((language: language, why: 'In your library'));
      }
    }
  }
  return out;
}

/// "Languages you read" with Done at the right, a search box, then
/// Suggested and All languages A to Z, every row a check row with the
/// English name over the language's own name; a search shows one Matches
/// group, or "No language called that." A tap toggles the language at
/// once (`SetReadingLanguages`); the last chosen one cannot be unticked.
class LanguagePickerSheet extends ConsumerStatefulWidget {
  const LanguagePickerSheet({super.key});

  static const noMatch = 'No language called that.';

  @override
  ConsumerState<LanguagePickerSheet> createState() =>
      _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends ConsumerState<LanguagePickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(IsoLanguage language, Set<String> chosen) {
    final next = {...chosen};
    if (!next.add(language.code)) {
      next.remove(language.code);
      if (next.isEmpty) return;
    }
    unawaited(
      ref
          .read(libraryRepositoryProvider)
          .applySettings(SetReadingLanguages(next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final chosen = ref.watch(readingLanguagesProvider);
    final query = _query.text.trim();

    Widget row(LanguageChoice choice) => LanguageRow(
      key: ValueKey(
        '${choice.why == null ? 'language' : 'suggested'}-'
        '${choice.language.code}',
      ),
      language: choice.language,
      why: choice.why,
      checked: chosen.contains(choice.language.code),
      onTap: () => _toggle(choice.language, chosen),
    );

    final List<Widget> body;
    if (query.isNotEmpty) {
      final hits = [
        for (final l in isoLanguages)
          if (l.matches(query)) (language: l, why: null),
      ];
      body = hits.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  LanguagePickerSheet.noMatch,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.muted,
                  ),
                ),
              ),
            ]
          : [_heading('Matches'), for (final c in hits) row(c)];
    } else {
      final suggested = suggestedLanguages(
        ref.watch(systemLanguagesProvider),
        ref.watch(libraryProvider).value,
      );
      body = [
        if (suggested.isNotEmpty) ...[
          _heading('Suggested'),
          for (final c in suggested) row(c),
        ],
        _heading('All languages'),
        for (final l in isoLanguages) row((language: l, why: null)),
      ];
    }

    return SheetFrame(
      scrollable: true,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Languages you read',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              AppButton(
                label: 'Done',
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(
            controller: _query,
            hintText: 'Search, e.g. Turkish or Türkçe',
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      ),
    );
  }

  Widget _heading(String label) =>
      SectionHeading(label, padding: const EdgeInsets.fromLTRB(0, 14, 0, 4));
}

/// One language: the English name over its own name ("Türkçe"; a name
/// that is the same in both shows once), with "Phone" or "In your library"
/// after it in the Suggested group, and a check at the right while chosen
/// (as the platform picker's rows).
class LanguageRow extends StatelessWidget {
  const LanguageRow({
    super.key,
    required this.language,
    required this.checked,
    required this.onTap,
    this.why,
  });

  final IsoLanguage language;
  final bool checked;
  final VoidCallback onTap;
  final String? why;

  /// The second line: the own name, the reason, or both ("Türkçe · Phone").
  String? get secondLine {
    final own = language.ownName == language.name ? null : language.ownName;
    return [?own, ?why].isEmpty ? null : [?own, ?why].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final second = secondLine;
    return Semantics(
      button: true,
      checked: checked,
      label: language.name,
      value: second,
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(language.name, style: theme.textTheme.titleMedium),
                    if (second != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        second,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontSize: 13,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (checked) ...[
                const SizedBox(width: 12),
                StrokeIcon(
                  AppIcons.check,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
