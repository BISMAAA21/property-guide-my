import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:property_guidance/features/auth/domain/user_role.dart';
import 'package:property_guidance/features/reviews/application/review_providers.dart';
import 'package:property_guidance/features/reviews/domain/property_review.dart';
import 'package:property_guidance/features/reviews/domain/review_repository.dart';
import 'package:property_guidance/features/reviews/presentation/property_reviews_panel.dart';

void main() {
  testWidgets('student writes a star and text review', (tester) async {
    final repository = _FakeReviewRepository(const []);
    await _pump(
      tester,
      repository: repository,
      role: UserRole.student,
      currentUserId: 'student-one',
    );

    await tester.tap(find.byKey(const Key('write_review_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review_star_4')));
    await tester.enterText(
      find.byKey(const Key('review_comment_field')),
      'The property was clean and matched the approved photographs.',
    );
    await tester.tap(find.byKey(const Key('save_review_button')));
    await tester.pumpAndSettle();

    expect(repository.savedPropertyId, 'property-one');
    expect(repository.savedInput?.rating, 4);
    expect(
      repository.savedInput?.comment,
      'The property was clean and matched the approved photographs.',
    );
  });

  testWidgets('administrator confirms removal of an inappropriate review', (
    tester,
  ) async {
    final review = PropertyReview(
      id: 'property-one_student-one',
      propertyId: 'property-one',
      studentId: 'student-one',
      studentName: 'Student One',
      rating: 2,
      comment: 'A review selected for moderation.',
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 2),
    );
    final repository = _FakeReviewRepository([review]);
    await _pump(
      tester,
      repository: repository,
      role: UserRole.admin,
      currentUserId: 'admin-one',
    );

    await tester.tap(find.byTooltip('Remove review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove review'));
    await tester.pumpAndSettle();

    expect(repository.removedReview, same(review));
  });

  testWidgets(
    'agent reads student reviews without write or moderation controls',
    (tester) async {
      final review = PropertyReview(
        id: 'property-one_student-one',
        propertyId: 'property-one',
        studentId: 'student-one',
        studentName: 'Student One',
        rating: 5,
        comment: 'Clear review visible to the property agent.',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 2),
      );
      final repository = _FakeReviewRepository([review]);

      await _pump(
        tester,
        repository: repository,
        role: UserRole.agent,
        currentUserId: 'agent-one',
      );

      expect(find.text('Student reviews (1)'), findsOneWidget);
      expect(
        find.text('Clear review visible to the property agent.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('write_review_button')), findsNothing);
      expect(find.byTooltip('Remove review'), findsNothing);
    },
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeReviewRepository repository,
  required UserRole role,
  required String currentUserId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reviewRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PropertyReviewsPanel(
              propertyId: 'property-one',
              role: role,
              currentUserId: currentUserId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

class _FakeReviewRepository implements ReviewRepository {
  _FakeReviewRepository(this.reviews);

  final List<PropertyReview> reviews;
  String? savedPropertyId;
  ReviewWriteInput? savedInput;
  PropertyReview? removedReview;

  @override
  Stream<List<PropertyReview>> watchPropertyReviews(String propertyId) =>
      Stream.value(reviews);

  @override
  Future<void> saveReview({
    required String propertyId,
    required ReviewWriteInput input,
  }) async {
    savedPropertyId = propertyId;
    savedInput = input;
  }

  @override
  Future<void> removeReview(PropertyReview review) async {
    removedReview = review;
  }
}
