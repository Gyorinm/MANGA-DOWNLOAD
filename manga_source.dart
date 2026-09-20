import '../../domain/entities/chapter.dart';
import '../../domain/entities/manga.dart';

/// العقد الذي يجب أن يطبّقه كل مصدر.
///
/// لا شيء في بقية التطبيق يعرف كيف يعمل مصدر بعينه: الشاشات ومدير التحميل
/// يتعاملان مع هذه الواجهة فقط. إضافة مصدر جديد = كلاس جديد + سطر في السجل.
abstract interface class MangaSource {
  /// معرّف تقني ثابت يُخزَّن في قاعدة البيانات. لا يتغيّر بعد الإطلاق.
  String get id;

  /// الاسم المعروض للمستخدم.
  String get displayName;

  /// اللغات التي يوفّرها المصدر.
  List<String> get languages;

  /// هل يحتاج المصدر ترويسات خاصة عند تنزيل الصور؟
  Map<String, String> get imageHeaders => const {};

  Future<List<Manga>> search(String query, {int page = 1});

  Future<Manga> details(String remoteId);

  /// كل الفصول مرتّبة تصاعديًا، بلغة محدّدة إن أمكن.
  Future<List<Chapter>> chapters(String remoteId, {String language = 'ar'});

  /// روابط صفحات الفصل بالترتيب.
  Future<List<String>> pageUrls(String chapterRemoteId);
}
