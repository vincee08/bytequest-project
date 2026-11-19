import 'dart:async';

import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/data/account_content_data.dart';
import 'package:bytequest/models/profile_model.dart';
import 'package:bytequest/screens/profile_setup/profile_setup_screen.dart';
import 'package:bytequest/screens/profile_setup/student_id_policy.dart';
import 'package:bytequest/screens/settings/edit_profile_screen.dart';
import 'package:bytequest/services/auth_service.dart';
import 'package:bytequest/services/profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth implements AuthService {
  @override
  String get currentUserId => 'managed-test-user';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Profiles implements ProfileService {
  _Profiles({this.learnerId, this.failWith});
  final String? learnerId;
  final Object? failWith;
  final writes = <Map<String, dynamic>>[];

  @override
  Future<ProfileModel?> getProfileByUserId(String userId) async => ProfileModel(
      id: 'profile',
      userId: userId,
      fullName: 'Maria Santos',
      email: 'maria@school.edu.ph',
      learnerId: learnerId,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));

  @override
  Future<void> updateProfile(String userId, Map<String, dynamic> updates) async {
    writes.add(Map.of(updates));
    if (failWith != null) throw failWith!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpEditProfile(WidgetTester tester, _Profiles profiles,
    StudentIdPolicy? policy) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<AuthService>.value(value: _Auth()),
      Provider<ProfileService>.value(value: profiles),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: EditProfileScreen(loadStudentIdPolicy: () async => policy),
    ),
  ));
  await tester.pumpAndSettle();
}

TextField _studentIdField(WidgetTester tester, Key key) => tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)));

Future<void> _save(WidgetTester tester) async {
  final save = find.text('Save Changes');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('a staff-managed student ID is read-only and never resent',
      (tester) async {
    final profiles = _Profiles(learnerId: '2026-0001');
    await _pumpEditProfile(tester, profiles,
        const StudentIdPolicy(learnerId: '2026-0001', managed: true));

    const key = Key('editProfileStudentIdField');
    expect(_studentIdField(tester, key).readOnly, isTrue);
    expect(_studentIdField(tester, key).controller!.text, '2026-0001');
    expect(find.text(AccountContentData.studentIdManagedHelper), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            AccountContentData.studentIdManagedSemantics('2026-0001')),
        findsOneWidget);

    await _save(tester);
    expect(profiles.writes, hasLength(1));
    expect(profiles.writes.single.containsKey('learner_id'), isFalse);
    expect(profiles.writes.single['full_name'], 'Maria Santos');
  });

  testWidgets('a self-managed student ID stays editable and is saved',
      (tester) async {
    final profiles = _Profiles();
    await _pumpEditProfile(tester, profiles,
        const StudentIdPolicy(learnerId: null, managed: false));

    const key = Key('editProfileStudentIdField');
    expect(_studentIdField(tester, key).readOnly, isFalse);
    expect(find.text(AccountContentData.studentIdManagedHelper), findsNothing);
    await tester.enterText(find.byKey(key), ' 2026-0042 ');
    await _save(tester);
    expect(profiles.writes.single['learner_id'], '2026-0042');
  });

  testWidgets(
      'a server refusal for a managed ID explains it and locks the field',
      (tester) async {
    final profiles = _Profiles(
        learnerId: '2026-0001',
        failWith: const PostgrestException(
            message: 'STUDENT_ID_STAFF_MANAGED', code: '42501'));
    await _pumpEditProfile(tester, profiles,
        const StudentIdPolicy(learnerId: '2026-0001', managed: false));

    const key = Key('editProfileStudentIdField');
    await tester.enterText(find.byKey(key), '2026-9999');
    await _save(tester);
    expect(find.text(AccountContentData.studentIdManagedSaveError), findsOneWidget);
    expect(_studentIdField(tester, key).readOnly, isTrue);
    expect(_studentIdField(tester, key).controller!.text, '2026-0001');
    expect(find.byType(Form), findsOneWidget);
  });

  testWidgets('a student ID used by another learner gets a specific message',
      (tester) async {
    final profiles = _Profiles(
        failWith: const PostgrestException(
            message: 'duplicate key value violates unique constraint',
            code: '23505'));
    await _pumpEditProfile(tester, profiles,
        const StudentIdPolicy(learnerId: null, managed: false));
    await tester.enterText(
        find.byKey(const Key('editProfileStudentIdField')), '2026-0001');
    await _save(tester);
    expect(find.text(AccountContentData.studentIdTakenSaveError), findsOneWidget);
  });

  testWidgets('profile setup shows a managed student ID read-only',
      (tester) async {
    final setupProfiles = _Profiles(learnerId: '2026-0200');
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AuthService>.value(value: _Auth()),
        Provider<ProfileService>.value(value: setupProfiles),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProfileSetupScreen(
          loadStudentIdPolicy: () async =>
              const StudentIdPolicy(learnerId: '2026-0200', managed: true),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const key = Key('profileSetupStudentIdField');
    expect(_studentIdField(tester, key).readOnly, isTrue);
    expect(_studentIdField(tester, key).controller!.text, '2026-0200');
    expect(find.text(AccountContentData.studentIdManagedHelper), findsOneWidget);
  });

  testWidgets('profile setup keeps the student ID editable when not managed',
      (tester) async {
    final pending = Completer<StudentIdPolicy?>();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: ProfileSetupScreen(loadStudentIdPolicy: () => pending.future),
    ));
    pending.complete(null);
    await tester.pumpAndSettle();
    const key = Key('profileSetupStudentIdField');
    expect(_studentIdField(tester, key).readOnly, isFalse);
    await tester.enterText(find.byKey(key), 'S-77');
    expect(_studentIdField(tester, key).controller!.text, 'S-77');
  });
}
