import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'custom_source_config.dart';

/// حفظ المصادر التي أضافها المستخدم.
/// البيانات العادية في SharedPreferences، وكلمات المرور في التخزين الآمن.
class CustomSourceStore {
  CustomSourceStore(this._prefs, this._secure);

  static const _listKey = 'custom_sources';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  String _passwordKey(String id) => 'source_pw_$id';

  Future<List<CustomSourceConfig>> loadAll() async {
    final raw = _prefs.getStringList(_listKey) ?? const <String>[];
    final result = <CustomSourceConfig>[];

    for (final item in raw) {
      try {
        final json = (jsonDecode(item) as Map).cast<String, dynamic>();
        final id = json['id'] as String;
        var password = '';
        try {
          password = await _secure.read(key: _passwordKey(id)) ?? '';
        } catch (_) {
          // تعذّر التخزين الآمن: يبقى المصدر ويُطلب من المستخدم إعادة إدخال كلمة المرور.
        }
        result.add(CustomSourceConfig.fromJson(json, password: password));
      } catch (_) {
        // سجل تالف: يُتجاوز بدل أن يُسقط الإقلاع كله.
      }
    }
    return result;
  }

  Future<void> save(CustomSourceConfig config) async {
    final others = (_prefs.getStringList(_listKey) ?? const <String>[])
        .where((item) => !_hasId(item, config.id))
        .toList();
    others.add(jsonEncode(config.toJson()));
    await _prefs.setStringList(_listKey, others);

    if (config.password.isNotEmpty) {
      await _secure.write(key: _passwordKey(config.id), value: config.password);
    }
  }

  Future<void> delete(String id) async {
    final remaining = (_prefs.getStringList(_listKey) ?? const <String>[])
        .where((item) => !_hasId(item, id))
        .toList();
    await _prefs.setStringList(_listKey, remaining);
    try {
      await _secure.delete(key: _passwordKey(id));
    } catch (_) {}
  }

  bool _hasId(String encoded, String id) {
    try {
      return (jsonDecode(encoded) as Map)['id'] == id;
    } catch (_) {
      return false;
    }
  }
}
