import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/utils/result.dart';
import '../../providers.dart';

Future<void> showAddSourceSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    builder: (_) => const _AddSourceSheet(),
  );
}

class _AddSourceSheet extends ConsumerStatefulWidget {
  const _AddSourceSheet();

  @override
  ConsumerState<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends ConsumerState<_AddSourceSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _url.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم المصدر ورابط الخادم.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(customSourcesControllerProvider).add(
            name: name,
            baseUrl: _url.text,
            username: _user.text,
            password: _pass.text,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text('أُضيف المصدر «$name»')));
    } on AppFailure catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _busy = false;
        _error = 'تعذّرت إضافة المصدر. تحقّق من الرابط ثم أعد المحاولة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('إضافة مصدر', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'أضف خادم مكتبة شخصية يعمل بواجهة Komga، مثل خادم تديره على '
              'حاسوبك أو جهاز التخزين في بيتك. يُختبر الاتصال قبل الحفظ.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'اسم المصدر'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'رابط الخادم',
                hintText: 'http://192.168.1.10:25600',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'اسم المستخدم (إن وُجد)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              enabled: !_busy,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'كلمة المرور (إن وُجدت)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.ink,
                      ),
                    )
                  : const Text('اختبار الاتصال وحفظ'),
            ),
          ],
        ),
      ),
    );
  }
}
