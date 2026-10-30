import 'entry_operations.dart';
import 'library_operation.dart';
import 'plan_operations.dart';
import 'season_operations.dart';
import 'settings_operations.dart';
import 'tag_operations.dart';

/// Operations as JSON, for the offline queue (`pending.json`). The `op`
/// key names the operation; the rest is the operation's own fields. A
/// [SettingsOperation] (a change to `settings.json`) is queued the same
/// way, under a `settings.` name.
Map<String, Object?> encodeOperation(Object operation) {
  final (name, json) = switch (operation) {
    SetStatus() => ('setStatus', operation.toJson()),
    SetRating() => ('setRating', operation.toJson()),
    SetReleased() => ('setReleased', operation.toJson()),
    SetKind() => ('setKind', operation.toJson()),
    SetSeriesCover() => ('setSeriesCover', operation.toJson()),
    AddEntry() => ('addEntry', operation.toJson()),
    UpdateEntry() => ('updateEntry', operation.toJson()),
    DeleteEntry() => ('deleteEntry', operation.toJson()),
    RateTrack() => ('rateTrack', operation.toJson()),
    ClearTrackRating() => ('clearTrackRating', operation.toJson()),
    AddPlan() => ('addPlan', operation.toJson()),
    UpdatePlan() => ('updatePlan', operation.toJson()),
    DeletePlan() => ('deletePlan', operation.toJson()),
    SetPlanItem() => ('setPlanItem', operation.toJson()),
    RemovePlanItem() => ('removePlanItem', operation.toJson()),
    SetPlanStarted() => ('setPlanStarted', operation.toJson()),
    AddTag() => ('addTag', operation.toJson()),
    SetTagCategories() => ('setTagCategories', operation.toJson()),
    SetSeasonStatus() => ('setSeasonStatus', operation.toJson()),
    MarkSeasonsDone() => ('markSeasonsDone', operation.toJson()),
    AddSeasons() => ('addSeasons', operation.toJson()),
    SetSeasons() => ('setSeasons', operation.toJson()),
    RemoveSeason() => ('removeSeason', operation.toJson()),
    KeepSeason() => ('keepSeason', operation.toJson()),
    RefreshShowStatus() => ('refreshShowStatus', operation.toJson()),
    MoveShowsToSeasons() => ('moveShowsToSeasons', operation.toJson()),
    SetSeasonDates() => ('setSeasonDates', operation.toJson()),
    SetTimelineDefault() => ('settings.setTimelineDefault', operation.toJson()),
    SetSeasonalThemeDefault() => (
      'settings.setSeasonalThemeDefault',
      operation.toJson(),
    ),
    SetDefaultPlatform() => ('settings.setDefaultPlatform', operation.toJson()),
    SetUpcomingEnabled() => ('settings.setUpcomingEnabled', operation.toJson()),
    SetFollow() => ('settings.setFollow', operation.toJson()),
    SetFollows() => ('settings.setFollows', operation.toJson()),
    SetNotInterested() => ('settings.setNotInterested', operation.toJson()),
    ForgetNotInterested() => (
      'settings.forgetNotInterested',
      operation.toJson(),
    ),
    _ => throw ArgumentError.value(
      operation,
      'operation',
      'has no JSON form: ${operation.runtimeType}',
    ),
  };
  return {'op': name, ...json};
}

/// The inverse of [encodeOperation]: a [LibraryOperation] or a
/// [SettingsOperation]. Throws [FormatException] for an unknown `op`.
Object decodeOperation(Map<String, Object?> json) {
  return switch (json['op']) {
    'setStatus' => SetStatus.fromJson(json),
    'setRating' => SetRating.fromJson(json),
    'setReleased' => SetReleased.fromJson(json),
    'setKind' => SetKind.fromJson(json),
    'setSeriesCover' => SetSeriesCover.fromJson(json),
    'addEntry' => AddEntry.fromJson(json),
    'updateEntry' => UpdateEntry.fromJson(json),
    'deleteEntry' => DeleteEntry.fromJson(json),
    'rateTrack' => RateTrack.fromJson(json),
    'clearTrackRating' => ClearTrackRating.fromJson(json),
    'addPlan' => AddPlan.fromJson(json),
    'updatePlan' => UpdatePlan.fromJson(json),
    'deletePlan' => DeletePlan.fromJson(json),
    'setPlanItem' => SetPlanItem.fromJson(json),
    'removePlanItem' => RemovePlanItem.fromJson(json),
    'setPlanStarted' => SetPlanStarted.fromJson(json),
    'addTag' => AddTag.fromJson(json),
    'setTagCategories' => SetTagCategories.fromJson(json),
    'setSeasonStatus' => SetSeasonStatus.fromJson(json),
    'markSeasonsDone' => MarkSeasonsDone.fromJson(json),
    'addSeasons' => AddSeasons.fromJson(json),
    'setSeasons' => SetSeasons.fromJson(json),
    'removeSeason' => RemoveSeason.fromJson(json),
    'keepSeason' => KeepSeason.fromJson(json),
    'refreshShowStatus' => RefreshShowStatus.fromJson(json),
    'moveShowsToSeasons' => MoveShowsToSeasons.fromJson(json),
    'setSeasonDates' => SetSeasonDates.fromJson(json),
    'settings.setTimelineDefault' => SetTimelineDefault.fromJson(json),
    'settings.setSeasonalThemeDefault' => SetSeasonalThemeDefault.fromJson(
      json,
    ),
    'settings.setDefaultPlatform' => SetDefaultPlatform.fromJson(json),
    'settings.setUpcomingEnabled' => SetUpcomingEnabled.fromJson(json),
    'settings.setFollow' => SetFollow.fromJson(json),
    'settings.setFollows' => SetFollows.fromJson(json),
    'settings.setNotInterested' => SetNotInterested.fromJson(json),
    'settings.forgetNotInterested' => ForgetNotInterested.fromJson(json),
    final other => throw FormatException('Unknown operation: $other'),
  };
}
