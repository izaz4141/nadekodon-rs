/// Offers this build as a handler for `.torrent` files and magnet links.
///
/// Every platform offers its own mechanism, so this is a contract rather than
/// an implementation. Use `FileAssociationServiceFactory.create()` to obtain
/// one.
abstract class FileAssociationService {
  /// Whether this build is currently registered to handle the formats.
  bool isRegistered();

  /// Adds this build to the list of programs the OS offers for the formats.
  Future<void> register();
}
