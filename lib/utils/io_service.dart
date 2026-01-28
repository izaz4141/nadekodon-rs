import 'src/io_service_base.dart';
import 'src/io_service_stub.dart'
    if (dart.library.io) 'src/io_service_native.dart'
    if (dart.library.js_interop) 'src/io_service_wasm.dart';

export 'src/io_service_base.dart';

class IOServiceFactory {
  static IOService create() => getIOService();
}
