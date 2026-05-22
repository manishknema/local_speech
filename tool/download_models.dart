import 'dart:io';

Future<void> downloadFile(String url, String savePath) async {
  final file = File(savePath);
  if (await file.exists()) {
    print('File already exists: $savePath. Skipping...');
    return;
  }

  print('Downloading $url...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode == 200) {
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      print('Saved to $savePath');
    } else if (response.statusCode == 301 || response.statusCode == 302) {
      final location = response.headers.value('location');
      if (location != null) {
        print('Redirecting to $location...');
        await downloadFile(location, savePath);
      }
    } else {
      print('Failed to download file. Status code: ${response.statusCode}');
    }
  } catch (e) {
    print('Error downloading file: $e');
  } finally {
    client.close();
  }
}

void main() async {
  final modelsDir = Directory('assets/models');
  if (!await modelsDir.exists()) {
    await modelsDir.create(recursive: true);
  }

  // Silero VAD v4 (Official latest)
  const vadUrl = 'https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx';
  // Meta MMS-LID (Xenova Quantized)
  const lidUrl = 'https://huggingface.co/Xenova/mms-lid-126/resolve/main/onnx/model_quantized.onnx';
  // WeSpeaker VoxCeleb ResNet34 (High-quality public URL)
  const speakerUrl = 'https://huggingface.co/Wespeaker/wespeaker-voxceleb-resnet34-LM/resolve/main/voxceleb_resnet34_LM.onnx';

  await downloadFile(vadUrl, 'assets/models/silero_vad.onnx');
  await downloadFile(lidUrl, 'assets/models/mms_lid.onnx');
  await downloadFile(speakerUrl, 'assets/models/speaker_embed.onnx');

  print('All models downloaded successfully.');
}
