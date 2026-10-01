import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth/domain/app_user.dart';
import '../../auth/domain/auth_failure.dart';
import '../../auth/domain/user_role.dart';
import '../domain/user_management_repository.dart';

class FirebaseUserManagementRepository implements UserManagementRepository {
  FirebaseUserManagementRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Stream<List<AppUser>> watchUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final users = snapshot.docs.map(_fromDocument).toList(growable: false)
        ..sort((left, right) => left.name.compareTo(right.name));
      return List.unmodifiable(users);
    });
  }

  @override
  Stream<AppUser?> watchUser(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((document) {
      if (!document.exists) return null;
      return _fromData(document.id, document.data()!);
    });
  }

  @override
  Future<void> updateAgentProfile(AgentProfileInput input) async {
    final validationError = input.validate();
    if (validationError != null) {
      throw AuthFailure('invalid-agent-profile', validationError);
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const AuthFailure('auth-required', 'Sign in to edit your profile.');
    }
    try {
      await _firestore.collection('users').doc(uid).update({
        'name': input.name.trim(),
        'agencyName': input.agencyName.trim(),
        'phone': input.phone.trim(),
        'registrationNumber': input.registrationNumber.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _auth.currentUser?.updateDisplayName(input.name.trim());
    } on FirebaseException catch (error) {
      throw AuthFailure(
        error.code,
        'The agent profile could not be updated. Please try again.',
      );
    }
  }

  @override
  Future<void> setAccountStatus(String uid, AccountStatus status) async {
    if (uid == _auth.currentUser?.uid) {
      throw const AuthFailure(
        'self-status-change',
        'Administrators cannot disable their own active session.',
      );
    }
    try {
      await _firestore.collection('users').doc(uid).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw AuthFailure(
        error.code,
        'The account status could not be updated. Please try again.',
      );
    }
  }

  static AppUser _fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return _fromData(document.id, document.data());
  }

  static AppUser _fromData(String uid, Map<String, dynamic> data) {
    final role = UserRole.fromStoredValue(data['role']);
    final status = switch (data['status']) {
      'active' => AccountStatus.active,
      'disabled' => AccountStatus.disabled,
      _ => null,
    };
    final name = data['name'];
    final email = data['email'];
    if (role == null ||
        status == null ||
        name is! String ||
        name.trim().isEmpty ||
        email is! String) {
      throw const AuthFailure(
        'invalid-user-profile',
        'A stored user profile contains invalid fields.',
      );
    }
    return AppUser(
      uid: uid,
      name: name.trim(),
      email: email.trim(),
      role: role,
      status: status,
      agencyName: (data['agencyName'] as String?)?.trim(),
      phone: (data['phone'] as String?)?.trim(),
      registrationNumber: (data['registrationNumber'] as String?)?.trim(),
    );
  }
}
