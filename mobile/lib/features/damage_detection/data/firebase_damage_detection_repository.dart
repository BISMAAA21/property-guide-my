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
import '../domain/damage_detection_failure.dart';
import '../domain/damage_detection_repository.dart';
import '../domain/damage_detection_result.dart';

class FirebaseDamageDetectionRepository implements DamageDetectionRepository {
  FirebaseDamageDetectionRepository({
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

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final http.Client _httpClient;
  final String apiBaseUrl;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('damageReports');

  @override
  Stream<List<DamageReport>> watchReports(String propertyId) {
    final uid = _authenticatedUser().uid;
    if (propertyId.trim().isEmpty) {
      return Stream.error(
        const DamageDetectionFailure(
          'invalid-property',
          'Choose a valid property to view damage reports.',
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
  Future<DamageReport> detectDamage({
    required String propertyId,
    required DamagePhotoSource source,
  }) async {
    final user = _authenticatedUser();
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const DamageDetectionFailure(
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
      if (!propertySnapshot.exists || property?['propertyName'] is! String) {
        throw const DamageDetectionFailure(
          'property-not-found',
          'The property linked to this photo is no longer available.',
        );
      }
      if (source is UploadedDamagePhoto &&
          property?['approvalStatus'] != PropertyApprovalStatus.approved.name) {
        throw const DamageDetectionFailure(
          'property-not-available',
          'Upload damage photos only for an approved property.',
        );
      }

      final prepared = await _preparePhoto(
        source: source,
        propertyId: propertyId,
        uid: user.uid,
      );
      final result = await _requestDetection(
        token: token,
        bytes: prepared.bytes,
        filename: prepared.filename,
        contentType: prepared.contentType,
      );
      final reportReference = _reports.doc();
      Reference? uploadedReference;
      var imagePath = prepared.existingPath;
      if (source is UploadedDamagePhoto) {
        final safeFilename = _safeFilename(
          source.filename,
          prepared.contentType,
        );
        imagePath =
            'students/${user.uid}/damage/${reportReference.id}/$safeFilename';
        uploadedReference = _storage.ref(imagePath);
      }
      if (imagePath == null) {
        throw const DamageDetectionFailure(
          'invalid-damage-source',
          'The damage photo source is incomplete.',
        );
      }

      var uploaded = false;
      try {
        if (uploadedReference != null) {
          await uploadedReference.putData(
            prepared.bytes,
            SettableMetadata(
              contentType: prepared.contentType,
              customMetadata: {
                'ownerId': user.uid,
                'propertyId': propertyId,
                'reportId': reportReference.id,
              },
            ),
          );
          uploaded = true;
        }
        final box = result.boundingBox;
        await reportReference.set({
          'studentId': user.uid,
          'propertyId': propertyId,
          'imagePath': imagePath,
          'sourceType': source is InspectionDamagePhoto
              ? DamagePhotoSourceType.inspection.name
              : DamagePhotoSourceType.upload.name,
          'inspectionId': source is InspectionDamagePhoto
              ? source.inspectionId
              : null,
          'checkId': source is InspectionDamagePhoto ? source.checkId : null,
          'damageClass': result.damageClass.storedValue,
          'modelScore': result.modelScore,
          'boundingBox': box?.toJson(),
          'recommendation': result.recommendation,
          'disclaimer': result.disclaimer,
          'modelId': result.modelId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (uploaded && uploadedReference != null) {
          try {
            await uploadedReference.delete();
          } on FirebaseException {
            throw const DamageDetectionFailure(
              'report-cleanup-failed',
              'The report could not be saved and its private photo could not be removed.',
            );
          }
        }
        rethrow;
      }

      return DamageReport(
        id: reportReference.id,
        studentId: user.uid,
        propertyId: propertyId,
        imagePath: imagePath,
        sourceType: source is InspectionDamagePhoto
            ? DamagePhotoSourceType.inspection
            : DamagePhotoSourceType.upload,
        inspectionId: source is InspectionDamagePhoto
            ? source.inspectionId
            : null,
        checkId: source is InspectionDamagePhoto ? source.checkId : null,
        result: result,
        createdAt: DateTime.now().toUtc(),
      );
    } on DamageDetectionFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } on TimeoutException {
      throw const DamageDetectionFailure(
        'damage-timeout',
        'Damage detection took too long. Check the API connection and retry.',
      );
    } on SocketException {
      throw const DamageDetectionFailure(
        'damage-api-unreachable',
        'The damage-detection API could not be reached.',
      );
    } on http.ClientException {
      throw const DamageDetectionFailure(
        'damage-api-unreachable',
        'The damage-detection API could not be reached.',
      );
    }
  }

  Future<_PreparedPhoto> _preparePhoto({
    required DamagePhotoSource source,
    required String propertyId,
    required String uid,
  }) async {
    switch (source) {
      case UploadedDamagePhoto():
        final normalizedType = normalizeImageContentType(source.contentType);
        _validateImage(source.bytes, normalizedType);
        return _PreparedPhoto(
          bytes: source.bytes,
          filename: source.filename,
          contentType: normalizedType,
        );
      case InspectionDamagePhoto():
        if (source.inspectionId.trim().isEmpty ||
            source.checkId.trim().isEmpty ||
            source.imagePath != source.imagePath.trim() ||
            !source.imagePath.startsWith(
              'students/$uid/inspections/${source.inspectionId}/',
            )) {
          throw const DamageDetectionFailure(
            'invalid-inspection-photo',
            'The Guided Inspection photo context is invalid.',
          );
        }
        final inspection = await _firestore
            .collection('inspections')
            .doc(source.inspectionId)
            .get();
        final data = inspection.data();
        final results = data?['results'];
        final finding = results is Map ? results[source.checkId] : null;
        if (!inspection.exists ||
            data?['studentId'] != uid ||
            data?['propertyId'] != propertyId ||
            data?['status'] != 'completed' ||
            finding is! Map ||
            finding['concernImagePath'] != source.imagePath) {
          throw const DamageDetectionFailure(
            'invalid-inspection-photo',
            'The concern photo is not linked to this completed inspection.',
          );
        }
        final reference = _storage.ref(source.imagePath);
        final metadata = await reference.getMetadata();
        final bytes = await reference.getData(DamageImageInput.maxBytes + 1);
        final contentType = metadata.contentType
            ?.toLowerCase()
            .split(';')
            .first
            .trim();
        if (bytes == null || contentType == null) {
          throw const DamageDetectionFailure(
            'inspection-photo-unavailable',
            'The Guided Inspection concern photo could not be loaded.',
          );
        }
        _validateImage(bytes, contentType);
        return _PreparedPhoto(
          bytes: bytes,
          filename: reference.name,
          contentType: contentType,
          existingPath: source.imagePath,
        );
    }
  }

  Future<DamageDetectionResult> _requestDetection({
    required String token,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final baseUri = AppConfig.validatedAiApiUri(apiBaseUrl);
    if (baseUri == null) {
      throw const DamageDetectionFailure(
        'api-not-configured',
        'Configure a valid damage-detection API URL.',
      );
    }
    final request = http.MultipartRequest(
      'POST',
      baseUri.resolve('/detect-damage'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: _safeFilename(filename, contentType),
        contentType: http_parser.MediaType.parse(contentType),
      ),
    );
    final streamed = await _httpClient.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DamageDetectionFailure(
        body?['code'] is String ? body!['code'] as String : 'api-error',
        body?['message'] is String
            ? body!['message'] as String
            : 'The damage-detection service rejected the request.',
      );
    }
    if (body == null) {
      throw const DamageDetectionFailure(
        'invalid-api-response',
        'The damage-detection service returned an invalid response.',
      );
    }
    try {
      return DamageDetectionResult.fromJson(body);
    } on FormatException {
      throw const DamageDetectionFailure(
        'invalid-api-response',
        'The damage-detection service returned an invalid response.',
      );
    }
  }

  User _authenticatedUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const DamageDetectionFailure(
        'auth-required',
        'Sign in as a student before using damage detection.',
      );
    }
    return user;
  }

  static void _validateImage(Uint8List bytes, String contentType) {
    final validationError = DamageImageInput(
      byteLength: bytes.length,
      contentType: contentType,
    ).validate();
    if (validationError != null ||
        !imageContentMatchesType(bytes, contentType)) {
      throw DamageDetectionFailure(
        'invalid-damage-image',
        validationError ??
            'The photo content does not match its JPEG, PNG, or WebP type.',
      );
    }
  }

  static DamageReport _reportFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final sourceType = DamagePhotoSourceType.values
        .where((item) => item.name == data['sourceType'])
        .firstOrNull;
    if (sourceType == null) {
      throw const DamageDetectionFailure(
        'invalid-report-data',
        'A damage report has an invalid photo source.',
      );
    }
    final result = DamageDetectionResult.fromJson({
      'damageClass': data['damageClass'],
      'modelScore': data['modelScore'],
      'boundingBox': data['boundingBox'],
      'recommendation': data['recommendation'],
      'disclaimer': data['disclaimer'],
      'modelId': data['modelId'],
    });
    final inspectionId = data['inspectionId'];
    final checkId = data['checkId'];
    if ((inspectionId != null && inspectionId is! String) ||
        (checkId != null && checkId is! String) ||
        (sourceType == DamagePhotoSourceType.inspection &&
            (inspectionId is! String || checkId is! String)) ||
        (sourceType == DamagePhotoSourceType.upload &&
            (inspectionId != null || checkId != null))) {
      throw const DamageDetectionFailure(
        'invalid-report-data',
        'A damage report has invalid inspection context.',
      );
    }
    try {
      return DamageReport(
        id: document.id,
        studentId: _requiredString(data, 'studentId'),
        propertyId: _requiredString(data, 'propertyId'),
        imagePath: _requiredString(data, 'imagePath'),
        sourceType: sourceType,
        inspectionId: inspectionId as String?,
        checkId: checkId as String?,
        result: result,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );
    } on TypeError {
      throw const DamageDetectionFailure(
        'invalid-report-data',
        'A damage report contains invalid data and cannot be displayed.',
      );
    }
  }

  static String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw DamageDetectionFailure(
        'invalid-report-data',
        'A damage report is missing $field.',
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
        ? 'damage.${_extensionFor(contentType)}'
        : sanitized;
  }

  static String _extensionFor(String contentType) => switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'img',
  };

  static DamageDetectionFailure _mapFirebaseError(FirebaseException error) {
    final message = switch (error.code) {
      'permission-denied' =>
        'You are not allowed to save or view this damage report.',
      'unauthenticated' => 'Sign in before using damage detection.',
      'unavailable' => 'Firebase is temporarily unavailable. Try again later.',
      'object-not-found' => 'A required damage photo is unavailable.',
      _ => 'The damage report operation failed. Please try again.',
    };
    return DamageDetectionFailure(error.code, message);
  }
}

class _PreparedPhoto {
  const _PreparedPhoto({
    required this.bytes,
    required this.filename,
    required this.contentType,
    this.existingPath,
  });

  final Uint8List bytes;
  final String filename;
  final String contentType;
  final String? existingPath;
}
