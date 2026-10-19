import 'dart:ui' show Color;

import '../../data/models/plan.dart';
import '../../theme/app_theme.dart';
import 'seasonal_art.dart';
import 'seasonal_art_data.dart';

/// The two seasons with artwork (Plans › Halloween touches; Christmas touches).
/// A plan has one when it is linked to the season's tag and its seasonal theme
/// is on.
enum PlanSeason {
  halloween,
  christmas;

  Color get accent => switch (this) {
    PlanSeason.halloween => SeasonalAccents.halloween,
    PlanSeason.christmas => SeasonalAccents.christmas,
  };

  SeasonalArt get strip => switch (this) {
    PlanSeason.halloween => halloweenStrip,
    PlanSeason.christmas => christmasStrip,
  };

  SeasonalArt get icon => switch (this) {
    PlanSeason.halloween => halloweenIcon,
    PlanSeason.christmas => christmasIcon,
  };

  SeasonalArt get marker => switch (this) {
    PlanSeason.halloween => halloweenMarker,
    PlanSeason.christmas => christmasMarker,
  };

  /// The help line under the Seasonal theme switch (Plans › Edit plan; New
  /// plan).
  String get help => switch (this) {
    PlanSeason.halloween =>
      'Halloween artwork and an orange accent inside this plan.',
    PlanSeason.christmas =>
      'Christmas artwork and a green accent inside this plan.',
  };
}

/// The season a set of linked tags implies, if any.
PlanSeason? seasonForTags(Iterable<String> tags) {
  for (final tag in tags) {
    switch (tag.toLowerCase()) {
      case 'halloween':
        return PlanSeason.halloween;
      case 'christmas':
      case 'xmas':
        return PlanSeason.christmas;
    }
  }
  return null;
}

/// The season shown for [plan]: only with the theme switched on.
PlanSeason? seasonOf(Plan plan) =>
    plan.seasonalTheme ? seasonForTags(plan.tags) : null;
