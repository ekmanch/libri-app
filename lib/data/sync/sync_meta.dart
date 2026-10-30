import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/json_file.dart';

/// The base of one more file synced beside the library: `settings.json`
/// (DESIGN.md section 8), compared the same three-way way.
@immutable
class FileBase {
  const FileBase({
    this.etag,
    required this.remoteSha,
    required this.canonicalSha,
  });

  /// The ETag of the last download, for the next conditional request.
  final String? etag;

  /// The blob sha of the file on GitHub as last seen or written, or null
  /// when the file is not on GitHub (yet): a missing `settings.json` is no
  /// error, it is created on the first save of a setting.
  final String? remoteSha;

  /// The blob sha of the remote file re-encoded in the canonical form; for
  /// a file not on GitHub, that of the defaults.
  final String canonicalSha;

  FileBase copyWith({
    Object? etag = _unset,
    Object? remoteSha = _unset,
    String? canonicalSha,
  }) => FileBase(
    etag: etag == _unset ? this.etag : etag as String?,
    remoteSha: remoteSha == _unset ? this.remoteSha : remoteSha as String?,
    canonicalSha: canonicalSha ?? this.canonicalSha,
  );

  static const _unset = Object();

  Map<String, Object?> toJson() => {
    'etag': etag,
    'remoteSha': remoteSha,
    'canonicalSha': canonicalSha,
  };

  static FileBase? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final canonicalSha = json['canonicalSha'];
    if (canonicalSha is! String) return null;
    return FileBase(
      etag: json['etag'] as String?,
      remoteSha: json['remoteSha'] as String?,
      canonicalSha: canonicalSha,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FileBase &&
      other.etag == etag &&
      other.remoteSha == remoteSha &&
      other.canonicalSha == canonicalSha;

  @override
  int get hashCode => Object.hash(etag, remoteSha, canonicalSha);
}

/// What the app remembers about the copy of the library file on GitHub,
/// kept in `sync.json` next to the cache, and the base of `settings.json`
/// beside it.
@immutable
class SyncMeta {
  const SyncMeta({
    this.target,
    this.etag,
    required this.remoteSha,
    required this.canonicalSha,
    this.commitSha,
    this.lastSynced,
    this.lastChecked,
    this.settings,
  });

  /// Which file this is the base of: "owner/repo:path@branch". A base
  /// only applies to the same file; one written for another file (a
  /// library kept on the phone, then connected elsewhere) is ignored.
  /// Null in a sync.json from before this field.
  final String? target;

  /// The ETag of the last download, for the next conditional request.
  /// For the raw format it is the quoted blob sha, so a save sets it too.
  final String? etag;

  /// The blob sha of the file on GitHub, as last seen or written. The
  /// Contents API wants it as the `sha` of the file being replaced.
  final String remoteSha;

  /// The blob sha of the remote file re-encoded in the app's canonical
  /// form. Equal to [remoteSha] once the app has saved; different for a
  /// file formatted by hand. The cache with no pending operations encodes
  /// to this sha.
  final String canonicalSha;

  /// The commit of the last save, when known.
  final String? commitSha;

  /// When the cache last matched GitHub (a download or a successful save).
  final DateTime? lastSynced;

  /// When GitHub was last asked whether the file changed.
  final DateTime? lastChecked;

  /// The base of `settings.json`, or null until it was first fetched (a
  /// `sync.json` from before the file).
  final FileBase? settings;

  SyncMeta copyWith({
    String? target,
    Object? etag = _unset,
    String? remoteSha,
    String? canonicalSha,
    Object? commitSha = _unset,
    DateTime? lastSynced,
    DateTime? lastChecked,
    FileBase? settings,
  }) => SyncMeta(
    target: target ?? this.target,
    etag: etag == _unset ? this.etag : etag as String?,
    remoteSha: remoteSha ?? this.remoteSha,
    canonicalSha: canonicalSha ?? this.canonicalSha,
    commitSha: commitSha == _unset ? this.commitSha : commitSha as String?,
    lastSynced: lastSynced ?? this.lastSynced,
    lastChecked: lastChecked ?? this.lastChecked,
    settings: settings ?? this.settings,
  );

  static const _unset = Object();

  Map<String, Object?> toJson() => {
    'target': target,
    'etag': etag,
    'remoteSha': remoteSha,
    'canonicalSha': canonicalSha,
    'commitSha': commitSha,
    'lastSynced': lastSynced?.toUtc().toIso8601String(),
    'lastChecked': lastChecked?.toUtc().toIso8601String(),
    'settings': settings?.toJson(),
  };

  /// Null when the map is not a sync meta (e.g. from an older app).
  static SyncMeta? fromJson(Map<String, Object?> json) {
    final remoteSha = json['remoteSha'];
    final canonicalSha = json['canonicalSha'];
    if (remoteSha is! String || canonicalSha is! String) return null;
    return SyncMeta(
      target: json['target'] as String?,
      etag: json['etag'] as String?,
      remoteSha: remoteSha,
      canonicalSha: canonicalSha,
      commitSha: json['commitSha'] as String?,
      lastSynced: _date(json['lastSynced']),
      lastChecked: _date(json['lastChecked']),
      settings: FileBase.fromJson(json['settings']),
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  @override
  bool operator ==(Object other) =>
      other is SyncMeta &&
      other.target == target &&
      other.etag == etag &&
      other.remoteSha == remoteSha &&
      other.canonicalSha == canonicalSha &&
      other.commitSha == commitSha &&
      other.lastSynced == lastSynced &&
      other.lastChecked == lastChecked &&
      other.settings == settings;

  @override
  int get hashCode => Object.hash(
    target,
    etag,
    remoteSha,
    canonicalSha,
    commitSha,
    lastSynced,
    lastChecked,
    settings,
  );
}

/// `sync.json` on the device.
class SyncMetaStore {
  SyncMetaStore(File file) : _file = JsonFile(file);

  final JsonFile _file;

  /// The stored meta, or null when there is none (or it is unreadable,
  /// which just costs one full download).
  Future<SyncMeta?> load() async {
    final json = await _file.read();
    return json == null ? null : SyncMeta.fromJson(json);
  }

  Future<void> save(SyncMeta meta) => _file.write(meta.toJson());

  Future<void> delete() => _file.delete();
}
