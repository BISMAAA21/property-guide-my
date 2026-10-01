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
import '../domain/agreement_failure.dart';
import '../domain/agreement_repository.dart';
import '../domain/agreement_result.dart';

class FirebaseAgreementRepository implements AgreementRepository {
  FirebaseAgreementRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    http.Client? httpClient,
    this.apiBaseUrl = AppConfig.aiApiBaseUrl,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _httpClient = httpClient ?? http.Client();

  static const _requestTimeout = Duration(minutes: 7);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final http.Client _httpClient;
  final String apiBaseUrl;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('agreements');

  @override
  Stream<List<AgreementReport>> watchReports() {
    final uid = _authenticatedUser().uid;
    return _reports.where('studentId', isEqualTo: uid).snapshots().map((
      snapshot,
    ) {
      final reports =
          snapshot.docs.map(_reportFromDocument).toList(growable: false)
            ..sort((left, right) {
              final leftDate = left.createdAt ?? DateTime(1970);
              final rightDate = right.createdAt ?? DateTime(1970);
              return rightDate.compareTo(leftDate);
            });
      return List.unmodifiable(reports);
    });
  }

  @override
  Future<AgreementReport> simplifyAndSave({
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final normalizedType = contentType.toLowerCase().split(';').first.trim();
    final inputError = AgreementPdfInput(
      byteLength: bytes.length,
      contentType: normalizedType,
    ).validate();
    if (inputError != null || !_hasPdfSignature(bytes)) {
      throw AgreementFailure(
        'invalid-agreement',
        inputError ?? 'The selected document content is not a valid PDF.',
      );
    }

    final user = _authenticatedUser();
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const AgreementFailure(
        'auth-token-unavailable',
        'Your sign-in token could not be obtained. Sign in again and retry.',
      );
    }

    try {
      final result = await _requestSimplification(
        token: token,
        bytes: bytes,
        filename: filename,
      );
      final reportReference = _reports.doc();
      final documentPath =
          'students/${user.uid}/agreements/${reportReference.id}/document.pdf';
      final documentReference = _storage.ref(documentPath);
      var uploaded = false;
      try {
        await documentReference.putData(
          bytes,
          SettableMetadata(
            contentType: 'application/pdf',
            customMetadata: {
              'ownerId': user.uid,
              'agreementId': reportReference.id,
            },
          ),
        );
        uploaded = true;
        await reportReference.set({
          'studentId': user.uid,
          'documentPath': documentPath,
          'filename': _safeFilename(filename),
          'extractionMethod': result.extractionMethod.storedValue,
          'clauses': result.clauses
              .map((clause) => clause.toJson())
              .toList(growable: false),
          'disclaimer': result.disclaimer,
          'modelId': result.modelId,
          'processingStatus': 'completed',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        if (uploaded) {
          try {
            await documentReference.delete();
          } on FirebaseException {
            throw const AgreementFailure(
              'agreement-cleanup-failed',
              'The result could not be saved and its private PDF could not be removed.',
            );
          }
        }
        rethrow;
      }
      return AgreementReport(
        id: reportReference.id,
        studentId: user.uid,
        documentPath: documentPath,
        filename: _safeFilename(filename),
        result: result,
        createdAt: DateTime.now().toUtc(),
      );
    } on AgreementFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    } on TimeoutException {
      throw const AgreementFailure(
        'agreement-timeout',
        'Agreement processing took too long. Check the API connection and retry.',
      );
    } on SocketException {
      throw const AgreementFailure(
        'agreement-unreachable',
        'The agreement-simplification API could not be reached.',
      );
    } on http.ClientException {
      throw const AgreementFailure(
        'agreement-unreachable',
        'The agreement-simplification API could not be reached.',
      );
    } on FormatException {
      throw const AgreementFailure(
        'invalid-api-response',
        'The agreement service returned an unsafe or invalid result.',
      );
    }
  }

  Future<AgreementSimplificationResult> _requestSimplification({
    required String token,
    required Uint8List bytes,
    required String filename,
  }) async {
    final baseUri = AppConfig.validatedAiApiUri(apiBaseUrl);
    if (baseUri == null) {
      throw const AgreementFailure(
        'invalid-api-url',
        'The agreement API address is not configured correctly.',
      );
    }
    final request = http.MultipartRequest(
      'POST',
      baseUri.resolve('/simplify-agreement'),
    )..headers['Authorization'] = 'Bearer $token';
    request.files.add(
      http.MultipartFile.fromBytes(
        'document',
        bytes,
        filename: _safeFilename(filename),
        contentType: http_parser.MediaType('application', 'pdf'),
      ),
    );
    final streamed = await _httpClient.send(request).timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AgreementFailure(
        'agreement-api-${response.statusCode}',
        _apiErrorMessage(response),
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Expected an object response.');
    }
    return AgreementSimplificationResult.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  User _authenticatedUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AgreementFailure(
        'auth-required',
        'Sign in as a student to simplify an agreement.',
      );
    }
    return user;
  }

  static AgreementReport _reportFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final studentId = data['studentId'];
    final documentPath = data['documentPath'];
    final filename = data['filename'];
    final createdAt = data['createdAt'];
    if (studentId is! String ||
        studentId.isEmpty ||
        documentPath is! String ||
        documentPath.isEmpty ||
        filename is! String ||
        filename.isEmpty ||
        data['processingStatus'] != 'completed' ||
        (createdAt != null && createdAt is! Timestamp)) {
      throw const AgreementFailure(
        'invalid-saved-agreement',
        'A saved agreement contains invalid data.',
      );
    }
    return AgreementReport(
      id: document.id,
      studentId: studentId,
      documentPath: documentPath,
      filename: filename,
      result: AgreementSimplificationResult.fromJson(data),
      createdAt: (createdAt as Timestamp?)?.toDate(),
    );
  }

  static bool _hasPdfSignature(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D;

  static String _safeFilename(String filename) {
    var stem = filename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (stem.toLowerCase().endsWith('.pdf')) {
      stem = stem.substring(0, stem.length - 4);
    }
    if (stem.isEmpty) stem = 'agreement';
    final limitedStem = stem.length <= 96 ? stem : stem.substring(0, 96);
    return '$limitedStem.pdf';
  }

  static String _apiErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['message'] is String) {
        final message = (decoded['message'] as String).trim();
        if (message.isNotEmpty) return message;
      }
    } on FormatException {
      // Fall through to a safe message that does not expose provider output.
    }
    return 'The agreement service could not process this PDF.';
  }

  static AgreementFailure _mapFirebaseError(FirebaseException error) =>
      AgreementFailure(error.code, switch (error.code) {
        'permission-denied' =>
          'You do not have permission to save this private agreement.',
        'unavailable' => 'Firebase is unavailable. Check your connection.',
        _ => 'The private agreement result could not be saved.',
      });
}
