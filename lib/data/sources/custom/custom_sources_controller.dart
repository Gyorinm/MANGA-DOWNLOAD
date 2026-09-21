import '../../../core/http/http_client.dart';
import '../source_registry.dart';
import 'custom_source_config.dart';
import 'custom_source_store.dart';
import 'komga_source.dart';

/// إضافة المصادر التي يكتبها المستخدم وإزالتها وحفظها.
class CustomSourcesController {
  CustomSourcesController({
    required this.registry,
    required this.store,
    required this.http,
    required this.onChanged,
  });

  final SourceRegistry registry;
  final CustomSourceStore store;
  final HttpClient http;

  /// تنبيه الواجهة بأن قائمة المصادر تغيّرت.
  final void Function() onChanged;

  /// يختبر الاتصال أولًا؛ لا يُحفظ مصدر لا يعمل.
  /// يرمي [AppFailure] برسالة مفهومة عند الفشل.
  Future<void> add({
    required String name,
    required String baseUrl,
    String username = '',
    String password = '',
  }) async {
    final config = CustomSourceConfig(
      id: 'komga-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      baseUrl: _normalize(baseUrl),
      username: username.trim(),
      password: password,
    );

    final source = KomgaSource(http, config);
    await source.verifyConnection();

    await store.save(config);
    registry.register(source);
    onChanged();
  }

  Future<void> remove(String id) async {
    registry.unregister(id);
    await store.delete(id);
    onChanged();
  }

  static String _normalize(String raw) {
    var url = raw.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url.replaceAll(RegExp(r'/+$'), '');
  }
}
