import 'package:web/web.dart';
import 'package:nadekodon/utils/logger.dart';

class CookieService {
  static void setCookie(String name, String value, {int days = 30}) {
    try {
      final expires = DateTime.now().add(Duration(days: days));

      final cookieStr =
          '$name=${Uri.encodeComponent(value)}; '
          'expires=${_formatHttpDate(expires)}; '
          'path=/; '
          'SameSite=Strict';

      document.cookie = cookieStr;
    } catch (e) {
      log('Error setting cookie: $e', isError: true);
    }
  }

  static String? getCookie(String name) {
    try {
      final cookies = document.cookie;
      if (cookies.isEmpty) return null;

      for (final part in cookies.split('; ')) {
        final idx = part.indexOf('=');
        if (idx == -1) continue;

        final key = part.substring(0, idx);
        if (key != name) continue;

        final value = part.substring(idx + 1);
        return Uri.decodeComponent(value);
      }
    } catch (e) {
      log('Error getting cookie: $e', isError: true);
    }
    return null;
  }

  static void deleteCookie(String name) {
    try {
      document.cookie = '$name=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
    } catch (e) {
      log('Error deleting cookie: $e', isError: true);
    }
  }
}

/// Formats a DateTime as an RFC 1123 HTTP-date (GMT),
/// suitable for use in cookies.
String _formatHttpDate(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  final d = date.toUtc();

  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekdays[d.weekday - 1]}, '
      '${two(d.day)} ${months[d.month - 1]} ${d.year} '
      '${two(d.hour)}:${two(d.minute)}:${two(d.second)} GMT';
}
