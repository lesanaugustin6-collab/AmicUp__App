import 'dart:typed_data';

class ImageModerationService {
  const ImageModerationService._();

  static Future<bool> validateImage(List<int> bytes) async {
    if (bytes.isEmpty) return false;

    final sizeInBytes = bytes.length;
    if (sizeInBytes > 8 * 1024 * 1024) {
      return false;
    }

    final header = Uint8List.fromList(bytes).sublist(0, bytes.length < 12 ? bytes.length : 12);
    final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final jpgHeader = [0xFF, 0xD8, 0xFF];
    final webpHeader = [0x52, 0x49, 0x46, 0x46];

    final isPng = header.length >= pngHeader.length &&
        List<int>.generate(pngHeader.length, (index) => header[index]).asMap().entries.every(
          (entry) => entry.value == pngHeader[entry.key],
        );

    final isJpg = header.length >= jpgHeader.length &&
        List<int>.generate(jpgHeader.length, (index) => header[index]).asMap().entries.every(
          (entry) => entry.value == jpgHeader[entry.key],
        );

    final isWebp = header.length >= webpHeader.length &&
        header[0] == webpHeader[0] &&
        header[1] == webpHeader[1] &&
        header[2] == webpHeader[2] &&
        header[3] == webpHeader[3];

    if (!isPng && !isJpg && !isWebp) {
      return false;
    }

    return true;
  }
}
