import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../domain/entities/manga.dart';
import '../../providers.dart';

/// نافذة تأكيد موحّدة لكل عمليات الحذف، فلا يُحذف شيء بلمسة واحدة.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'حذف',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('تراجع'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// يحذف المانهوا مع فصولها وصورها بعد التأكيد، ويوقف تحميلها الجاري.
/// يعيد true إن تم الحذف.
Future<bool> confirmAndDeleteManga(
  BuildContext context,
  WidgetRef ref,
  Manga manga,
) async {
  final ok = await confirmDialog(
    context,
    title: 'حذف «${manga.title}»',
    body: 'ستُحذف كل فصولها وصورها من الجهاز. يمكنك تنزيلها لاحقًا من جديد.',
  );
  if (!ok) return false;

  ref.read(downloadManagerProvider).cancelManga(manga.key);
  await ref.read(libraryRepositoryProvider).removeManga(manga.key);
  return true;
}
