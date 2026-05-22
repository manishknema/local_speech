import 'dart:typed_data';

/// Base interface for all ONNX model processors in the pipeline.
abstract class OnnxProcessor<InputType, OutputType> {
  /// Loads the `.onnx` model into memory and initializes the session.
  Future<void> loadModel();

  /// Performs inference on the given input and returns the typed output.
  Future<OutputType> infer(InputType input);
  
  /// Releases the ONNX session and frees native resources.
  void dispose();
}
