import 'base.dart';

/// Dart has no file association concept on the web, and no way to reach the
/// host to register one.
FileAssociationService getFileAssociationService() =>
    throw UnsupportedError('Cannot create FileAssociationService');
