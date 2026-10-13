import '../l10n/translations.dart';
import '../services/locale_service.dart';

/// `'Exit'.tr` gives the text in the current app language (English when a
/// translation is missing). `'{n} days left'.trArgs({'n': 3})` fills {name}s.
extension Tr on String {
  String get tr => kTranslations[AppLocale.code]?[this] ?? this;

  String trArgs(Map<String, Object?> args) {
    var s = tr;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}
