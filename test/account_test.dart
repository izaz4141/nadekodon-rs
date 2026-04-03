import 'package:flutter_test/flutter_test.dart';
import 'package:nadekodon/models/account.dart';

void main() {
  group('Account Model', () {
    test('fromJson and toJson work correctly', () async {
      final json = {
        'host': '1.2.3.4',
        'port': 1234,
        'api_key': 'secret',
        'username': 'user',
        'label': 'My Server',
      };

      final account = await Account.fromJson(json);

      expect(account.host, '1.2.3.4');
      expect(account.port, 1234);
      expect(account.apiKey, 'secret');
      expect(account.username, 'user');
      expect(account.label, 'My Server');

      final toJ = account.toJson();
      expect(toJ['host'], '1.2.3.4');
      expect(toJ['api_key'], 'secret');
    });

    test('defaults are applied', () async {
      final account = await Account.fromJson({});
      expect(account.host, '127.0.0.1');
      expect(account.port, 8080);
      expect(account.username, 'admin');
    });
  });
}
