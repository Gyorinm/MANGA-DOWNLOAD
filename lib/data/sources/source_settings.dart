import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// المواقع التي اختار المستخدم البحث والتحميل منها.
///
/// الإصدار السابق كان يحفظ قائمة المواقع المعطّلة فقط. ننتقل الآن إلى
/// قائمة المواقع المفعّلة حتى تصبح «إضافة موقع» عملية واضحة من واجهة التطبيق.
/// تتم المحافظة على الاختيار القديم عند أول تشغيل بعد التحديث.
class SourceSettingsNotifier extends StateNotifier<Set<String>> {
  SourceSettingsNotifier(this._prefs, this._allIds)
      : super(_load(_prefs, _allIds));

  static const _enabledKey = 'enabled_sources';
  static const _legacyDisabledKey = 'disabled_sources';

  final SharedPreferences _prefs;
  final Set<String> _allIds;

  static Set<String> _load(SharedPreferences prefs, Set<String> allIds) {
    if (allIds.isEmpty) return <String>{};

    final savedEnabled = prefs.getStringList(_enabledKey);
    if (savedEnabled != null) {
      final enabled = savedEnabled.toSet()..retainAll(allIds);
      return enabled.isEmpty ? allIds : enabled;
    }

    // ترحيل اختيار النسخة السابقة بدل تجاهله.
    final savedDisabled = prefs.getStringList(_legacyDisabledKey);
    if (savedDisabled != null) {
      final enabled = allIds.difference(savedDisabled.toSet());
      return enabled.isEmpty ? allIds : enabled;
    }

    // عند التثبيت الجديد يبدأ التطبيق بجميع المواقع مفعّلة، لأن التطبيق
    // مصمّم للبحث عبر كل المصادر في نفس الوقت. هذا يمنع «الظهور في موقع واحد فقط»
    // عند أول تشغيل ويبقي للمستخدم حرية إيقاف أي موقع لاحقًا.
    return allIds;
  }

  bool isEnabled(String id) => state.contains(id);

  Future<void> setEnabled(String id, bool enabled) async {
    if (!_allIds.contains(id)) return;

    final next = {...state};
    if (enabled) {
      next.add(id);
    } else {
      // لا نسمح بأن يصبح البحث بلا أي موقع.
      if (!next.contains(id) || next.length <= 1) return;
      next.remove(id);
    }

    state = next;
    await _prefs.setStringList(_enabledKey, next.toList()..sort());
    await _prefs.remove(_legacyDisabledKey);
  }
}
