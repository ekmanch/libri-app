import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icons.dart';

/// The small label above a form field: "Title", "Director". Not uppercase,
/// unlike section headings.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!
            .copyWith(letterSpacing: 0),
      ),
    );
  }
}

/// A 52 px text field on the surface color with the 14 px corner of the forms
/// (Add / edit entry; Add / edit entry › New entry: pick a match). Grows for
/// [maxLines] > 1.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.errorText,
    this.maxLines = 1,
    this.autofocus = false,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
    this.onChanged,
    this.onSubmitted,
    this.maxLength,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? errorText;
  final int maxLines;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Stops typing past this many characters; no counter is shown.
  final int? maxLength;

  /// Hides the text, for the access token (First run › Connect GitHub).
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: maxLines,
      maxLength: maxLength,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: theme.textTheme.bodyLarge!.copyWith(
        fontWeight: maxLines == 1 ? FontWeight.w500 : FontWeight.w400,
        fontSize: maxLines == 1 ? 16 : 15.5,
        height: maxLines == 1 ? null : 1.4,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        errorText: errorText,
        counterText: '',
        fillColor: theme.colorScheme.surface,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: maxLines == 1 ? 15 : 12,
        ),
      ),
    );
  }
}

/// A field-shaped button that opens a picker: the rating and tags fields
/// of the entry form. [placeholder] draws the child in the hint color.
class FieldButton extends StatelessWidget {
  const FieldButton({
    super.key,
    required this.child,
    required this.onTap,
    this.placeholder = false,
    this.semanticsLabel,
    this.padding = const EdgeInsets.fromLTRB(14, 8, 12, 8),
  });

  final Widget child;
  final VoidCallback onTap;
  final bool placeholder;
  final String? semanticsLabel;

  /// 14 px in front of text; chips sit 8 px in (Add / edit entry; Plans › Edit
  /// plan).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: theme.colorScheme.outline),
    );
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: theme.colorScheme.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: padding,
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w500,
                      color: placeholder
                          ? colors.placeholder
                          : theme.colorScheme.onSurface,
                    ),
                    child: child,
                  ),
                ),
                const SizedBox(width: 8),
                StrokeIcon(AppIcons.chevronDown, size: 18, color: colors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
