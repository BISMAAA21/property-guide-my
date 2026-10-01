import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:property_guidance/features/image_verification/application/image_verification_providers.dart';
import 'package:property_guidance/features/image_verification/data/unavailable_image_verification_repository.dart';
import 'package:property_guidance/features/image_verification/domain/image_verification_result.dart';
import 'package:property_guidance/features/image_verification/presentation/image_verification_screen.dart';
import 'package:property_guidance/features/properties/application/property_providers.dart';
import 'package:property_guidance/features/properties/data/unavailable_property_repository.dart';
import 'package:property_guidance/features/properties/domain/property_listing.dart';

void main() {
  testWidgets('student uploads a visit photo and sees cautious low result', (
    tester,
  ) async {
    final verificationRepository = _VerificationFake();
    final visitBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyRepositoryProvider.overrideWithValue(
            const _PropertyFake(_approvedProperty),
          ),
          imageVerificationRepositoryProvider.overrideWithValue(
            verificationRepository,
          ),
        ],
        child: MaterialApp(
          home: ImageVerificationScreen(
            propertyId: 'property-one',
            pickVisitImage: () async => XFile.fromData(
              visitBytes,
              name: 'visit.jpg',
              mimeType: 'image/jpeg',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byKey(const Key('choose_visit_image_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const Key('visit_image_preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('run_image_verification_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.scrollUntilVisible(
      find.byKey(const Key('image_verification_result_card')),
      400,
      scrollable: find.byType(Scrollable).first,
    );

    expect(verificationRepository.verifyCalls, 1);
    expect(verificationRepository.lastContentType, 'image/png');
    expect(find.text('38.0 / 100'), findsOneWidget);
    expect(find.text('Low similarity'), findsOneWidget);
    expect(find.byKey(const Key('possible_mismatch_warning')), findsOneWidget);
    expect(find.byKey(const Key('verification_guidance')), findsOneWidget);
    expect(find.byKey(const Key('verification_disclaimer')), findsOneWidget);
    expect(find.textContaining('definitely fake'), findsNothing);
    expect(find.textContaining('definitely genuine'), findsNothing);
  });

  testWidgets('property without listing images cannot start comparison', (
    tester,
  ) async {
    final property = _copyPropertyWithImages(const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          propertyRepositoryProvider.overrideWithValue(_PropertyFake(property)),
          imageVerificationRepositoryProvider.overrideWithValue(
            _VerificationFake(),
          ),
        ],
        child: const MaterialApp(
          home: ImageVerificationScreen(propertyId: 'property-one'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.textContaining('no listing images available'), findsOneWidget);
    expect(
      find.byKey(const Key('run_image_verification_button')),
      findsNothing,
    );
  });
}

const _approvedProperty = PropertyListing(
  id: 'property-one',
  agentId: 'agent-one',
  propertyName: 'Cyberjaya Visit Suite',
  location: 'Cyberjaya, Selangor',
  normalizedLocation: 'cyberjaya, selangor',
  monthlyRent: 1400,
  bedrooms: 2,
  bathrooms: 1,
  propertyType: PropertyType.apartment,
  description: 'An approved property used for image verification testing.',
  facilities: ['Wi-Fi'],
  imageUrls: ['https://example.test/listing.jpg'],
  approvalStatus: PropertyApprovalStatus.approved,
  ratingAverage: 4,
  ratingCount: 2,
  createdAt: null,
  updatedAt: null,
);

PropertyListing _copyPropertyWithImages(List<String> images) => PropertyListing(
  id: _approvedProperty.id,
  agentId: _approvedProperty.agentId,
  propertyName: _approvedProperty.propertyName,
  location: _approvedProperty.location,
  normalizedLocation: _approvedProperty.normalizedLocation,
  monthlyRent: _approvedProperty.monthlyRent,
  bedrooms: _approvedProperty.bedrooms,
  bathrooms: _approvedProperty.bathrooms,
  propertyType: _approvedProperty.propertyType,
  description: _approvedProperty.description,
  facilities: _approvedProperty.facilities,
  imageUrls: images,
  approvalStatus: _approvedProperty.approvalStatus,
  ratingAverage: _approvedProperty.ratingAverage,
  ratingCount: _approvedProperty.ratingCount,
  createdAt: _approvedProperty.createdAt,
  updatedAt: _approvedProperty.updatedAt,
);

class _PropertyFake extends UnavailablePropertyRepository {
  const _PropertyFake(this.property);

  final PropertyListing property;

  @override
  Stream<PropertyListing?> watchListing(String propertyId) =>
      Stream.value(property);
}

class _VerificationFake extends UnavailableImageVerificationRepository {
  _VerificationFake();

  int verifyCalls = 0;
  String? lastContentType;

  @override
  Stream<List<VerificationReport>> watchReports(String propertyId) =>
      Stream.value(const []);

  @override
  Future<VerificationReport> verifyVisitImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    verifyCalls += 1;
    lastContentType = contentType;
    return VerificationReport(
      id: 'report-one',
      studentId: 'student-one',
      propertyId: propertyId,
      propertyName: _approvedProperty.propertyName,
      visitImagePath: 'students/student-one/verifications/report-one/visit.png',
      bestListingImageUrl: _approvedProperty.imageUrls.first,
      result: const ImageVerificationResult(
        similarityScore: 38,
        similarityLevel: SimilarityLevel.low,
        possibleMismatch: true,
        mismatchWarning:
            'Possible mismatch: the visit image differs from the listing.',
        bestListingImageIndex: 0,
        guidance: 'Pause and verify the address and exact unit with the agent.',
        disclaimer: 'AI-assisted guidance only; this does not guarantee that the property or listing is genuine.',
        modelId: 'controlled-model',
      ),
      createdAt: DateTime.utc(2026, 8, 17),
    );
  }
}
