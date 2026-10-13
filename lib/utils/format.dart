import '../services/locale_service.dart';

class _DateNames {
  final List<String> weekdays, weekdaysShort, months, monthsShort;
  final String today, tomorrow, yesterday, pattern;
  const _DateNames(this.weekdays, this.weekdaysShort, this.months,
      this.monthsShort, this.today, this.tomorrow, this.yesterday,
      this.pattern);
}

// Names follow the app language (AppLocale). Missing language = English.
// pattern placeholders: {wd} weekday, {d} day, {m} month, {y} year.
const _en = _DateNames(
  ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
  ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'],
  ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
    'Nov', 'Dec'],
  'Today', 'Tomorrow', 'Yesterday', '{wd}, {d} {m} {y}',
);

const Map<String, _DateNames> _names = {
  'fr': _DateNames(
    ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'],
    ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
    ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août',
      'septembre', 'octobre', 'novembre', 'décembre'],
    ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août',
      'sept.', 'oct.', 'nov.', 'déc.'],
    "Aujourd’hui", 'Demain', 'Hier', '{wd} {d} {m} {y}',
  ),
  'es': _DateNames(
    ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'],
    ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'],
    ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
      'septiembre', 'octubre', 'noviembre', 'diciembre'],
    ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct',
      'nov', 'dic'],
    'Hoy', 'Mañana', 'Ayer', '{wd}, {d} de {m} de {y}',
  ),
  'pt': _DateNames(
    ['Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira',
      'Sexta-feira', 'Sábado', 'Domingo'],
    ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'],
    ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
      'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'],
    ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out',
      'nov', 'dez'],
    'Hoje', 'Amanhã', 'Ontem', '{wd}, {d} de {m} de {y}',
  ),
  'ar': _DateNames(
    ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
    ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'],
    ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس',
      'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'],
    ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس',
      'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'],
    'اليوم', 'غدًا', 'أمس', '{wd}، {d} {m} {y}',
  ),
  'sw': _DateNames(
    ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi',
      'Jumapili'],
    ['Jtatu', 'Jnne', 'Jtano', 'Alh', 'Ijm', 'Jmosi', 'Jpili'],
    ['Januari', 'Februari', 'Machi', 'Aprili', 'Mei', 'Juni', 'Julai',
      'Agosti', 'Septemba', 'Oktoba', 'Novemba', 'Desemba'],
    ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt',
      'Nov', 'Des'],
    'Leo', 'Kesho', 'Jana', '{wd}, {d} {m} {y}',
  ),
};

_DateNames get _n => _names[AppLocale.code] ?? _en;

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String weekdayName(DateTime d) => _n.weekdays[d.weekday - 1];

/// "Saturday, 3 October 2026"
String longDate(DateTime d) => _n.pattern
    .replaceAll('{wd}', weekdayName(d))
    .replaceAll('{d}', '${d.day}')
    .replaceAll('{m}', _n.months[d.month - 1])
    .replaceAll('{y}', '${d.year}');

/// "Sat, 3 Oct"
String shortDate(DateTime d) =>
    '${_n.weekdaysShort[d.weekday - 1]}, ${d.day} ${_n.monthsShort[d.month - 1]}';

int _daysFromToday(DateTime d, DateTime now) =>
    DateTime.utc(d.year, d.month, d.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;

/// Today / Tomorrow / Yesterday, otherwise "Sat, 3 Oct".
String dayLabel(DateTime d, DateTime now) {
  switch (_daysFromToday(d, now)) {
    case 0:
      return _n.today;
    case 1:
      return _n.tomorrow;
    case -1:
      return _n.yesterday;
    default:
      return shortDate(d);
  }
}

String countdownText(Duration d) {
  if (d.isNegative) return '0m';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m ${two(d.inSeconds % 60)}s';
}

/// 1536 -> "1.5 KB", 734003200 -> "700 MB".
String fmtBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

/// "GMT+1", "GMT-5", "GMT+5:30" for the given (local) time.
String gmtOffset(DateTime d) {
  final m = d.timeZoneOffset.inMinutes;
  final sign = m < 0 ? '-' : '+';
  final h = m.abs() ~/ 60;
  final mm = m.abs() % 60;
  return 'GMT$sign$h${mm == 0 ? '' : ':${two(mm)}'}';
}

/// Short zone name for the user's device ("WAT" in Nigeria), or "GMT+1" when
/// the platform only reports an offset.
String tzShort(DateTime d) {
  final n = d.timeZoneName;
  if (n.isNotEmpty && n.length <= 5 && RegExp(r'^[A-Za-z]+$').hasMatch(n)) {
    return n.toUpperCase();
  }
  return gmtOffset(d);
}

/// "09:30 AM" (12-hour clock).
String fmtTime12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${two(h)}:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "05/10/2026" (day/month/year).
String fmtDateNum(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';
