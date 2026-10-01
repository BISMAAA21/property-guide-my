import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;

import '../../../shared/config/app_config.dart';
import '../../../shared/validation/image_content.dart';
import '../../properties/domain/property_listing.dart';
import '../domain/image_verification_failure.dart';
import '../domain/image_verification_repository.dart';
import '../domain/image_verification_result.dart';

class FirebaseImageVerificationRepository
    implements ImageVerificationRepository {
  FirebaseImageVerificationRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    http.Client? httpClient,
    this.apiBaseUrl = AppConfig.aiApiBaseUrl,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _httpClient = httpClient ?? http.Client();

  static const _requestTimeout = Duration(seconds: 45);
  static const _maximumListingImages = 8;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final http.Client _httpClient;
  final String apiBaseUrl;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('verificationReports');

  @override
  Stream<List<VerificationReport>> watchReports(String propertyId) {
    final uid = _authenticatedUser().uid;
    if (propertyId.trim().isEmpty) {
      return Stream.error(
        const ImageVerificationFailure(
          'invalid-property',
          'Choose a valid property to view verification reports.',
        ),
      );
    }
    return _reports.where('studentId', isEqualTo: uid).snapshots().map((
      snapshot,
    ) {
      final reports =
          snapshot.docs
              .map(_reportFromDocument)
              .where((report) => report.propertyId == propertyId)
              .toList(growable: false)
            ..sort((left, right) {
              final leftDate = left.createdAt ?? DateTime(1970);
              final rightDate = right.createdAt ?? DateTime(1970);
              return rightDate.compareTo(leftDate);
            });
      return List.unmodifiable(reports);
    });
  }

  @override
  Future<VerificationReport> verifyVisitImage({
    required String propertyId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final normalizedType = normalizeImageContentType(contentType);
    final validationError = VerificationImageInput(
      byteLength: bytes.length,
      contentType: normalizedType,
    ).validate();
    if (validationError != null ||
        !imageContentMatchesType(bytes, normalizedType)) {
      throw ImageVerificationFailure(
        'invalid-visit-image',
        validationError ?? 'The visit photo content does not match its JPEG, PNG, or WebP type.',
      );
    }

    final user = _authenticatedUser();
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ImageVerificationFailure(
        'auth-token-unavailable',
        'Your sign-in token could not be obtained. Sign in again and retry.',
      );
    }

    try {
      final propertySnapshot = await _firestore
          .collection('properties')
          .doc(propertyId)
          .get();
      final property = propertySnapshot.data();
      final propertyName = property?['propertyName'];
      final approvalStatus = property?['approvalStatus'];
      final rawUrls = property?['imageUrls'];
      if (!propertySnapshot.exists ||
          propertyName is! String ||
          propertyName.trim().isEmpty ||
          approvalStatus != PropertyApprovalStatus.approved.name ||
          rawUrls is! List) {
        throw const ImageVerificationFailure(
          'property-not-verifiable',
          'Only an approved property with listing images can be verified.',
        );
      }
      final listingUrls = rawUrls.whereType<String>().toList(growable: false);
      if (listingUrls.isEmpty ||
          listingUrls.length != rawUrls.length ||
          listingUrls.length > _maximumListingImages) {
        throw const ImageVerificationFailure(
          'listing-images-unavailable',
          'This property does not have a valid set of listing images to compare.',
        );
      }

      final listingImages = await Future.wait(
        listingUrls.indexed.map(
          (entry) => _downloadListingImage(entry.$2, entry.$1),
        ),
      );
      final result = await _requestVerification(
        token: token,
        visitBytes: bytes,
        visitFilename: filename,
        visitContentType: normalizedType,
        listingImages: listingImages,
      );

      final reportReference = _reports.doc();
      final safeFilename = _safeFilename(filename, normalizedType);
      final visitPath =
          'students/${user.uid}/verifications/${reportReference.id}/$safeFilename';
      final visitReference = _storage.ref(visitPath);
      var uploaded = false;
      try {
        await visitReference.putData(
          bytes,
          SettableMetadata(
            contentType: normalizedType,
            customMetadata: {
              'ownerId': user.uid,
              'propertyId': propertyId,
              'reportId': reportReference.id,
            },
          ),
        );
        uploaded = true;
        await reportReference.set({
          'studentId': user.uid,
          'propertyId': propertyId,
          'propertyName': propertyName.trim(),
          'visitImagePath': visitPath,
          'bestListingImageUrl': listingUrls[result.bestListingImageIndex],
          'bestListingImageIndex': result.bestListingImageIndex,
          'similarityScore': result.similarityScore,
          'similarityLevel': result.similarityLevel.name,
          'possibleMismatch': result.possibleMismatch,
          'mismatchWarning': result.mismatchWarning,
          'guidance': result.guidance,
          'disclaimer': result.disclaimer,
          'modelId': result.modelId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (uploaded) {
          try {
            await visitReference.delete();
          } on FirebaseException {
            throw const ImageVerificationFailure(
              'report-cleanup-failed',
              'The report could not be saved and its private visit photo could not be removed.',
            );
          }
        }
        rethrow;
      }

      return VerificationReport(
        id: reportReference.id,
        studentId: user.uid,
        propertyId: propertyId,
        propertyName: propertyName.trim(),
        visitImagePath: visitPath,
        bestListingImageUrl: listingUrls[result.bestListingImageIndex],
        result: result,
        createdAt: DateTime.now().toUtc(),
      );
    } on ImageVerificationFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } on TimeoutException {
      throw const ImageVerificationFailure(
        'verification-timeout',
        'Image verification took too long. Check the API connection and retry.',
      );
    } on SocketException {
      throw const ImageVerificationFailure(
        'verification-unreachable',
        'The image-verification API could not be reached.',
      );
    } on http.ClientException {
      throw const ImageVerificationFailure(
        'verification-unreachable',
        'The image-verification API could not be reached.',
      );
    }
  }

  Future<_DownloadedImage> _downloadListingImage(String url, int index) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw const ImageVerificationFailure(
        'invalid-listing-image',
        'A listing image reference is invalid.',
      );
    }
    final response = await _httpClient.get(uri).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageVerificationFailure(
        'listing-image-unavailable',
        'Listing image ${index + 1} could not be downloaded for comparison.',
      );
    }
    final detectedType = detectSupportedImageContentType(response.bodyBytes);
    final inputError = VerificationImageInput(
      byteLength: response.bodyBytes.length,
      contentType: detectedType ?? '',
    ).validate();
    if (detectedType == null || inputError != null) {
      throw ImageVerificationFailure(
        'invalid-listing-image',
        'Listing image ${index + 1} is not a valid JPEG, PNG, or WebP image.',
      );
    }
    return _DownloadedImage(
      bytes: response.bodyBytes,
      filename: 'listing-${index + 1}.${_extensionFor(detectedType)}',
      contentType: detectedType,
    );
  }

  Future<ImageVerificationResult> _requestVerification({
    required String token,
    required Uint8List visitBytes,
    required String visitFilename,
    required String visitContentType,
    required List<_DownloadedImage> listingImages,
  }) async {
    final baseUri = AppConfig.validatedAiApiUri(apiBaseUrl);
    if (baseUri == null) {
      throw const ImageVerificationFailure(
        'api-not-configured',
        'Configure a valid image-verification API URL.',
      );
    }
    final request = http.MultipartRequest(
      'POST',
      baseUri.resolve('/verify-image'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'visit_image',
        visitBytes,
        filename: _safeFilename(visitFilename, visitContentType),
        contentType: http_parser.MediaType.parse(visitContentType),
      ),
    );
    for (final image in listingImages) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'listing_images',
          image.bytes,
          filename: image.filename,
          contentType: http_parser.MediaType.parse(image.contentType),
        ),
      );
    }
    final streamed = await _httpClient.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    } on FormatException {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ImageVerificationFailure(
        body?['code'] is String ? body!['code'] as String : 'api-error',
        body?['message'] is String
            ? body!['message'] as String
            : 'The image-verification service rejected the request.',
      );
    }
    if (body == null) {
      throw const ImageVerificationFailure(
        'invalid-api-response',
        'The image-verification service returned an invalid response.',
      );
    }
    try {
      return ImageVerificationResult.fromJson(
        body,
        listingImageCount: listingImages.length,
      );
    } on FormatException {
      throw const ImageVerificationFailure(
        'invalid-api-response',
        'The image-verification service returned an invalid response.',
      );
    }
  }

  User _authenticatedUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const ImageVerificationFailure(
        'auth-required',
        'Sign in as a student before verifying a property image.',
      );
    }
    return user;
  }

  static VerificationReport _reportFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final index = data['bestListingImageIndex'];
    final result = ImageVerificationResult.fromJson({
      'similarityScore': data['similarityScore'],
      'similarityLevel': data['similarityLevel'],
      'possibleMismatch': data['possibleMismatch'],
      'mismatchWarning': data['mismatchWarning'],
      'bestListingImageIndex': index,
      'guidance': data['guidance'],
      'disclaimer': data['disclaimer'],
      'modelId': data['modelId'],
    }, listingImageCount: index is int ? index + 1 : 0);
    try {
      return VerificationReport(
        id: document.id,
        studentId: _requiredString(data, 'studentId'),
        propertyId: _requiredString(data, 'propertyId'),
        propertyName: _requiredString(data, 'propertyName'),
        visitImagePath: _requiredString(data, 'visitImagePath'),
        bestListingImageUrl: _requiredString(data, 'bestListingImageUrl'),
        result: result,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );
    } on TypeError {
      throw const ImageVerificationFailure(
        'invalid-report-data',
        'A verification report contains invalid data and cannot be displayed.',
      );
    }
  }

  static String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw ImageVerificationFailure(
        'invalid-report-data',
        'A verification report is missing $field.',
      );
    }
    return value.trim();
  }

  static String _safeFilename(String filename, String contentType) {
    final sanitized = filename.trim().replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    return sanitized.isEmpty
        ? 'visit.${_extensionFor(contentType)}'
        : sanitized;
  }

  static String _extensionFor(String contentType) => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'img',
  };

  static ImageVerificationFailure _mapFirebaseError(FirebaseException error) {
    final message = switch (error.code) {
      'permission-denied' =>
        'You are not allowed to save or view this verification report.',
      'unauthenticated' => 'Sign in before verifying a property image.',
      'unavailable' => 'Firebase is temporarily unavailable. Try again later.',
      'object-not-found' => 'A required verification image is unavailable.',
      _ => 'The verification report operation failed. Please try again.',
    };
    return ImageVerificationFailure(error.code, message);
  }
}

class _DownloadedImage {
  const _DownloadedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
}
