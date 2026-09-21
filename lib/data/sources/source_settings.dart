import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// المصادر المفعّلة، بحسب اختيار المستخدم.
///
/// يُحفظ المعطَّل لا المفعَّل: فأي مصدر يُضاف في تحديث لاحق يظهر مفعّلًا افتراضيًا،
/// ولا يختفي عن مستخدم لم يعرف بوجوده. وتبقى دائمًا مصدر واحد على الأقل مفعّلًا.
class SourceSettingsNotifier extends StateNotifier<Set<String>> {
  SourceSettingsNotifier(this._prefs, this._allIds)
      : super(_load(_prefs, _allIds));

  static const _disabledKey = 'disabled_sources';

  final SharedPreferences _prefs;
  final Set<String> _allIds;

  static Set<String> _load(SharedPreferences prefs, Set<String> allIds) {
    final disabled = (prefs.getStringList(_disabledKey) ?? const []).toSet();
    final enabled = allIds.difference(disabled);
    // حماية من حالة غير صالحة: لا يجوز أن يبقى البحث بلا أي مصدر.
    return enabled.isEmpty ? allIds : enabled;
  }

  bool isEnabled(String id) => state.contains(id);

  Future<void> setEnabled(String id, bool enabled) async {
    final next = {...state};
    if (enabled) {
      next.add(id);
    } else {
      if (!next.contains(id) || next.length <= 1) return;
      next.remove(id);
    }
    state = next;
    await _prefs.setStringList(
      _disabledKey,
      _allIds.difference(next).toList(),
    );
  }
}
