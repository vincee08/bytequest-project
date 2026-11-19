import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/core/widgets/learner_navigation_shell.dart';
import 'package:bytequest/data/learning_content_data.dart';
import 'package:bytequest/data/mission_content_data.dart';
import 'package:bytequest/models/assigned_activity_model.dart';
import 'package:bytequest/models/curriculum_model.dart';
import 'package:bytequest/models/homework_model.dart';
import 'package:bytequest/models/learner_learning_path_model.dart';
import 'package:bytequest/models/learner_quiz_model.dart';
import 'package:bytequest/models/mission_model.dart';
import 'package:bytequest/screens/courses/coc_details_screen.dart';
import 'package:bytequest/screens/dashboard/home_class_work_links.dart';
import 'package:bytequest/screens/learn/learn_screen.dart';
import 'package:bytequest/screens/learn/lesson_markdown.dart';
import 'package:bytequest/screens/learn/module_detail_screen.dart';
import 'package:bytequest/screens/learn/topic_reader_screen.dart';
import 'package:bytequest/screens/missions/missions_screen.dart';
import 'package:bytequest/screens/practice/practice_screen.dart';
import 'package:bytequest/screens/progress/progress_screen.dart';
import 'package:bytequest/screens/quizzes/quiz_details_screen.dart';
import 'package:bytequest/services/curriculum_service.dart';
import 'package:bytequest/services/learner_realtime_coordinator.dart';
import 'package:bytequest/services/mission_service.dart';
import 'package:bytequest/widgets/bytequest_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Fixtures: the shape returned by get_learner_curriculum().
// ---------------------------------------------------------------------------
Map<String, dynamic> mission(String code, int number, String title,
        {bool unlocked = true,
        bool verified = false,
        int runs = 0,
        int? best}) =>
    {
      'mission_code': code,
      'mission_number': number,
      'title': title,
      'unlocked': unlocked,
      'verified': verified,
      'runs': runs,
      'best_seconds': best,
    };

Map<String, dynamic> module(String code, int sequence, String title,
        {bool unlocked = false,
        bool completed = false,
        String? lockReason,
        bool newContent = false,
        List<Map<String, dynamic>> topics = const [],
        List<Map<String, dynamic>> missions = const [],
        int done = 0}) =>
    {
      'id': 'module-$code',
      'code': code,
      'title': title,
      'sequence_order': sequence,
      'source_reference': 'TR curriculum $code',
      'unlocked': unlocked,
      'completed': completed,
      'lock_reason': lockReason,
      'no_required_items': topics.isEmpty && missions.isEmpty,
      'new_content': newContent,
      'progress': {
        'done': done,
        'total': topics.length + missions.length,
        'percent': topics.length + missions.length == 0
            ? (completed ? 100 : 0)
            : done * 100 ~/ (topics.length + missions.length),
      },
      'topics': topics,
      'outcomes': [
        {
          'id': 'pc-$code-1',
          'code': '1.1',
          'statement': 'Unit assembly is planned and prepared'
        },
      ],
      'missions': missions,
    };

const lo12Reason =
    'Complete Module 1 · LO1.1 Assemble computer hardware to unlock.';
const coc2Reason = 'Complete COC 1 and pass the COC 1 practice quiz to unlock.';

Map<String, dynamic> projectionJson({bool topicDone = false}) => {
      'cocs': [
        {
          'coc_code': 'coc1',
          'title': 'Install and Configure Computer Systems',
          'order': 1,
          'unlocked': true,
          'completed': false,
          'lock_reason': null,
          'progress': {
            'done': topicDone ? 2 : 1,
            'total': 7,
            'percent': topicDone ? 28 : 14
          },
          'quiz': {'eligible': false, 'passed': false},
          'modules': [
            module('LO1.1', 1, 'Assemble computer hardware',
                unlocked: true,
                done: topicDone ? 2 : 1,
                topics: [
                  {
                    'id': 'topic-esd',
                    'revision_id': 'revision-esd',
                    'title': 'ESD precautions',
                    'summary': 'Why the wrist strap comes first.',
                    'sequence_order': 1,
                    'completed': topicDone,
                  }
                ],
                missions: [
                  mission('coc1_m1', 1, 'Identify Computer Parts and Tools',
                      verified: true, runs: 3, best: 280),
                  mission('coc1_m2', 2, 'Install Internal Components'),
                ]),
            module('LO1.2', 2,
                'Install operating system and drivers for peripherals/devices',
                lockReason: lo12Reason,
                missions: [
                  mission(
                      'coc1_m3', 3, 'Install and Configure a Workstation OS',
                      unlocked: false),
                  mission(
                      'coc1_m4', 4, 'Connect and Configure Peripheral Devices',
                      unlocked: false),
                ]),
            module('LO1.3', 3, 'Install the computer application software',
                lockReason:
                    'Complete Module 2 · LO1.2 Install operating system and drivers for peripherals/devices to unlock.'),
            module('LO1.4', 4, 'Conduct testing and documentation',
                lockReason:
                    'Complete Module 3 · LO1.3 Install the computer application software to unlock.',
                missions: [
                  mission('coc1_m5', 5, 'Install Drivers and Test the System',
                      unlocked: false)
                ]),
          ],
        },
        {
          'coc_code': 'coc2',
          'title': 'Set-up Computer Networks',
          'order': 2,
          'unlocked': false,
          'completed': false,
          'lock_reason': coc2Reason,
          'progress': {'done': 0, 'total': 6, 'percent': 0},
          'quiz': {'eligible': false, 'passed': false},
          'modules': [
            module('LO2.1', 1, 'Install network cables',
                lockReason: coc2Reason,
                missions: [
                  mission('coc2_m1', 1, 'Identify Network Devices and Tools',
                      unlocked: false)
                ]),
          ],
        },
      ],
    };

class FakeCurriculumService extends CurriculumService {
  FakeCurriculumService({this.failure});

  CurriculumProjection projection =
      CurriculumProjection.fromJson(projectionJson());
  final completedTopics = <String>[];
  CurriculumFailure? failure;
  int loads = 0;

  @override
  Future<CurriculumProjection> getCurriculum() async {
    loads++;
    return projection;
  }

  @override
  Future<CurriculumLesson> getLesson(String revisionId) async => CurriculumLesson(
      revisionId: revisionId,
      title: 'ESD precautions',
      summary: 'Why the wrist strap comes first.',
      bodyMarkdown:
          '# Before you open the case\n\nWear the **wrist strap** and ground it.\n\n- Unplug the PSU\n- Use the mat');

  @override
  Future<CurriculumProjection?> completeTopic(String topicId) async {
    if (failure != null) throw CurriculumException(failure!);
    completedTopics.add(topicId);
    projection = CurriculumProjection.fromJson(projectionJson(topicDone: true));
    return projection;
  }
}

class FailingCurriculumService extends CurriculumService {
  @override
  Future<CurriculumProjection> getCurriculum() async =>
      throw StateError('offline');
}

/// Hosts a screen on the current test surface (set with [setSurface]).
Widget host(Widget child, {double textScale = 1}) => ChangeNotifierProvider(
      create: (_) => LearnerRealtimeCoordinator(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child,
          ),
        ),
      ),
    );

Future<void> setSurface(WidgetTester tester, double width,
    [double height = 800]) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'sb_publishable_learn_test');
  });
  tearDownAll(() async => Supabase.instance.dispose());

  test('projection parsing keeps server state and tolerates missing fields',
      () {
    final data = CurriculumProjection.fromJson(projectionJson());
    expect(data.cocs.map((coc) => coc.cocCode), ['coc1', 'coc2']);
    final lo11 = data.cocs.first.modules.first;
    expect(lo11.unlocked, isTrue);
    expect(lo11.progress.total, 3);
    expect(lo11.missions.first.bestSeconds, 280);
    expect(data.cocs.first.modules[1].lockReason, lo12Reason);
    expect(data.cocs.first.modules[2].noRequiredItems, isTrue);
    expect(data.locateMission('coc1_m3')?.module.code, 'LO1.2');
    expect(data.currentCoc?.cocCode, 'coc1');
    expect(data.missionsTotal, 6);
    expect(data.missionsVerified, 1);
    final sparse = CurriculumProjection.fromJson({
      'cocs': [
        {
          'coc_code': 'COC3',
          'modules': [
            {
              'id': 'm',
              'missions': [
                {'mission_code': 'coc3_m1'}
              ]
            }
          ]
        }
      ]
    });
    expect(sparse.cocs.single.cocCode, 'coc3');
    expect(sparse.cocs.single.number, 3);
    expect(sparse.modules.single.unlocked, isFalse);
    expect(sparse.modules.single.missions.single.runs, 0);
    expect(CurriculumProjection.fromJson(null).cocs, isEmpty);
  });

  test('lesson Markdown is parsed into safe blocks and never runs HTML', () {
    final blocks = parseLessonMarkdown(
        '# ESD\n\nWear the **strap**.\n\n1. Off\n2. Unplug\n\n<script>x</script>');
    expect(blocks.map((block) => block.type), [
      LessonBlockType.heading,
      LessonBlockType.paragraph,
      LessonBlockType.list,
      LessonBlockType.paragraph,
    ]);
    expect(blocks[1].inlines.first.map((part) => part.kind), [
      LessonInlineKind.text,
      LessonInlineKind.strong,
      LessonInlineKind.text
    ]);
    expect(blocks[2].ordered, isTrue);
    expect(blocks[3].inlines.first.single.text, '<script>x</script>');
  });

  testWidgets(
      'bottom navigation offers Home, Learn, Practice, Progress and Rewards at 320 px with large text',
      (tester) async {
    await setSurface(tester, 320, 568);
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 568), textScaler: TextScaler.linear(2)),
        child: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: ByteQuestBottomNav(
                currentIndex: selected,
                onTap: (value) => setState(() => selected = value)),
          ),
        ),
      ),
    ));
    for (final label in ['Home', 'Learn', 'Practice', 'Progress', 'Rewards']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Practice'));
    await tester.pump();
    expect(selected, 2);
    await tester.tap(find.text('Rewards'));
    await tester.pump();
    expect(selected, 4);
    for (final element in find.byType(InkWell).evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('navigation shell hosts five destinations in tab order',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: LearnerNavigationShell(destinations: [
        for (final label in [
          'Home body',
          'Learn body',
          'Practice body',
          'Progress body',
          'Rewards body'
        ])
          Center(child: Text(label)),
      ]),
    ));
    expect(ByteQuestBottomNav.destinations.map((d) => d.$2), [
      LearningContentData.navHome,
      LearningContentData.navLearn,
      LearningContentData.navPractice,
      LearningContentData.navProgress,
      LearningContentData.navRewards
    ]);
    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    expect(find.text('Practice body'), findsOneWidget);
    await tester.tap(find.text('Rewards'));
    await tester.pumpAndSettle();
    expect(find.text('Rewards body'), findsOneWidget);
  });

  testWidgets(
      'Learn shows locked, unlocked and completed module states with prerequisite text',
      (tester) async {
    await setSurface(tester, 420, 2600);
    final service = FakeCurriculumService();
    var assessmentPath = 0, quizzes = 0;
    await tester.pumpWidget(host(LearnScreen(
        service: service,
        openAssessmentPath: () => assessmentPath++,
        openClassQuizzes: () => quizzes++)));
    await tester.pumpAndSettle();
    expect(find.text('Assemble computer hardware'), findsOneWidget);
    expect(find.text(lo12Reason), findsOneWidget);
    expect(find.text(LearningContentData.noRequiredItems), findsOneWidget);
    expect(find.text(LearningContentData.lockedLabel), findsNWidgets(3));
    expect(find.text(LearningContentData.inProgressLabel), findsOneWidget);
    expect(find.text(LearningContentData.progressValue(1, 3)), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            RegExp(r'Module 2, LO1\.2 Install operating system.*, Locked')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('coc-chip-coc2')));
    await tester.pumpAndSettle();
    expect(find.text('Install network cables'), findsOneWidget);
    expect(find.text(coc2Reason), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('learn-assessment-path')));
    await tester.tap(find.byKey(const ValueKey('learn-class-quizzes')));
    expect((assessmentPath, quizzes), (1, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Learn shows an actionable error state when the projection fails',
      (tester) async {
    await tester
        .pumpWidget(host(LearnScreen(service: FailingCurriculumService())));
    await tester.pumpAndSettle();
    expect(find.text(LearningContentData.curriculumUnavailableTitle),
        findsOneWidget);
    expect(find.text(LearningContentData.retry), findsOneWidget);
  });

  testWidgets(
      'a learner reads a lesson and marks it complete through the server',
      (tester) async {
    await setSurface(tester, 420, 2400);
    final service = FakeCurriculumService();
    await tester.pumpWidget(host(ModuleDetailScreen(
        cocCode: 'coc1',
        moduleId: 'module-LO1.1',
        initial: service.projection,
        service: service)));
    await tester.pumpAndSettle();
    expect(find.text('ESD precautions'), findsOneWidget);
    expect(find.text('Unit assembly is planned and prepared'), findsOneWidget);
    expect(find.text('Identify Computer Parts and Tools'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-topic-esd')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicReaderScreen), findsOneWidget);
    expect(find.text('Before you open the case'), findsOneWidget);
    expect(find.text(LearningContentData.markComplete), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mark-topic-complete')));
    await tester.pumpAndSettle();
    expect(service.completedTopics, ['topic-esd']);
    expect(find.text(LearningContentData.lessonCompleted), findsWidgets);
    expect(find.text(LearningContentData.markComplete), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(TopicReaderScreen), findsNothing);
    expect(find.text(LearningContentData.progressValue(2, 3)), findsOneWidget);
  });

  // Rest Minor 9 (A2 #3, quizzes): module detail lists the class quizzes
  // linked to the module, and only those.
  testWidgets('module detail lists the class quizzes linked to the module',
      (tester) async {
    await setSurface(tester, 420, 3000);
    final service = FakeCurriculumService();
    LearnerQuizSummary quiz(String id, List<String> modules,
            {String coc = 'coc1'}) =>
        LearnerQuizSummary.fromJson({
          'assignment_id': 'assignment-$id',
          'quiz_version_id': 'version-$id',
          'quiz_id': 'quiz-$id',
          'title': 'Class quiz $id',
          'class_id': 'class',
          'class_title': 'CSS 11-A',
          'coc_code': coc,
          'is_available': true,
          'module_codes': modules,
        });
    await tester.pumpWidget(host(ModuleDetailScreen(
      cocCode: 'coc1',
      moduleId: 'module-LO1.1',
      initial: service.projection,
      service: service,
      loadQuizzes: () async => [
        quiz('linked', ['LO1.1']),
        quiz('other-module', ['LO1.2']),
        quiz('other-coc', ['LO1.1'], coc: 'coc2'),
      ],
    )));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('module-quiz-assignment-linked')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.moduleQuizzesTitle), findsOneWidget);
    expect(find.text('Class quiz linked'), findsOneWidget);
    expect(find.text('Class quiz other-module'), findsNothing);
    expect(find.text('Class quiz other-coc'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('module-quiz-assignment-linked')));
    await tester.pumpAndSettle();
    expect(find.byType(QuizDetailsScreen), findsOneWidget);
  });

  // Rest Minor 10 (A2 #2): the Assessment path screens use the same
  // module-level access as Practice.
  test('COC details mission access follows the curriculum modules', () {
    final projection = FakeCurriculumService().projection;
    Mission mission(String id, {bool? unlocked}) => Mission(
        id: id,
        cocId: 'coc1',
        missionCode: id.toUpperCase(),
        missionNumber: 1,
        title: id,
        missionType: MissionType.identification,
        orderIndex: 1,
        isUnlocked: unlocked);
    expect(curriculumMissionUnlocked(projection, mission('coc1_m1')), isTrue);
    expect(
        curriculumMissionUnlocked(
            projection, mission('coc1_m3', unlocked: true)),
        isFalse,
        reason: 'a COC-level unlock does not open a locked module');
    expect(curriculumMissionUnlocked(null, mission('coc1_m3', unlocked: true)),
        isTrue,
        reason: 'before the curriculum loads, the earlier rule applies');
  });

  testWidgets('COC details uses the curriculum unlock, not the COC progress',
      (tester) async {
    await setSurface(tester, 420, 2400);
    final service = FakeCurriculumService();
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => MissionService(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: COCDetailsScreen(
          projection: const LearnerCocProjection(
              id: 'coc-1',
              code: 'coc1',
              title: 'COC 1',
              description: '',
              order: 1,
              missions: []),
          loadCurriculum: service.getCurriculum,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(MissionContentData.practiceLockedMessage), findsNothing,
        reason: 'the curriculum unlocks COC 1 (no practice progress loaded)');
  });

  testWidgets('a lesson in a locked module can be read but not completed',
      (tester) async {
    final service = FakeCurriculumService();
    final topic = service.projection.cocs.first.modules.first.topics.first;
    await tester.pumpWidget(host(TopicReaderScreen(
        topic: topic,
        moduleUnlocked: false,
        lockReason: lo12Reason,
        service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Before you open the case'), findsOneWidget);
    expect(find.text(lo12Reason), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-topic-complete')), findsNothing);
  });

  testWidgets('a server refusal is explained without changing the lesson state',
      (tester) async {
    final service =
        FakeCurriculumService(failure: CurriculumFailure.moduleLocked);
    final topic = service.projection.cocs.first.modules.first.topics.first;
    await tester.pumpWidget(host(Scaffold(
        body: TopicReaderScreen(
            topic: topic, moduleUnlocked: true, service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-topic-complete')));
    await tester.pumpAndSettle();
    expect(find.text(LearningContentData.lessonModuleLocked), findsOneWidget);
    expect(find.text(LearningContentData.markComplete), findsOneWidget);
    expect(find.textContaining(RegExp('wrong|correct', caseSensitive: false)),
        findsNothing);
  });

  testWidgets(
      'Practice gates missions by module, checks access on the server and shows runs and best time',
      (tester) async {
    await setSurface(tester, 420, 3200);
    final service = FakeCurriculumService();
    final checked = <String>[];
    final launched = <String>[];
    await tester.pumpWidget(host(PracticeScreen(
      service: service,
      showSessionPanel: false,
      accessCheck: (code) async => checked.add(code),
      launch: (context, Mission mission) async => launched.add(mission.id),
    )));
    await tester.pumpAndSettle();
    expect(find.text(LearningContentData.missionVerified), findsOneWidget);
    expect(find.text(LearningContentData.missionRuns(3)), findsOneWidget);
    expect(find.text(LearningContentData.missionBest('4:40')), findsOneWidget);
    expect(find.text(lo12Reason), findsNWidgets(2),
        reason: 'each locked mission tile names its prerequisite');
    expect(
        find.bySemanticsLabel(RegExp(
            r'Mission 3, Install and Configure a Workstation OS, Locked, 0 runs')),
        findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('practice-mission-coc1_m3')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('practice-mission-coc1_m3')));
    await tester.pumpAndSettle();
    expect(checked, isEmpty, reason: 'a locked tile cannot start a mission');

    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('practice-mission-coc1_m2')), -200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('practice-mission-coc1_m2')));
    await tester.pumpAndSettle();
    expect(checked, ['coc1_m2']);
    expect(launched, ['coc1_m2']);
    expect(service.loads, greaterThanOrEqualTo(2),
        reason: 'progress refreshes after the mission closes');
  });

  testWidgets(
      'Practice explains a server-side lock instead of opening the mission',
      (tester) async {
    await setSurface(tester, 420, 3200);
    final launched = <String>[];
    await tester.pumpWidget(host(PracticeScreen(
      service: FakeCurriculumService(),
      showSessionPanel: false,
      accessCheck: (code) async => throw StateError('PRACTICE_COC_LOCKED'),
      launch: (context, Mission mission) async => launched.add(mission.id),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-mission-coc1_m2')));
    await tester.pumpAndSettle();
    expect(launched, isEmpty);
    expect(find.text(LearningContentData.missionAccessDenied), findsOneWidget);
  });

  for (final screen in ['learn', 'practice', 'module', 'progress']) {
    testWidgets('$screen screen fits 320 px with doubled text', (tester) async {
      await setSurface(tester, 320, 640);
      final service = FakeCurriculumService();
      final child = switch (screen) {
        'learn' => LearnScreen(service: service) as Widget,
        'practice' => PracticeScreen(service: service, showSessionPanel: false),
        'module' => ModuleDetailScreen(
            cocCode: 'coc1',
            moduleId: 'module-LO1.1',
            initial: service.projection,
            service: service),
        _ => ProgressScreen(sources: progressSources(service)),
      };
      await tester.pumpWidget(host(child, textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Progress combines the projection with released results, quiz scores and homework',
      (tester) async {
    await setSurface(tester, 420, 4000);
    final service = FakeCurriculumService();
    await tester
        .pumpWidget(host(ProgressScreen(sources: progressSources(service))));
    await tester.pumpAndSettle();
    expect(
        find.text(LearningContentData.modulesCompleted(0, 5)), findsOneWidget);
    expect(find.text(LearningContentData.topicsSummary(0, 1)), findsWidgets);
    expect(
        find.text(LearningContentData.missionsSummary(1, 6)), findsOneWidget);
    expect(find.text(LearningContentData.runsSummary(3)), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(LearningContentData.resultsEmpty), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.pendingCount(2)), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(LearningContentData.quizScore(4, 5)), 300,
        scrollable: find.byType(Scrollable).first);
    expect(
        find.text(LearningContentData.quizStatusCounts(1, 1)), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(LearningContentData.homeworkCounts(1, 0, 1)), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.homeworkScore('92')), findsOneWidget);
    expect(
        find.textContaining(RegExp(r'of 5 practice missions|Mission \d of 5')),
        findsNothing,
        reason: 'counts come from the projection, not a hard-coded "of 5"');
  });

  // Rest I2: Progress never invents a score for a quiz awaiting instructor
  // evaluation, and shows the released points the result screen shows.
  testWidgets('Progress quiz scores follow evaluation and release',
      (tester) async {
    await setSurface(tester, 420, 4000);
    final service = FakeCurriculumService();
    final base = progressSources(service);
    final now = DateTime.utc(2026, 11, 19).toIso8601String();
    LearnerQuizSummary quiz(String id, Map<String, dynamic> extra) =>
        LearnerQuizSummary.fromJson({
          'assignment_id': 'assignment-$id',
          'quiz_version_id': 'version-$id',
          'quiz_id': 'quiz-$id',
          'title': 'Essay quiz $id',
          'class_id': 'class',
          'class_title': 'CSS 11-A',
          'is_available': false,
          'attempt_status': 'completed',
          'attempt_id': 'attempt-$id',
          ...extra,
        });
    final fetched = <String>[];
    await tester.pumpWidget(host(ProgressScreen(
        sources: ProgressSources(
      curriculum: base.curriculum,
      releasedResults: base.releasedResults,
      attemptCounts: base.attemptCounts,
      homework: base.homework,
      quizzes: () async => [
        quiz('pending', {
          'status': 'awaiting_evaluation',
          'evaluation_status': 'pending',
        }),
        quiz('stale', const {}),
        quiz('released', {
          'status': 'released',
          'evaluation_status': 'released',
        }),
      ],
      quizResult: (attemptId) async {
        fetched.add(attemptId);
        return LearnerQuizResult.fromJson({
          'attempt_id': attemptId,
          'title': 'Essay quiz',
          'class_title': 'CSS 11-A',
          'completed_at': now,
          'question_count': 2,
          ...switch (attemptId) {
            'attempt-released' => {
                'result_status': 'released',
                'evaluation_status': 'released',
                'correct_count': 1,
                'total_points': 12,
                'max_points': 13,
              },
            // The list was stale: the server says the result is pending.
            _ => {
                'result_status': 'awaiting_evaluation',
                'evaluation_status': 'pending',
              },
          },
        });
      },
    ))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text(LearningContentData.quizPoints('12', '13')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.quizPoints('12', '13')),
        findsOneWidget, reason: 'released points, as on the result screen');
    expect(find.text(LearningContentData.quizAwaitingEvaluation),
        findsNWidgets(2));
    expect(find.textContaining(RegExp(r'\d+/\d+ correct')), findsNothing,
        reason: 'no made-up count for a pending or points-based quiz');
    expect(fetched, isNot(contains('attempt-pending')),
        reason: 'a quiz known to be awaiting evaluation is not fetched');
  });

  testWidgets(
      'Progress keeps working when one source fails and explains the methodology',
      (tester) async {
    await setSurface(tester, 420, 4000);
    final service = FakeCurriculumService();
    final sources = progressSources(service, homeworkFails: true);
    await tester.pumpWidget(host(ProgressScreen(
        sources: sources, performanceSection: const Text('A7 performance'))));
    await tester.pumpAndSettle();
    expect(
        find.text(LearningContentData.missionsSummary(1, 6)), findsOneWidget);
    expect(find.text('A7 performance'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text(LearningContentData.homeworkFailed), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(LearningContentData.homeworkFailed), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('methodology-button')), -300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('methodology-button')));
    await tester.pumpAndSettle();
    expect(find.text(LearningContentData.methodologyTitle), findsWidgets);
    expect(find.text('Module complete'), findsOneWidget);
  });

  testWidgets('Tasks, Classes, Files and Quizzes stay reachable from Home',
      (tester) async {
    final opened = <ClassWorkDestination>[];
    await setSurface(tester, 320, 640);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 640), textScaler: TextScaler.linear(2)),
        child: Scaffold(
            body: SingleChildScrollView(
                child: HomeClassWorkLinks(onOpen: opened.add))),
      ),
    ));
    for (final destination in ClassWorkDestination.values) {
      expect(
          find.bySemanticsLabel(
              LearningContentData.shortcutSemantics(destination.label)),
          findsOneWidget);
      await tester
          .tap(find.byKey(ValueKey('home-shortcut-${destination.name}')));
      await tester.pump();
      expect(
          tester
              .getSize(
                  find.byKey(ValueKey('home-shortcut-${destination.name}')))
              .height,
          greaterThanOrEqualTo(48));
    }
    expect(opened, ClassWorkDestination.values);
    expect(tester.takeException(), isNull);
    // Tasks, Classes and Files open the class work screen at their own tab.
    expect([for (final d in ClassWorkDestination.values) d.classWorkTab],
        [0, 1, 2, null]);
    expect(MissionsScreen.tabCount, 3);
  });
}

ProgressSources progressSources(FakeCurriculumService service,
    {bool homeworkFails = false}) {
  final now = DateTime.utc(2026, 11, 19);
  LearnerQuizSummary quiz(String id, String? status) =>
      LearnerQuizSummary.fromJson({
        'assignment_id': 'assignment-$id',
        'quiz_version_id': 'version-$id',
        'quiz_id': 'quiz-$id',
        'title': 'Hardware quiz $id',
        'class_id': 'class',
        'class_title': 'CSS 11-A',
        'is_available': true,
        'attempt_status': status,
        if (status != null) 'attempt_id': 'attempt-$id',
      });
  HomeworkAssignment homework(String id, {String? status, num? score}) =>
      HomeworkAssignment.fromJson(
        {
          'id': id,
          'class_id': 'class',
          'title': 'Homework $id',
          'instructions': 'Write a report.'
        },
        classTitle: 'CSS 11-A',
        serverNow: now,
        files: const [],
        submission: status == null
            ? null
            : HomeworkSubmission.fromJson({
                'id': 'submission-$id',
                'answer': 'Done',
                'status': status,
                'submitted_at': now.toIso8601String(),
                'lateness_seconds': 0,
                'score': score,
              }),
      );
  return ProgressSources(
    curriculum: service.getCurriculum,
    releasedResults: () async => const <ReleasedAssessmentResult>[],
    attemptCounts: () async => {'submitted': 1, 'evaluated': 1, 'released': 3},
    quizzes: () async => [quiz('done', 'completed'), quiz('open', null)],
    quizResult: (attemptId) async => LearnerQuizResult.fromJson({
      'attempt_id': attemptId,
      'title': 'Hardware quiz done',
      'class_title': 'CSS 11-A',
      'completed_at': now.toIso8601String(),
      'correct_count': 4,
      'question_count': 5,
    }),
    homework: () async {
      if (homeworkFails) throw StateError('HOMEWORK_REQUEST_FAILED');
      return [homework('one'), homework('two', status: 'graded', score: 92)];
    },
  );
}
