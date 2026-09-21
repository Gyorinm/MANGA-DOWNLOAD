/// إعدادات مصدر أضافه المستخدم بنفسه.
///
/// كلمة المرور لا تُحفظ مع بقية الحقول؛ تُخزَّن منفصلة في التخزين الآمن للنظام
/// (انظر [CustomSourceStore])، ولذلك يغيب عنها [toJson].
class CustomSourceConfig {
  const CustomSourceConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.username = '',
    this.password = '',
  });

  /// معرّف ثابت يُخزَّن في قاعدة البيانات مع كل مانهوا محمّلة من هذا المصدر.
  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
      };

  factory CustomSourceConfig.fromJson(
    Map<String, dynamic> json, {
    String password = '',
  }) {
    return CustomSourceConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      username: (json['username'] as String?) ?? '',
      password: password,
    );
  }
}
