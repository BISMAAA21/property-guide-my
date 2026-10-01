import '../../auth/domain/app_user.dart';

class AgentProfileInput {
  const AgentProfileInput({
    required this.name,
    required this.agencyName,
    required this.phone,
    required this.registrationNumber,
  });

  final String name;
  final String agencyName;
  final String phone;
  final String registrationNumber;

  String? validate() {
    if (name.trim().length < 2) return 'Enter your full name.';
    if (agencyName.trim().length < 2) return 'Enter the agency name.';
    if (phone.trim().length < 7 || phone.trim().length > 24) {
      return 'Enter a valid contact number.';
    }
    if (registrationNumber.trim().length < 3) {
      return 'Enter the agent registration number.';
    }
    return null;
  }
}

abstract interface class UserManagementRepository {
  Stream<List<AppUser>> watchUsers();

  Stream<AppUser?> watchUser(String uid);

  Future<void> updateAgentProfile(AgentProfileInput input);

  Future<void> setAccountStatus(String uid, AccountStatus status);
}
