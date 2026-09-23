import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _time = DateFormat('h:mm a');
  static final _day = DateFormat('d MMM');
  static final _weekday = DateFormat('EEE');

  static String percent(double p, {int decimals = 1}) => '${(p * 100).toStringAsFixed(decimals)}%';

  static String ms(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(2)} s' : '${v.toStringAsFixed(0)} ms';

  static String dateTime(DateTime? dt) => dt == null ? '—' : _dateTime.format(dt.toLocal());

  static String day(DateTime dt) => _day.format(dt.toLocal());

  static String weekday(DateTime dt) => _weekday.format(dt.toLocal());

  static String relative(DateTime? dt) {
    if (dt == null) return 'never';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && now.day == local.day) return 'today, ${_time.format(local)}';
    if (diff.inHours < 48) return 'yesterday, ${_time.format(local)}';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return _dateTime.format(local);
  }

  static String plural(int n, String one, [String? many]) => n == 1 ? '$n $one' : '$n ${many ?? '${one}s'}';
}
