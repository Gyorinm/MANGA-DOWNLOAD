import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../providers.dart';

/// غلاف بنسبة 2:3 يفضّل الملف المحلي، ويسقط إلى الشبكة، ثم إلى بديل نصي.
///
/// هذا هو المكان الوحيد الذي يقرّر كيف تُعرض الأغلفة، فلا يتكرر المنطق.
class CoverImage extends ConsumerWidget {
  const CoverImage({
    super.key,
    this.localPath,
    this.remoteUrl,
    this.sourceId,
    this.title = '',
    this.radius = 10,
  });

  final String? localPath;
  final String? remoteUrl;

  /// لإرفاق ترويسة الدخول عندما يكون الغلاف على خادم محميّ.
  final String? sourceId;
  final String title;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sourceId;
    final headers =
        id == null ? null : ref.watch(sourceRegistryProvider).byId(id)?.imageHeaders;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: _build(headers),
      ),
    );
  }

  Widget _build(Map<String, String>? headers) {
    final path = localPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }

    final url = remoteUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        fit: BoxFit.cover,
        placeholder: (_, __) => const ColoredBox(color: AppTheme.surfaceHigh),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }

    return _fallback();
  }

  Widget _fallback() {
    return Container(
      color: AppTheme.surfaceHigh,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: Text(
        title.isEmpty ? 'بلا غلاف' : title,
        maxLines: 3,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
      ),
    );
  }
}

/// شاشة فارغة تدعو إلى فعل بدل أن تكتفي بالإخبار.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.headline,
    required this.body,
    this.action,
  });

  final String headline;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(headline, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// رسالة خطأ تشرح ما حدث وتعرض طريق الخروج.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
