import 'file_association/base.dart';
import 'file_association/stub.dart'
    if (dart.library.io) 'file_association/native.dart'
    if (dart.library.js_interop) 'file_association/wasm.dart';

export 'file_association/base.dart';

class FileAssociationServiceFactory {
  static FileAssociationService create() => getFileAssociationService();
}
