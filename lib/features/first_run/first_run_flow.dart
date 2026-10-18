import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/github/github_api.dart';
import '../../data/library_codec.dart';
import '../../data/library_providers.dart';
import '../../data/models/library.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/libri_logo.dart';
import '../../widgets/radio_mark.dart';
import '../sync/relative_time.dart';
import '../sync/sync_state.dart';
import 'which_library_dialog.dart';

/// Opens the Connect GitHub step on its own, from "Replace token" in D6.
/// Pops when the token is saved.
Future<void> openReplaceTokenScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(builder: (_) => const FirstRunFlow.replaceToken()),
  );
}

enum FirstRunStep {
  splash,
  welcome,
  connect,
  branch,
  file,
  create,
  existing,
  done,
}

enum _FileChoice { newFile, existing }

/// A branch in the repo, as F4 lists them.
class RepoBranch {
  const RepoBranch(this.name, {required this.isDefault, this.updated});

  final String name;

  /// The repo's default branch: listed first, with a badge, preselected.
  final bool isDefault;

  /// When its head was committed ("2 days ago"), when known.
  final String? updated;

  String? get info => updated == null ? null : 'Updated $updated';
}

/// A JSON file in the repo, as F7 lists them.
class RepoFile {
  const RepoFile(this.path, {this.entries, this.updated, this.sha});

  final String path;

  /// The blob sha, for replacing the file with this phone's library (D18).
  final String? sha;

  /// How many entries the library holds; null for a JSON file that is not
  /// a Libri library, which cannot be picked.
  final int? entries;

  /// When it was last committed ("2 days ago"), when known.
  final String? updated;

  bool get usable => entries != null;

  String get info => usable
      ? 'Libri library · $entries ${entries == 1 ? 'entry' : 'entries'}'
            '${updated == null ? '' : ' · updated $updated'}'
      : 'Not a Libri library file';
}

/// What went wrong with a GitHub call, in the flow's words.
String describeGitHubFailure(GitHubException e) => switch (e.failure) {
  GitHubFailure.unauthorized =>
    'GitHub refused the token. Check it and try again.',
  GitHubFailure.notFound => 'Repository not found, or the token cannot see it.',
  GitHubFailure.forbidden => 'The token is not allowed to use this repo.',
  GitHubFailure.rateLimited =>
    'GitHub is rate limiting the token. Try again in a few minutes.',
  GitHubFailure.offline => 'No connection. Check your network and try again.',
  GitHubFailure.conflict || GitHubFailure.other =>
    'GitHub answered with an error'
        '${e.status == null ? '' : ' (${e.status})'}. Try again.',
};

/// The first run (F1 to F8): splash, welcome, connect GitHub, pick a
/// branch, new or existing library file, create or pick it, all set. One
/// screen whose content changes with the step, like the canvas template.
/// Talks to GitHub through [GitHubApi]; the token and the connection are
/// stored at the end (F8).
class FirstRunFlow extends ConsumerStatefulWidget {
  const FirstRunFlow({super.key, this.initialStep = FirstRunStep.splash})
    : replaceToken = false,
      reconnect = false;

  /// Only the connect step, with a Save token button that pops.
  const FirstRunFlow.replaceToken({super.key})
    : initialStep = FirstRunStep.connect,
      replaceToken = true,
      reconnect = false;

  /// Connecting a repo again while the library is kept on the phone (D6
  /// after D16): F3 to F8 pushed above the app, popped when done or on
  /// back from F3.
  const FirstRunFlow.reconnect({super.key})
    : initialStep = FirstRunStep.connect,
      replaceToken = false,
      reconnect = true;

  final FirstRunStep initialStep;
  final bool replaceToken;
  final bool reconnect;

  /// How long the splash stays before the welcome screen.
  static const splashDuration = Duration(milliseconds: 900);

  /// How many JSON files F7 looks into, and how large one may be.
  static const maxFiles = 20;
  static const maxFileBytes = 20 * 1024 * 1024;

  /// Where "How do I create a token?" goes.
  static final tokenHelpUrl = Uri.parse(
    'https://github.com/settings/personal-access-tokens/new',
  );

  /// The commit that creates the file (F6), empty or from this phone.
  static const createMessage = 'Create Libri library';

  /// The commit that puts this phone's library over a chosen file (D18).
  static const replaceMessage = 'Replace with the library from this phone';

  @override
  ConsumerState<FirstRunFlow> createState() => _FirstRunFlowState();
}

class _FirstRunFlowState extends ConsumerState<FirstRunFlow> {
  late FirstRunStep _step = widget.initialStep;
  _FileChoice _choice = _FileChoice.newFile;
  Timer? _timer;
  late final TextEditingController _repo;
  late final TextEditingController _token;
  late final TextEditingController _fileName;

  /// The client for the repo and token of F3, once they are accepted.
  GitHubApi? _api;

  /// The repo's default branch, from F3.
  String _defaultBranch = 'main';

  /// The branch picked in F4 (the default until another is tapped), used
  /// for everything after it.
  String _branch = 'main';

  /// F4: null while the branches are being read.
  List<RepoBranch>? _branches;

  /// Connect or Create in progress; a second press is ignored.
  bool _busy = false;

  /// Shown under the step's field after a failed call.
  String? _error;

  /// F7: null while the repo is being read.
  List<RepoFile>? _files;
  int _file = 0;

  /// F8: how many entries the chosen file holds.
  int _loadedEntries = 0;

  /// The library kept on this phone after a disconnect (D16), once read;
  /// F6 creates the new file from it and F7 asks which to keep (D18).
  Library? _kept;

  /// The connection the kept library belongs to, to tell the same file
  /// from another one.
  LibraryConnection? _keptConnection;

  /// F8 after "This phone's" in D18: the chosen file now holds it.
  bool _replacedFile = false;

  @override
  void initState() {
    super.initState();
    final connection = ref.read(libraryConnectionProvider);
    if (connection.keptLocally) {
      _keptConnection = connection;
      unawaited(
        ref.read(libraryRepositoryProvider).load().then((library) {
          if (mounted) setState(() => _kept = library);
        }, onError: (Object _) {}),
      );
    }
    _repo = TextEditingController(text: connection.repository);
    _token = TextEditingController();
    _fileName = TextEditingController(text: connection.file);
    _repo.addListener(_refresh);
    _token.addListener(_refresh);
    _fileName.addListener(_refresh);
    if (_step == FirstRunStep.splash) {
      _timer = Timer(FirstRunFlow.splashDuration, () {
        if (mounted) setState(() => _step = FirstRunStep.welcome);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _repo.dispose();
    _token.dispose();
    _fileName.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _go(FirstRunStep step) {
    setState(() {
      _step = step;
      _busy = false;
      _error = null;
    });
    if (step == FirstRunStep.branch) unawaited(_loadBranches());
    if (step == FirstRunStep.existing) unawaited(_loadFiles());
  }

  /// The step a back goes to; null where there is no back.
  FirstRunStep? get _previous => switch (_step) {
    FirstRunStep.connect => FirstRunStep.welcome,
    FirstRunStep.branch => FirstRunStep.connect,
    FirstRunStep.file => FirstRunStep.branch,
    FirstRunStep.create || FirstRunStep.existing => FirstRunStep.file,
    _ => null,
  };

  void _back() {
    if (widget.replaceToken ||
        (widget.reconnect && _step == FirstRunStep.connect)) {
      Navigator.pop(context);
    } else if (_previous case final step?) {
      _go(step);
    }
  }

  bool get _canConnect =>
      _repo.text.trim().contains('/') && _token.text.trim().isNotEmpty;

  /// F3: checks the token against the repo. A token that can read but
  /// not write is refused here, not at the first save.
  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = _repo.text.trim();
    final token = _token.text.trim();
    final api = ref.read(gitHubApiFactoryProvider)(
      token: token,
      repository: repository,
    );
    try {
      final info = await api.getRepo();
      if (!mounted) return;
      if (!info.canPush) {
        setState(() {
          _busy = false;
          _error =
              'The token can read this repo but not write to it. It needs '
              'Contents: read and write.';
        });
        return;
      }
      _api = api;
      _defaultBranch = info.defaultBranch;
      _branch = info.defaultBranch;
      if (widget.replaceToken) {
        await ref.read(libraryConnectionProvider.notifier).replaceToken(token);
        unawaited(ref.read(librarySyncProvider)?.syncNow());
        if (mounted) Navigator.pop(context);
      } else {
        _go(FirstRunStep.branch);
      }
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeGitHubFailure(e);
      });
    }
  }

  /// F4: the repo's branches, the default first and the rest A to Z, each
  /// with when its head was committed. The default is preselected.
  Future<void> _loadBranches() async {
    setState(() {
      _branches = null;
      _error = null;
    });
    final api = _api!;
    final now = DateTime.now();
    try {
      final list = await api.listBranches();
      String? updated(BranchInfo b) =>
          b.updated == null ? null : relativeTime(b.updated!, now: now);
      final others = list.where((b) => b.name != _defaultBranch).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      final branches = [
        for (final b in list)
          if (b.name == _defaultBranch)
            RepoBranch(b.name, isDefault: true, updated: updated(b)),
        for (final b in others)
          RepoBranch(b.name, isDefault: false, updated: updated(b)),
      ];
      if (!mounted || _step != FirstRunStep.branch) return;
      setState(() {
        _branches = branches;
        // A repo without commits has no branches; the default branch is
        // then where the first commit goes.
        _branch = branches.isEmpty ? _defaultBranch : branches.first.name;
      });
    } on GitHubException catch (e) {
      if (!mounted || _step != FirstRunStep.branch) return;
      setState(() {
        _branches = const [];
        _error = describeGitHubFailure(e);
      });
    }
  }

  /// F6: adds the empty library to the repo. An existing file is never
  /// overwritten.
  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = _fileName.text.trim();
    // With a library kept on this phone the new file is that library.
    final library = _kept ?? const Library();
    try {
      await _api!.putFile(
        name,
        branch: _branch,
        bytes: utf8.encode(encodeLibrary(library)),
        message: FirstRunFlow.createMessage,
      );
      if (!mounted) return;
      _loadedEntries = library.entries.length;
      _go(FirstRunStep.done);
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.failure == GitHubFailure.conflict
            ? 'A file named $name already exists. Libri never overwrites '
                  'it: pick another name, or go back and use the file you '
                  'have.'
            : describeGitHubFailure(e);
      });
    }
  }

  /// F7: the JSON files in the repo, each opened to see whether it is a
  /// Libri library and how many entries it holds.
  Future<void> _loadFiles() async {
    setState(() {
      _files = null;
      _error = null;
    });
    final api = _api!;
    final now = DateTime.now();
    try {
      final tree = await api.listFiles(branch: _branch);
      final files = <RepoFile>[];
      for (final blob
          in tree
              .where((b) => b.size <= FirstRunFlow.maxFileBytes)
              .take(FirstRunFlow.maxFiles)) {
        final raw = await api.getFileRaw(blob.path, branch: _branch);
        int? entries;
        try {
          entries = decodeLibrary(raw!.text).entries.length;
        } on Object {
          entries = null;
        }
        String? updated;
        if (entries != null) {
          final commits = await api.commits(
            blob.path,
            branch: _branch,
            limit: 1,
          );
          if (commits.isNotEmpty) {
            updated = relativeTime(commits.first.date, now: now);
          }
        }
        files.add(
          RepoFile(
            blob.path,
            entries: entries,
            updated: updated,
            sha: blob.sha,
          ),
        );
      }
      if (!mounted || _step != FirstRunStep.existing) return;
      setState(() {
        _files = files;
        _file = files.indexWhere((f) => f.usable);
      });
    } on GitHubException catch (e) {
      if (!mounted || _step != FirstRunStep.existing) return;
      setState(() {
        _files = const [];
        _error = describeGitHubFailure(e);
      });
    }
  }

  RepoFile? get _chosenFile =>
      _files != null && _file >= 0 && _file < _files!.length
      ? _files![_file]
      : null;

  /// Whether the chosen file is another one than the kept library's.
  bool get _otherFile {
    final kept = _keptConnection;
    final file = _chosenFile;
    return kept != null &&
        file != null &&
        (_repo.text.trim() != kept.repository ||
            file.path != kept.file ||
            _branch != kept.branch);
  }

  Future<void> _useFile() async {
    final file = _chosenFile!;
    final kept = _kept;
    if (kept != null && _otherFile) {
      // D18: which library to keep. The same file needs no question: the
      // sync compares both copies to their base.
      final choice = await askWhichLibrary(
        context,
        phoneEntries: kept.entries.length,
        file: file,
      );
      if (choice == null || !mounted) return;
      if (choice == WhichLibrary.phone) {
        await _replaceFile(file, kept);
        return;
      }
    }
    _loadedEntries = file.entries ?? 0;
    _go(FirstRunStep.done);
  }

  /// D18, "This phone's": the kept library goes over the chosen file,
  /// then the file is connected like any other.
  Future<void> _replaceFile(RepoFile file, Library kept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api!.putFile(
        file.path,
        branch: _branch,
        bytes: utf8.encode(encodeLibrary(kept)),
        message: FirstRunFlow.replaceMessage,
        sha: file.sha,
      );
      if (!mounted) return;
      _loadedEntries = kept.entries.length;
      _replacedFile = true;
      _go(FirstRunStep.done);
    } on GitHubException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeGitHubFailure(e);
      });
    }
  }

  /// F7: the token and the connection are stored; the app then opens the
  /// library from GitHub. A flow pushed above the app (reconnect) pops.
  void _finish() {
    unawaited(
      ref
          .read(libraryConnectionProvider.notifier)
          .connect(
            repository: _repo.text.trim(),
            file: _choice == _FileChoice.newFile
                ? _fileName.text.trim()
                : _chosenFile!.path,
            branch: _branch,
            token: _token.text.trim(),
          ),
    );
    if (widget.reconnect) Navigator.pop(context);
  }

  Future<void> _openTokenHelp() async {
    try {
      await launchUrl(
        FirstRunFlow.tokenHelpUrl,
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      // No browser to open it: nothing to do.
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _previous == null && !widget.replaceToken;
    final repository = _repo.text.trim();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: switch (_step) {
            FirstRunStep.splash => const _Splash(),
            FirstRunStep.welcome => _Welcome(
              onStart: () => _go(FirstRunStep.connect),
            ),
            FirstRunStep.connect => _StepPage(
              label: widget.replaceToken ? null : 'Step 1 of 4',
              onBack: _back,
              title: 'Connect GitHub',
              body:
                  'Libri reads and saves your library in a GitHub repo you '
                  'own. A private repo is fine.',
              content: [
                const FieldLabel('Repository'),
                AppTextField(
                  controller: _repo,
                  hintText: 'owner/repo',
                  textCapitalization: TextCapitalization.none,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                const FieldLabel('Access token'),
                AppTextField(
                  controller: _token,
                  hintText: 'github_pat_…',
                  obscureText: true,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _canConnect ? _connect() : null,
                ),
                const SizedBox(height: 6),
                const _Help(
                  'A fine-grained token that can read and write this one '
                  'repo. It stays in the phone\'s secure storage and never '
                  'leaves the device.',
                ),
                if (_error case final error?) _ErrorText(error),
              ],
              footer: [
                _BusyButton(
                  label: widget.replaceToken ? 'Save token' : 'Connect',
                  busyLabel: 'Connecting…',
                  busy: _busy,
                  onPressed: _canConnect ? _connect : null,
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: 'How do I create a token?',
                  kind: AppButtonKind.text,
                  onPressed: _openTokenHelp,
                ),
              ],
            ),
            FirstRunStep.branch => _StepPage(
              label: 'Step 2 of 4',
              onBack: _back,
              title: 'Pick a branch',
              body:
                  'Branches in $repository. Libri reads and saves your '
                  'library on the one you pick.',
              bodyHighlights: [repository],
              contentTopPadding: 20,
              content: [
                if (_branches case final branches?) ...[
                  for (final branch in branches)
                    _BranchRow(
                      branch: branch,
                      selected: branch.name == _branch,
                      onTap: () => setState(() => _branch = branch.name),
                    ),
                  const SizedBox(height: 14),
                  if (_error case final error?)
                    _ErrorText(error)
                  else if (branches.isEmpty)
                    _Help(
                      'This repo has no branches yet. Libri makes its first '
                      'commit on $_defaultBranch.',
                    )
                  else
                    const _Help(
                      'Libri commits straight to this branch, with no pull '
                      'requests.',
                    ),
                ] else
                  const _Help('Looking for branches in the repo…'),
              ],
              footer: [
                if (_error != null)
                  AppButton(
                    label: 'Try again',
                    kind: AppButtonKind.outline,
                    onPressed: _loadBranches,
                  )
                else
                  AppButton(
                    label: 'Continue',
                    onPressed: _branches == null
                        ? null
                        : () => _go(FirstRunStep.file),
                  ),
              ],
            ),
            FirstRunStep.file => _StepPage(
              label: 'Step 3 of 4',
              onBack: _back,
              title: 'Your library file',
              body:
                  'Libri keeps everything in one JSON file in '
                  '$repository on $_branch. Start fresh, or use a file you '
                  'already have.',
              bodyHighlights: [repository, _branch],
              content: [
                _ChoiceCard(
                  icon: AppIcons.filePlus,
                  title: 'Create a new library',
                  body:
                      'Libri makes an empty library file in your repo. '
                      'Pick this if you are starting out.',
                  selected: _choice == _FileChoice.newFile,
                  onTap: () => setState(() => _choice = _FileChoice.newFile),
                ),
                const SizedBox(height: 12),
                _ChoiceCard(
                  icon: AppIcons.folder,
                  title: 'Use a file I already have',
                  body:
                      'Pick a Libri library file that is already in the repo.',
                  selected: _choice == _FileChoice.existing,
                  onTap: () => setState(() => _choice = _FileChoice.existing),
                ),
              ],
              footer: [
                AppButton(
                  label: 'Continue',
                  onPressed: () => _go(
                    _choice == _FileChoice.newFile
                        ? FirstRunStep.create
                        : FirstRunStep.existing,
                  ),
                ),
              ],
            ),
            FirstRunStep.create => _StepPage(
              label: 'Step 4 of 4',
              onBack: _back,
              title: 'Create a new library',
              body:
                  'Libri adds an empty library file to your repo and '
                  'commits it for you.',
              content: [
                const FieldLabel('File name'),
                AppTextField(
                  controller: _fileName,
                  hintText: 'library.json',
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 6),
                _Help(
                  'Saved at the top of $repository on $_branch. Libri never '
                  'overwrites a file that already exists.',
                ),
                if (_error case final error?) _ErrorText(error),
                const SizedBox(height: 16),
                const FieldLabel('What gets added'),
                if (_kept case final kept?)
                  _CodeBlock(
                    'The library kept on this phone: '
                    '${kept.entries.length} '
                    '${kept.entries.length == 1 ? 'entry' : 'entries'}, '
                    '${kept.plans.length} '
                    '${kept.plans.length == 1 ? 'plan' : 'plans'}.',
                  )
                else
                  const _CodeBlock(
                    '{\n'
                    '  "version": 2,\n'
                    '  "tags": {},\n'
                    '  "entries": [],\n'
                    '  "plans": []\n'
                    '}',
                  ),
                const SizedBox(height: 6),
                const _Help('Commit message: “${FirstRunFlow.createMessage}”'),
              ],
              footer: [
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Creating ${_fileName.text.trim()} and pushing to '
                      'GitHub…',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall!
                          .copyWith(fontSize: 14, fontStyle: FontStyle.normal),
                    ),
                  ),
                _BusyButton(
                  label: 'Create library',
                  busyLabel: 'Creating…',
                  busy: _busy,
                  onPressed: _fileName.text.trim().isEmpty ? null : _create,
                ),
              ],
            ),
            FirstRunStep.existing => _StepPage(
              label: 'Step 4 of 4',
              onBack: _back,
              title: 'Pick your file',
              body:
                  'JSON files found in $repository on $_branch. Only files '
                  'in Libri\'s format can be used.',
              contentTopPadding: 20,
              content: [
                if (_files case final files?) ...[
                  for (final (i, file) in files.indexed)
                    _FileRow(
                      file: file,
                      selected: file.usable && i == _file,
                      onTap: file.usable
                          ? () => setState(() => _file = i)
                          : null,
                    ),
                  const SizedBox(height: 14),
                  if (_error case final error?)
                    _ErrorText(error)
                  else if (files.isEmpty)
                    const _Help(
                      'No JSON files found. Make sure the file is in this '
                      'repo and ends in .json, or go back and create a '
                      'new library.',
                    )
                  else
                    const _Help(
                      'Don\'t see your file? Make sure it\'s in this repo '
                      'and ends in .json.',
                    ),
                ] else
                  const _Help('Looking for JSON files in the repo…'),
              ],
              footer: [
                if (_error != null)
                  AppButton(
                    label: 'Try again',
                    kind: AppButtonKind.outline,
                    onPressed: _loadFiles,
                  )
                else
                  AppButton(
                    label: 'Use this file',
                    onPressed: _chosenFile?.usable ?? false ? _useFile : null,
                  ),
              ],
            ),
            FirstRunStep.done => _Done(
              text: _choice == _FileChoice.newFile
                  ? _kept != null
                        ? '${_fileName.text.trim()} is now in $repository '
                              'on $_branch, with the $_loadedEntries '
                              '${_loadedEntries == 1 ? 'entry' : 'entries'} '
                              'from this phone.'
                        : '${_fileName.text.trim()} is now in $repository '
                              'on $_branch. Add your first entry with the + '
                              'button.'
                  : _replacedFile
                  ? '${_chosenFile?.path} now holds the $_loadedEntries '
                        '${_loadedEntries == 1 ? 'entry' : 'entries'} from '
                        'this phone.'
                  : 'Loaded $_loadedEntries '
                        '${_loadedEntries == 1 ? 'entry' : 'entries'} from '
                        '${_chosenFile?.path}.',
              onOpen: _finish,
            ),
          },
        ),
      ),
    );
  }
}

/// A primary button that reads "Connecting…" or "Creating…" while its
/// call runs: dimmed rather than disabled, as on the canvas, and a second
/// press is ignored by the caller.
class _BusyButton extends StatelessWidget {
  const _BusyButton({
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: AppButton(label: busy ? busyLabel : label, onPressed: onPressed),
    );
  }
}

/// What went wrong, under the field it concerns.
class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = LibraryColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontSize: 13.5,
            fontStyle: FontStyle.normal,
            height: 1.4,
            color: colors.dangerText,
          ),
        ),
      ),
    );
  }
}

/// F1: the mark in the middle, the name near the bottom.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(child: LibriLogo(width: 168)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: Text(
            appName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

/// F2.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LibriLogo(width: 134),
                const SizedBox(height: 32),
                Text(
                  'Welcome to $appName',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineLarge!.copyWith(height: 1.1),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    'Keep track of your movies, shows, books, games, music '
                    'and anime, and plan what to enjoy next.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontSize: 16,
                      color: colors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppButton(label: 'Get started', onPressed: onStart),
              const SizedBox(height: 10),
              Text(
                'Your library is saved in a GitHub repo you own.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall!.copyWith(
                  fontSize: 13,
                  fontStyle: FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// F3 to F7: a back arrow with the step label, a title and a line under
/// it, the step's content, and the buttons pinned to the bottom.
class _StepPage extends StatelessWidget {
  const _StepPage({
    required this.label,
    required this.onBack,
    required this.title,
    required this.body,
    required this.content,
    required this.footer,
    this.bodyHighlights = const [],
    this.contentTopPadding = 24,
  });

  /// "Step 1 of 4"; null when the step stands alone (Replace token).
  final String? label;
  final VoidCallback onBack;
  final String title;
  final String body;

  /// Parts of [body] set in the main text color, in the order they occur:
  /// the repo name, the branch.
  final List<String> bodyHighlights;
  final List<Widget> content;
  final List<Widget> footer;
  final double contentTopPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final bodyStyle = theme.textTheme.bodyMedium!.copyWith(color: colors.muted);
    final highlightStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    // The body split at its highlights, each found after the one before.
    final spans = <TextSpan>[];
    var at = 0;
    for (final highlight in bodyHighlights) {
      if (highlight.isEmpty) continue;
      final start = body.indexOf(highlight, at);
      if (start < 0) continue;
      spans.add(TextSpan(text: body.substring(at, start)));
      spans.add(TextSpan(text: highlight, style: highlightStyle));
      at = start + highlight.length;
    }
    spans.add(TextSpan(text: body.substring(at)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 24, 20, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                tooltip: 'Back',
                color: theme.colorScheme.onSurface,
                icon: const StrokeIcon(AppIcons.back, size: 22),
              ),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label!.toUpperCase(),
                  style: theme.textTheme.labelSmall!.copyWith(
                    letterSpacing: 0.78,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            children: [
              Text(
                title,
                style: theme.textTheme.headlineMedium!.copyWith(height: 1.1),
              ),
              const SizedBox(height: 8),
              Text.rich(TextSpan(style: bodyStyle, children: spans)),
              SizedBox(height: contentTopPadding),
              ...content,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: footer,
          ),
        ),
      ],
    );
  }
}

/// Muted help under a field.
class _Help extends StatelessWidget {
  const _Help(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(fontSize: 13.5, fontStyle: FontStyle.normal, height: 1.4),
    );
  }
}

/// The JSON that F6 adds to the repo.
class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Text(
        code,
        style: theme.textTheme.bodyMedium!.copyWith(
          fontFamily: AppFonts.code,
          fontSize: 13,
          height: 1.55,
        ),
      ),
    );
  }
}

/// F5: one of the two ways to get a library file.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final StrokeIconData icon;
  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: selected ? theme.colorScheme.primary : colors.surfaceHigh,
        width: 2,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: theme.colorScheme.surface,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.selectedFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: StrokeIcon(
                      icon,
                      size: 22,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 16.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontSize: 14,
                          fontStyle: FontStyle.normal,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RadioMark(selected: selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// F4: a branch in the repo, with the branch icon, a Default badge on the
/// repo's default branch and when it was last updated.
class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.selected,
    required this.onTap,
  });

  final RepoBranch branch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.selectedFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: StrokeIcon(
                    AppIcons.branch,
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            branch.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (branch.isDefault) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.selectedFill,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Default',
                              style: theme.textTheme.labelSmall!.copyWith(
                                fontSize: 12,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (branch.info case final info?) ...[
                      const SizedBox(height: 3),
                      Text(
                        info,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              RadioMark(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// F7: a JSON file in the repo. A file that is not a library is dimmed
/// and cannot be picked.
class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final RepoFile file;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: file.usable ? 1 : 0.5,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        file.info,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                RadioMark(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// F8.
class _Done extends StatelessWidget {
  const _Done({required this.text, required this.onOpen});

  final String text;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = LibraryColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: StrokeIcon(
                      AppIcons.checkBold,
                      size: 40,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'You\'re all set',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium!.copyWith(height: 1.1),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontSize: 16,
                      color: colors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: AppButton(label: 'Open $appName', onPressed: onOpen),
        ),
      ],
    );
  }
}
