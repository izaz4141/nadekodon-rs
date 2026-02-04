class Account {
  final String host;
  final int port;
  final String apiKey;
  final String username;
  final String label;

  Account({
    required this.host,
    required this.port,
    required this.apiKey,
    required this.username,
    String? label,
  }) : label = label ?? host;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      host: json['host'] ?? '127.0.0.1',
      port: json['port'] ?? 8080,
      apiKey: json['api_key'] ?? '',
      username: json['username'] ?? 'admin',
      label: json['label'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'api_key': apiKey,
      'username': username,
      'label': label,
    };
  }
}
