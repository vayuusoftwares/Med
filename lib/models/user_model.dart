class User {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String roleLabel;
  final bool isActive;
  final String createdAt;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.roleLabel,
    required this.isActive,
    required this.createdAt,
  });

  bool get isAdmin => role == 'admin';

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      role: json['role'] as String,
      roleLabel: json['role_label'] as String,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'role_label': roleLabel,
      'is_active': isActive,
      'created_at': createdAt,
    };
  }
}
