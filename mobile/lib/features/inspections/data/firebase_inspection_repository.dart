import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../shared/validation/image_content.dart';
import '../../properties/domain/property_listing.dart';
import '../domain/inspection_checklist.dart';
import '../domain/inspection_failure.dart';
import '../domain/inspection_repository.dart';
import '../domain/property_inspection.dart';

class FirebaseInspectionRepository implements InspectionRepository {
  FirebaseInspectionRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _inspections =>
      _firestore.collection('inspections');

  @override
  Stream<PropertyInspection?> watchPropertyInspection(String propertyId) {
    final uid = _authenticatedUid();
    return watchInspection(_inspectionId(propertyId, uid));
  }

  @override
  Stream<PropertyInspection?> watchInspection(String inspectionId) {
    _authenticatedUid();
    return _inspections
        .doc(inspectionId)
        .snapshots()
        .map((document) => document.exists ? _fromDocument(document) : null);
  }

  @override
  Future<String> startOrResume({
    required String propertyId,
    required String propertyName,
  }) async {
    final uid = _authenticatedUid();
    final normalizedName = propertyName.trim();
    if (propertyId.trim().isEmpty || normalizedName.length < 3) {
      throw const InspectionFailure(
        'invalid-property',
        'Choose a valid approved property before starting an inspection.',
      );
    }
    final inspectionId = _inspectionId(propertyId, uid);
    final inspectionReference = _inspections.doc(inspectionId);
    final propertyReference = _firestore
        .collection('properties')
        .doc(propertyId);
    final profileReference = _firestore.collection('users').doc(uid);
    try {
      await _firestore.runTransaction((transaction) async {
        final propertySnapshot = await transaction.get(propertyReference);
        final profileSnapshot = await transaction.get(profileReference);
        final inspectionSnapshot = await transaction.get(inspectionReference);
        final property = propertySnapshot.data();
        final profile = profileSnapshot.data();
        if (!propertySnapshot.exists ||
            property?['approvalStatus'] !=
                PropertyApprovalStatus.approved.name ||
            property?['propertyName'] != normalizedName) {
          throw const InspectionFailure(
            'property-not-inspectable',
            'Only an approved property can start a guided inspection.',
          );
        }
        if (!profileSnapshot.exists ||
            profile?['role'] != 'student' ||
            profile?['status'] != 'active') {
          throw const InspectionFailure(
            'student-required',
            'An active student account is required for guided inspection.',
          );
        }
        if (inspectionSnapshot.exists) {
          _requireOwner(_fromDocument(inspectionSnapshot), uid);
          return;
        }
        final now = FieldValue.serverTimestamp();
        transaction.set(inspectionReference, {
          'studentId': uid,
          'propertyId': propertyId,
          'propertyName': normalizedName,
          'checklistVersion': InspectionChecklist.version,
          'status': InspectionStatus.inProgress.storedValue,
          'results': _resultsToData(PropertyInspection.emptyFindings()),
          'startedAt': now,
          'updatedAt': now,
        });
      });
      return inspectionId;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> saveFinding({
    required String inspectionId,
    required InspectionFinding finding,
  }) async {
    final validationError = finding.validate();
    if (validationError != null) {
      throw InspectionFailure('invalid-finding', validationError);
    }
    final uid = _authenticatedUid();
    String? oldPhotoPath;
    try {
      await _firestore.runTransaction((transaction) async {
        final reference = _inspections.doc(inspectionId);
        final snapshot = await transaction.get(reference);
        final inspection = _existingInspection(snapshot);
        _requireEditableOwner(inspection, uid);
        final oldFinding = inspection.findingFor(finding.checkId);
        oldPhotoPath = oldFinding.concernImagePath;
        final nextFindings = inspection.findings
            .map(
              (stored) => stored.checkId == finding.checkId
                  ? finding.copyWith(note: finding.note.trim())
                  : stored,
            )
            .toList(growable: false);
        transaction.update(reference, {
          'results': _resultsToData(nextFindings),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      final nextPhotoPath = finding.concernImagePath;
      if (oldPhotoPath != null && oldPhotoPath != nextPhotoPath) {
        try {
          await _storage.ref(oldPhotoPath!).delete();
        } on FirebaseException {
          throw const InspectionFailure(
            'photo-cleanup-failed',
            'The finding was saved but its previous concern photo could not be removed.',
          );
        }
      }
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<String> uploadConcernPhoto({
    required String inspectionId,
    required String checkId,
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) async {
    final normalizedType = normalizeImageContentType(contentType);
    final photoError = ConcernPhotoInput(
      byteLength: bytes.length,
      contentType: normalizedType,
    ).validate();
    if (photoError != null || !imageContentMatchesType(bytes, normalizedType)) {
      throw InspectionFailure(
        'invalid-concern-photo',
        photoError ?? 'The concern photo content does not match its JPEG, PNG, or WebP type.',
      );
    }
    if (InspectionChecklist.itemById(checkId) == null) {
      throw const InspectionFailure(
        'invalid-check',
        'The concern photo is not linked to a valid inspection check.',
      );
    }
    final uid = _authenticatedUid();
    final safeFilename = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'students/$uid/inspections/$inspectionId/${checkId}_${DateTime.now().microsecondsSinceEpoch}_$safeFilename';
    final photoReference = _storage.ref(path);
    String? oldPhotoPath;
    try {
      final initial = _existingInspection(
        await _inspections.doc(inspectionId).get(),
      );
      _requireEditableOwner(initial, uid);
      if (initial.findingFor(checkId).state != InspectionFindingState.concern) {
        throw const InspectionFailure(
          'concern-required',
          'Mark the check as a concern before attaching a photo.',
        );
      }
      await photoReference.putData(
        bytes,
        SettableMetadata(
          contentType: normalizedType,
          customMetadata: {
            'ownerId': uid,
            'inspectionId': inspectionId,
            'checkId': checkId,
          },
        ),
      );
      final downloadUrl = await photoReference.getDownloadURL();
      try {
        await _firestore.runTransaction((transaction) async {
          final inspectionReference = _inspections.doc(inspectionId);
          final snapshot = await transaction.get(inspectionReference);
          final inspection = _existingInspection(snapshot);
          _requireEditableOwner(inspection, uid);
          final finding = inspection.findingFor(checkId);
          if (finding.state != InspectionFindingState.concern) {
            throw const InspectionFailure(
              'concern-required',
              'The check is no longer marked as a concern.',
            );
          }
          oldPhotoPath = finding.concernImagePath;
          final nextFindings = inspection.findings
              .map(
                (stored) => stored.checkId == checkId
                    ? stored.copyWith(
                        concernImagePath: path,
                        concernImageUrl: downloadUrl,
                      )
                    : stored,
              )
              .toList(growable: false);
          transaction.update(inspectionReference, {
            'results': _resultsToData(nextFindings),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      } catch (_) {
        try {
          await photoReference.delete();
        } on FirebaseException {
          throw const InspectionFailure(
            'upload-rollback-failed',
            'The concern photo uploaded but could not be linked or cleaned up.',
          );
        }
        rethrow;
      }
      if (oldPhotoPath != null && oldPhotoPath != path) {
        await _storage.ref(oldPhotoPath!).delete();
      }
      return downloadUrl;
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  @override
  Future<void> completeInspection(String inspectionId) async {
    final uid = _authenticatedUid();
    try {
      await _firestore.runTransaction((transaction) async {
        final reference = _inspections.doc(inspectionId);
        final snapshot = await transaction.get(reference);
        final inspection = _existingInspection(snapshot);
        _requireEditableOwner(inspection, uid);
        if (!inspection.canComplete) {
          throw const InspectionFailure(
            'inspection-incomplete',
            'Answer every checklist item before completing the inspection.',
          );
        }
        final now = FieldValue.serverTimestamp();
        transaction.update(reference, {
          'status': InspectionStatus.completed.storedValue,
          'completedAt': now,
          'updatedAt': now,
        });
      });
    } on FirebaseException catch (error) {
      throw _mapFirebaseError(error);
    }
  }

  String _authenticatedUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const InspectionFailure(
        'auth-required',
        'Sign in before managing a guided inspection.',
      );
    }
    return uid;
  }

  static String _inspectionId(String propertyId, String uid) =>
      '${propertyId}_$uid';

  static void _requireOwner(PropertyInspection inspection, String uid) {
    if (inspection.studentId != uid) {
      throw const InspectionFailure(
        'inspection-not-owned',
        'You can access only your own guided inspections.',
      );
    }
  }

  static void _requireEditableOwner(PropertyInspection inspection, String uid) {
    _requireOwner(inspection, uid);
    if (inspection.status != InspectionStatus.inProgress) {
      throw const InspectionFailure(
        'inspection-completed',
        'A completed inspection cannot be changed.',
      );
    }
  }

  static PropertyInspection _existingInspection(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) {
      throw const InspectionFailure(
        'inspection-not-found',
        'The guided inspection no longer exists.',
      );
    }
    return _fromDocument(snapshot);
  }

  static PropertyInspection _fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) {
      throw const InspectionFailure(
        'invalid-inspection-data',
        'The guided inspection data is missing.',
      );
    }
    final status = InspectionStatus.fromStoredValue(data['status']);
    final version = data['checklistVersion'];
    final storedResults = data['results'];
    if (status == null ||
        version != InspectionChecklist.version ||
        storedResults is! Map ||
        storedResults.length != InspectionChecklist.items.length) {
      throw const InspectionFailure(
        'invalid-inspection-data',
        'The guided inspection uses invalid or unsupported checklist data.',
      );
    }
    final findings = <InspectionFinding>[];
    for (final item in InspectionChecklist.items) {
      final raw = storedResults[item.id];
      if (raw is! Map) {
        throw const InspectionFailure(
          'invalid-inspection-data',
          'A guided inspection result is missing.',
        );
      }
      final result = Map<String, dynamic>.from(raw);
      final state = InspectionFindingState.fromStoredValue(result['state']);
      if (result['checkId'] != item.id ||
          result['sectionId'] != item.sectionId ||
          state == null ||
          result['note'] is! String) {
        throw const InspectionFailure(
          'invalid-inspection-data',
          'A guided inspection result contains invalid fields.',
        );
      }
      final path = result['concernImagePath'];
      final url = result['concernImageUrl'];
      if ((path != null && path is! String) ||
          (url != null && url is! String)) {
        throw const InspectionFailure(
          'invalid-inspection-data',
          'A concern photo contains invalid fields.',
        );
      }
      final finding = InspectionFinding(
        checkId: item.id,
        sectionId: item.sectionId,
        state: state,
        note: (result['note'] as String).trim(),
        concernImagePath: path as String?,
        concernImageUrl: url as String?,
      );
      if (finding.validate() != null) {
        throw const InspectionFailure(
          'invalid-inspection-data',
          'A guided inspection result failed validation.',
        );
      }
      findings.add(finding);
    }
    final completedAt = (data['completedAt'] as Timestamp?)?.toDate();
    if ((status == InspectionStatus.completed) != (completedAt != null)) {
      throw const InspectionFailure(
        'invalid-inspection-data',
        'The guided inspection completion state is inconsistent.',
      );
    }
    try {
      return PropertyInspection(
        id: document.id,
        studentId: _requiredString(data, 'studentId'),
        propertyId: _requiredString(data, 'propertyId'),
        propertyName: _requiredString(data, 'propertyName'),
        checklistVersion: version as String,
        status: status,
        findings: List.unmodifiable(findings),
        startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
        completedAt: completedAt,
      );
    } on TypeError {
      throw const InspectionFailure(
        'invalid-inspection-data',
        'The guided inspection contains invalid data and cannot be displayed.',
      );
    }
  }

  static Map<String, Map<String, Object?>> _resultsToData(
    List<InspectionFinding> findings,
  ) {
    if (findings.length != InspectionChecklist.items.length) {
      throw const InspectionFailure(
        'invalid-inspection-data',
        'Every checklist result must be present.',
      );
    }
    return {
      for (final finding in findings)
        finding.checkId: {
          'checkId': finding.checkId,
          'sectionId': finding.sectionId,
          'state': finding.state.storedValue,
          'note': finding.note.trim(),
          'concernImagePath': ?finding.concernImagePath,
          'concernImageUrl': ?finding.concernImageUrl,
        },
    };
  }

  static String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.trim().isEmpty) {
      throw InspectionFailure(
        'invalid-inspection-data',
        'The guided inspection is missing $field.',
      );
    }
    return value.trim();
  }

  static InspectionFailure _mapFirebaseError(FirebaseException error) {
    final message = switch (error.code) {
      'permission-denied' =>
        'You are not allowed to perform this inspection action.',
      'unavailable' =>
        'The guided inspection service is temporarily unavailable.',
      'object-not-found' ||
      'not-found' => 'The inspection or concern photo no longer exists.',
      _ => 'The guided inspection action could not be completed. Please try again.',
    };
    return InspectionFailure(error.code, message);
  }
}
