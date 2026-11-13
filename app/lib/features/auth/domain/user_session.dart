enum UserRole {
  administrador,
  repartidor;

  static UserRole fromCode(String code) =>
      code == 'REPARTIDOR' ? UserRole.repartidor : UserRole.administrador;

  String get code => name.toUpperCase();
}

class UserSession {
  const UserSession({required this.id, required this.nombre, required this.usuario, required this.rol});

  final int id;
  final String nombre;
  final String usuario;
  final UserRole rol;

  String get primerNombre => nombre.split(' ').first;

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        id: (json['id'] as num).toInt(),
        nombre: json['nombre'] as String,
        usuario: json['usuario'] as String,
        rol: UserRole.fromCode(json['rol'] as String),
      );

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'usuario': usuario, 'rol': rol.code};
}

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}
