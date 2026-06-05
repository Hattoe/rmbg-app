import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

void main() {
  runApp(const RMBGApp());
}

class RMBGApp extends StatelessWidget {
  const RMBGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Background Remover',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.rmbg.app/background_removal');

  File? _originalImage;
  Uint8List? _resultBytes;
  bool _isProcessing = false;
  String? _errorMessage;

  Future<void> _pickAndProcess() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      _originalImage = File(picked.path);
      _resultBytes = null;
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final imageBytes = await _originalImage!.readAsBytes();
      final result = await _channel.invokeMethod('removeBackground', {
        'imageBytes': imageBytes,
      });
      setState(() {
        _resultBytes = (result as Uint8List);
        _isProcessing = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Background Remover'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (_originalImage != null)
              Expanded(
                child: Column(
                  children: [
                    const Text('Original', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Image.file(_originalImage!)),
                  ],
                ),
              ),
            if (_resultBytes != null)
              Expanded(
                child: Column(
                  children: [
                    const Text('Background Removed', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          image: const DecorationImage(
                            image: AssetImage('assets/checkerboard.png'),
                            repeat: ImageRepeat.repeat,
                          ),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Image.memory(_resultBytes!, fit: BoxFit.contain),
                      ),
                    ),
                  ],
                ),
              ),
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Removing background...'),
                  ],
                ),
              ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Error: $_errorMessage',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndProcess,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Image'),
            ),
          ],
        ),
      ),
    );
  }
}