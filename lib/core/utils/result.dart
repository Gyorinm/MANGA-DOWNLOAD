/// نتيجة موحدة تُغني عن رمي الاستثناءات عبر الطبقات.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;

  R fold<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>() => ok(self.value),
      Err<T>() => err(self.failure),
    };
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final AppFailure failure;
}

/// وصف الخطأ بلغة المستخدم، لا بلغة النظام.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  factory AppFailure.network([Object? cause]) =>
      AppFailure('تعذّر الاتصال بالمصدر. تحقّق من الشبكة ثم أعد المحاولة.',
          cause: cause);

  factory AppFailure.parsing([Object? cause]) =>
      AppFailure('وصلت بيانات غير مفهومة من المصدر.', cause: cause);

  factory AppFailure.storage([Object? cause]) =>
      AppFailure('تعذّر الحفظ على الجهاز. تأكّد من توفّر مساحة كافية.',
          cause: cause);

  @override
  String toString() => 'AppFailure($message, cause: $cause)';
}
