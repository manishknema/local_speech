import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _SetDllDirectoryNative = Int32 Function(Pointer<Utf16> lpPathName);
typedef _SetDllDirectoryDart = int Function(Pointer<Utf16> lpPathName);

void setWindowsDllDirectory(String path) {
  if (!Platform.isWindows) {
    return;
  }

  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final setDllDirectory = kernel32.lookupFunction<
      _SetDllDirectoryNative,
      _SetDllDirectoryDart>('SetDllDirectoryW');

  final widePath = path.toNativeUtf16();
  try {
    final result = setDllDirectory(widePath);
    if (result == 0) {
      throw const OSError('SetDllDirectoryW failed');
    }
  } finally {
    calloc.free(widePath);
  }
}
