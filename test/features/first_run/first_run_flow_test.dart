import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/github/github_api.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/dev/fake_github_api.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/first_run/first_run_flow.dart';
import 'package:library_app/features/library/home_type_provider.dart';
import 'package:library_app/features/settings/connection_screen.dart';
import 'package:library_app/features/shell/app_shell.dart';
import 'package:library_app/features/sync/sync_state.dart';
import 'package:library_app/main.dart';
import 'package:library_app/widgets/libri_logo.dart';

import '../../helpers/package_info.dart';
import '../../helpers/pump.dart';
import '../../helpers/pump_app.dart';

void main() {
  late FakeGitHubApi github;
  final fixtureText = encodeLibrary(loadFixture());

  setUp(() => github = FakeGitHubApi.demo(fixtureText));

  /// The flow with the fake repo behind every token.
  Future<ProviderContainer> pumpFlow(
    WidgetTester tester, {
    FirstRunStep step = FirstRunStep.welcome,
  }) => pumpApp(
    tester,
    FirstRunFlow(initialStep: step),
    overrides: [
      gitHubApiFactoryProvider.overrideWithValue(
        ({required token, required repository}) => github,
      ),
    ],
  );

  /// The flow while a library (the fixture) is kept on this phone after a
  /// disconnect (Settings › Disconnect: keep or delete): what First run ›
  /// Different file: which library? and Create a new library are about.
  Future<ProviderContainer> pumpKept(WidgetTester tester) => pumpApp(
    tester,
    const FirstRunFlow(initialStep: FirstRunStep.connect),
    overrides: [
      gitHubApiFactoryProvider.overrideWithValue(
        ({required token, required repository}) => github,
      ),
      initialConnectionProvider.overrideWithValue(
        const LibraryConnection(connected: false, keptLocally: true),
      ),
    ],
  );

  /// First run › Library file: new or existing to Pick an existing file, with
  /// [path] picked and "Use this file" pressed.
  Future<void> useFile(WidgetTester tester, String path) async {
    await tester.tap(find.text('Use a file I already have'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(path));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this file'));
    await tester.pumpAndSettle();
  }

  /// First run › Connect GitHub with the fields filled in and Connect pressed;
  /// the fake's latency, if any, is waited out.
  Future<void> fillConnect(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, 'ekmanch/library');
    await tester.enterText(find.byType(TextField).last, 'github_pat_x');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  }

  /// [fillConnect], then First run › Pick a branch passed with the default
  /// branch when the connection was accepted.
  Future<void> connect(WidgetTester tester) async {
    await fillConnect(tester);
    if (find.text('Pick a branch').evaluate().isEmpty) return;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('the splash gives way to the welcome screen', (tester) async {
    await pumpApp(tester, const FirstRunFlow());
    expect(find.byType(LibriLogo), findsOneWidget);
    expect(find.text('Libri'), findsOneWidget);
    expect(find.text('Welcome to Libri'), findsNothing);
    await tester.pump(FirstRunFlow.splashDuration);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Libri'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('creating a new library walks the first run and connects', (
    tester,
  ) async {
    github = FakeGitHubApi(); // An empty repo, with only `main`.
    final container = await pumpFlow(tester);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    // First run › Connect GitHub: Connect needs a repo and a token, then asks
    // GitHub.
    expect(find.text('STEP 1 OF 4'), findsOneWidget);
    expect(find.text('Connect GitHub'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Connect');
    expect(tester.widget<FilledButton>(button).enabled, isFalse);
    await fillConnect(tester);
    expect(github.requests, ['GET repo', 'GET branches']);

    // First run › Pick a branch: the one branch, the default, is preselected.
    expect(find.text('STEP 2 OF 4'), findsOneWidget);
    expect(find.text('Pick a branch'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(isSelected(tester, find.text('main')), isTrue);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // First run › Library file: new or existing: new is the default choice.
    expect(find.text('STEP 3 OF 4'), findsOneWidget);
    expect(find.text('Your library file'), findsOneWidget);
    expect(find.textContaining('ekmanch/library on main.'), findsOneWidget);
    expect(isSelected(tester, find.text('Create a new library')), isTrue);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // First run › Create a new library: the create step with its preview, then
    // the commit.
    expect(find.text('STEP 4 OF 4'), findsOneWidget);
    expect(find.textContaining('"version": 2'), findsOneWidget);
    expect(find.text('Commit message: “Create Libri library”'), findsOneWidget);
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(github.text('library.json'), encodeLibrary(const Library()));
    final commits = await github.commits('library.json', branch: 'main');
    expect(commits.single.message, 'Create Libri library');

    // First run › All set.
    expect(find.text('You\'re all set'), findsOneWidget);
    expect(
      find.text(
        'library.json is now in ekmanch/library on main. '
        'Add your first entry with the + button.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Libri'));
    await tester.pumpAndSettle();
    final connection = container.read(libraryConnectionProvider);
    expect(connection.connected, isTrue);
    expect(connection.repository, 'ekmanch/library');
    expect(connection.file, 'library.json');
    expect(connection.branch, 'main');
    expect(container.read(tokenProvider), 'github_pat_x');
  });

  testWidgets('the create step shows its progress and refuses an existing '
      'file', (tester) async {
    github.latency = const Duration(milliseconds: 300);
    await pumpFlow(tester, step: FirstRunStep.connect);
    await tester.enterText(find.byType(TextField).first, 'ekmanch/library');
    await tester.enterText(find.byType(TextField).last, 'github_pat_x');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    expect(find.text('Connecting…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // First run › Pick a branch while the branches load.
    expect(find.text('Looking for branches in the repo…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Looking for branches in the repo…'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create library'));
    await tester.pump();
    expect(find.text('Creating…'), findsOneWidget);
    expect(
      find.text('Creating library.json and pushing to GitHub…'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A file named library.json already exists'),
      findsOneWidget,
    );
    expect(find.text('Create library'), findsOneWidget);
    expect(find.text('You\'re all set'), findsNothing);
    expect(github.text('library.json'), isNot(encodeLibrary(const Library())));
  });

  testWidgets('connect says what went wrong with the token or the repo', (
    tester,
  ) async {
    await pumpFlow(tester, step: FirstRunStep.connect);
    for (final (failure, message) in [
      (GitHubFailure.unauthorized, 'GitHub refused the token'),
      (GitHubFailure.notFound, 'Repository not found, or the token cannot'),
      (GitHubFailure.offline, 'No connection'),
      (GitHubFailure.rateLimited, 'rate limiting'),
    ]) {
      github.failure = failure;
      await connect(tester);
      expect(find.textContaining(message), findsOneWidget, reason: '$failure');
      expect(find.text('Your library file'), findsNothing);
    }
    github.failure = null;
    github.canPush = false;
    await connect(tester);
    expect(find.textContaining('not write to it'), findsOneWidget);
    github.canPush = true;
    await connect(tester);
    expect(find.text('Your library file'), findsOneWidget);
  });

  testWidgets('picking an existing file skips files that are not libraries', (
    tester,
  ) async {
    github.latency = const Duration(milliseconds: 50);
    final container = await pumpFlow(tester, step: FirstRunStep.connect);
    await connect(tester);
    await tester.tap(find.text('Use a file I already have'));
    await tester.pumpAndSettle();
    expect(isSelected(tester, find.text('Use a file I already have')), isTrue);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Looking for JSON files in the repo…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Pick your file'), findsOneWidget);
    expect(
      find.text('Libri library · 63 entries · updated 2 days ago'),
      findsOneWidget,
    );
    expect(find.textContaining('31 entries · updated Mar 14'), findsOneWidget);
    expect(find.text('Not a Libri library file'), findsOneWidget);
    expect(isSelected(tester, find.text('library.json')), isTrue);
    await tester.tap(find.text('data/old-lists.json'));
    await tester.pumpAndSettle();
    expect(isSelected(tester, find.text('library.json')), isTrue);
    await tester.tap(find.text('backup/library-2025.json'));
    await tester.pumpAndSettle();
    expect(isSelected(tester, find.text('backup/library-2025.json')), isTrue);
    await tester.tap(find.text('Use this file'));
    await tester.pumpAndSettle();
    expect(
      find.text('Loaded 31 entries from backup/library-2025.json.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Libri'));
    await tester.pumpAndSettle();
    expect(
      container.read(libraryConnectionProvider).file,
      'backup/library-2025.json',
    );
  });

  testWidgets(
    'the branch step lists the default branch first with a badge, the rest A '
    'to Z, and preselects the default',
    (tester) async {
      await pumpFlow(tester, step: FirstRunStep.connect);
      await fillConnect(tester);
      expect(find.text('Pick a branch'), findsOneWidget);
      expect(
        find.textContaining('Branches in ekmanch/library.'),
        findsOneWidget,
      );
      // The fake lists dev, main, app-sync-test; the step sorts them.
      final tops = [
        for (final name in ['main', 'app-sync-test', 'dev'])
          tester.getTopLeft(find.text(name)).dy,
      ];
      expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue, reason: '$tops');
      expect(find.text('Default'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Default')).dy, closeTo(tops[0], 12));
      expect(find.text('Updated 2 days ago'), findsOneWidget);
      expect(find.text('Updated 7 days ago'), findsOneWidget);
      expect(find.textContaining('Updated Aug 9'), findsOneWidget);
      expect(isSelected(tester, find.text('main')), isTrue);
      expect(isSelected(tester, find.text('dev')), isFalse);
      expect(find.textContaining('no pull requests'), findsOneWidget);
    },
  );

  testWidgets('the chosen branch is used for the file, the listing and the '
      'commit, and saved with the connection', (tester) async {
    final container = await pumpFlow(tester, step: FirstRunStep.connect);
    await fillConnect(tester);
    await tester.tap(find.text('dev'));
    await tester.pumpAndSettle();
    expect(isSelected(tester, find.text('dev')), isTrue);
    expect(isSelected(tester, find.text('main')), isFalse);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // First run › Library file: new or existing and Pick an existing file name
    // the branch; the listing reads it.
    expect(find.textContaining('ekmanch/library on dev.'), findsOneWidget);
    await tester.tap(find.text('Use a file I already have'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('JSON files found in ekmanch/library on dev.'),
      findsOneWidget,
    );
    expect(github.lastBranch, 'dev');

    // First run › Create a new library commits to it, and All set says where
    // the file is.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a new library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Saved at the top of ekmanch/library on dev.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'libri.json');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    expect(github.lastBranch, 'dev');
    expect(
      find.text(
        'libri.json is now in ekmanch/library on dev. Add your first entry '
        'with the + button.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Open Libri'));
    await tester.pumpAndSettle();
    expect(container.read(libraryConnectionProvider).branch, 'dev');
  });

  testWidgets('the branch step reports a failed listing and can try again', (
    tester,
  ) async {
    github.latency = const Duration(milliseconds: 50);
    await pumpFlow(tester, step: FirstRunStep.connect);
    await tester.enterText(find.byType(TextField).first, 'ekmanch/library');
    await tester.enterText(find.byType(TextField).last, 'github_pat_x');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    // The repo call passes; the branches call then finds no connection.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.text('Looking for branches in the repo…'), findsOneWidget);
    github.failure = GitHubFailure.offline;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    github.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('the file step reports a failed listing and can try again', (
    tester,
  ) async {
    await pumpFlow(tester, step: FirstRunStep.connect);
    await connect(tester);
    github.failure = GitHubFailure.offline;
    await tester.tap(find.text('Use a file I already have'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.text('Use this file'), findsNothing);
    github.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('library.json'), findsOneWidget);
    expect(find.text('Use this file'), findsOneWidget);
  });

  testWidgets('back goes one step at a time, also with the system back', (
    tester,
  ) async {
    await pumpFlow(tester, step: FirstRunStep.connect);
    await connect(tester);
    expect(find.text('Your library file'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a branch'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Connect GitHub'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Libri'), findsOneWidget);
  });

  testWidgets('the app shows the first run until connected, then the shell', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(
            loadJson: () async => encodeLibrary(loadFixture()),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LibraryApp(),
      ),
    );
    await tester.pump(FirstRunFlow.splashDuration);
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    await container
        .read(libraryConnectionProvider.notifier)
        .connect(
          repository: 'ekmanch/library',
          file: 'library.json',
          branch: 'main',
          token: 'github_pat_x',
        );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(FirstRunFlow), findsNothing);
  });

  testWidgets('deleting the library from the phone starts over at the welcome; '
      'keeping it stays on the shell', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(
            loadJson: () async => encodeLibrary(loadFixture()),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    await container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: true);
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(container.read(libraryConnectionProvider).keptLocally, isTrue);

    await container
        .read(libraryConnectionProvider.notifier)
        .disconnect(keepLibrary: false);
    await tester.pumpAndSettle();
    expect(find.byType(FirstRunFlow), findsOneWidget);
    // Straight to the welcome screen, not the splash.
    expect(find.text('Get started'), findsOneWidget);
  });

  group('with a library kept on this phone', () {
    final kept = loadFixture();
    final n = kept.entries.length;

    testWidgets(
      'another file asks which library; "This phone\'s" replaces it',
      (tester) async {
        await pumpKept(tester);
        await connect(tester);
        await useFile(tester, 'backup/library-2025.json');
        expect(find.text('Which library do you want to keep?'), findsOneWidget);
        expect(find.text('This phone · $n entries'), findsOneWidget);
        expect(
          find.text('GitHub · backup/library-2025.json · 31 entries'),
          findsOneWidget,
        );
        await tester.tap(find.text("This phone's"));
        await tester.pumpAndSettle();
        expect(github.text('backup/library-2025.json'), fixtureText);
        final commits = await github.commits(
          'backup/library-2025.json',
          branch: 'main',
          limit: 1,
        );
        expect(commits.single.message, FirstRunFlow.replaceMessage);
        expect(
          find.text(
            'backup/library-2025.json now holds the $n entries from this '
            'phone.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('"The one on GitHub" takes the file as before', (tester) async {
      await pumpKept(tester);
      await connect(tester);
      await useFile(tester, 'backup/library-2025.json');
      await tester.tap(find.text('The one on GitHub'));
      await tester.pumpAndSettle();
      expect(github.putCount, 0);
      expect(
        find.text('Loaded 31 entries from backup/library-2025.json.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Cancel stays on the file list, and the same file asks nothing',
      (tester) async {
        await pumpKept(tester);
        await connect(tester);
        await useFile(tester, 'backup/library-2025.json');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Pick your file'), findsOneWidget);
        expect(find.text('Which library do you want to keep?'), findsNothing);

        // The kept library's own file: the sync compares, no question.
        await tester.tap(find.text('library.json'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this file'));
        await tester.pumpAndSettle();
        expect(find.text('Which library do you want to keep?'), findsNothing);
        expect(
          find.text('Loaded 63 entries from library.json.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a new file is created from the phone\'s library', (
      tester,
    ) async {
      await pumpKept(tester);
      await connect(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"version": 2'), findsNothing);
      expect(
        find.textContaining('The library kept on this phone: $n entries'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'libri.json');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create library'));
      await tester.pumpAndSettle();
      expect(github.text('libri.json'), fixtureText);
      expect(
        find.text(
          'libri.json is now in ekmanch/library on main, with the $n '
          'entries from this phone.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('Open Libri always lands on the library home with All picked, '
      'also on a reconnect from Plans', (tester) async {
    github = FakeGitHubApi();
    mockPackageInfo();
    final container = ProviderContainer(
      overrides: [
        ...fakeLookupOverrides(),
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(
            loadJson: () async => encodeLibrary(loadFixture()),
          ),
        ),
        gitHubApiFactoryProvider.overrideWithValue(
          ({required token, required repository}) => github,
        ),
        initialConnectionProvider.overrideWithValue(
          const LibraryConnection(connected: false, keptLocally: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LibraryApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE PLAN').hitTestable(), findsOneWidget);

    // Movies picked, the Plans tab open, Settings › Library connection above
    // everything.
    container.read(homeTypeProvider.notifier).set(MediaType.movies);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE PLAN').hitTestable(), findsNothing);
    // The push completes when Settings › Library connection pops, so it is not
    // awaited.
    unawaited(openConnectionScreen(tester.element(find.byType(AppShell))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect to GitHub'));
    await tester.pumpAndSettle();
    await connect(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Libri'));
    await tester.pumpAndSettle();

    expect(find.byType(FirstRunFlow), findsNothing);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(container.read(homeTypeProvider), isNull);
    expect(container.read(libraryConnectionProvider).connected, isTrue);
    expect(find.text('ACTIVE PLAN').hitTestable(), findsOneWidget);
  });
}
