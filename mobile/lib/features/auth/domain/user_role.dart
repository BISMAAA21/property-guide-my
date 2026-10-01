enum UserRole {
  student,
  agent,
  admin;

  static UserRole? fromStoredValue(String? value) {
    return UserRole.values.where((role) => role.name == value).firstOrNull;
  }

  String get displayName => switch (this) {
    UserRole.student => 'Student',
    UserRole.agent => 'Property Agent',
    UserRole.admin => 'Administrator',
  };

  String get homeLocation => '/$name';
}
