import 'manga_source.dart';

/// حاوية المصادر المتاحة، تُبنى في `providers.dart` (sourceRegistryProvider).
///
/// أضف المصدر الجديد إلى تلك القائمة فقط؛ لا تُعدّل أي شاشة أو مدير تحميل.
/// أما المفعَّل منها فيحدده المستخدم من شاشة «مصادر التحميل».
class SourceRegistry {
  SourceRegistry(List<MangaSource> sources)
      : _byId = {for (final s in sources) s.id: s};

  final Map<String, MangaSource> _byId;

  List<MangaSource> get all => _byId.values.toList(growable: false);

  MangaSource? byId(String id) => _byId[id];

  /// يُستعمل عند القراءة من قاعدة البيانات حيث يجب أن يوجد المصدر.
  MangaSource require(String id) {
    final source = _byId[id];
    if (source == null) {
      throw StateError('المصدر "$id" غير مسجَّل. ربما أُزيل بعد التحديث.');
    }
    return source;
  }
}
