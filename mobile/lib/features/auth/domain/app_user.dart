import 'user_role.dart';

enum AccountStatus { active, disabled }

class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.agencyName,
    this.phone,
    this.registrationNumber,
  });

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final AccountStatus status;
  final String? agencyName;
  final String? phone;
  final String? registrationNumber;

  bool get isDisabled => status == AccountStatus.disabled;
}
