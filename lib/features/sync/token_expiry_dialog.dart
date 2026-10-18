import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icons.dart';
import 'token_expiry.dart';

/// What was picked in D20. Null when the dialog was dismissed otherwise.
enum TokenExpiryChoice {
  /// Open the token step with the repo kept (F3 as "Replace token").
  replace,

  /// Dismiss until the next day.
  later,
}

/// The token expiry warning (D20): the token for [repository] stops
/// working on [expires]. "Open GitHub" opens the tokens page in the
/// browser and leaves the dialog up, so the new token can be pasted on
/// return; the other two buttons close it with their choice.
Future<TokenExpiryChoice?> showTokenExpiryDialog(
  BuildContext context, {
  required String repository,
  required DateTime expires,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return showAppDialog<TokenExpiryChoice>(
    context,
    builder: (context) {
      final colors = LibraryColors.of(context);
      return AppDialog(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.caution.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: StrokeIcon(AppIcons.key, size: 22, color: colors.caution),
        ),
        title: tokenExpiryTitle(expires, at),
        body:
            'The access token for $repository stops working on '
            '${tokenExpiryDate(expires, at)}. After that, Libri can\'t sync '
            'until you add a new one.',
        note:
            'On GitHub, regenerate the token with a new expiry date, then '
            'paste it here. Your library stays as it is.',
        actionsLayout: DialogActionsLayout.column,
        actions: [
          AppButton(
            label: 'Replace token',
            kind: AppButtonKind.neutral,
            onPressed: () => Navigator.pop(context, TokenExpiryChoice.replace),
          ),
          Semantics(
            button: true,
            label: 'Open token settings on GitHub, opens website',
            excludeSemantics: true,
            child: AppButton(
              label: 'Open GitHub',
              kind: AppButtonKind.outline,
              icon: const StrokeIcon(AppIcons.externalLink, size: 16),
              onPressed: _openGitHub,
            ),
          ),
          AppButton(
            label: 'Later',
            kind: AppButtonKind.text,
            onPressed: () => Navigator.pop(context, TokenExpiryChoice.later),
          ),
        ],
      );
    },
  );
}

Future<void> _openGitHub() async {
  try {
    await launchUrl(gitHubTokensUrl, mode: LaunchMode.externalApplication);
  } on Object {
    // No browser to open it: nothing to do.
  }
}
