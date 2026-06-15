import 'dart:typed_data';

class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
}

class File {
  final String path;
  File(this.path);

  Future<bool> exists() async => false;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
}
