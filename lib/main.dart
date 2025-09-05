import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FRPC Flutter Demo',
      theme: ThemeData.dark(),
      home: const FrpcHome(),
    );
  }
}

class FrpcHome extends StatefulWidget {
  const FrpcHome({super.key});

  @override
  State<FrpcHome> createState() => _FrpcHomeState();
}

class _FrpcHomeState extends State<FrpcHome> {
  String _log = "";
  Process? _process;
  String? _frpcPath;
  String? _configPath;
  final TextEditingController _configController = TextEditingController();
  bool _isInitialized = false;
  static const _platform = MethodChannel("frpc_path");

  @override
  void initState() {
    super.initState();
    _prepareFrpc();
  }

  @override
  void dispose() {
    _configController.dispose();
    _stopFrpc();
    super.dispose();
  }

  Future<void> _prepareFrpc() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _appendLog("Using directory: ${dir.path}");

      // Ask native side for FRPC binary path
      final nativePath = await _platform.invokeMethod<String>("getFrpcPath");
      if (nativePath == null) throw Exception("FRPC path not found");
      _appendLog("FRPC binary located at: $nativePath");

      // Add binary check here
      _appendLog("Checking FRPC binary...");
      final file = File(nativePath);
      final exists = await file.exists();
      _appendLog("FRPC exists: $exists");
      if (exists) {
        final stat = await file.stat();
        _appendLog("FRPC size: ${stat.size} bytes");
        _appendLog("FRPC mode: ${stat.mode}");
      }

      // Copy config
      final configFile = File('${dir.path}/frpc.ini');
      if (!await configFile.exists()) {
        _appendLog("Copying config file...");
        final cfg = await rootBundle.loadString('assets/frpc.ini');
        await configFile.writeAsString(cfg, flush: true);
      } else {
        _appendLog("Config file already exists");
      }

      _configController.text = await configFile.readAsString();

      setState(() {
        _frpcPath = nativePath;
        _configPath = configFile.path;
        _isInitialized = true;
      });

      _appendLog("Initialization complete");
      _appendLog("FRPC path: $_frpcPath");
      _appendLog("Config path: $_configPath");
    } catch (e) {
      _appendLog("Error during initialization: $e");
    }
  }

  Future<void> _checkFilePermissions(String filePath, String context) async {
    try {
      _appendLog("=== File permissions check ($context) ===");

      // Method 1: Using ls -l to get detailed permissions
      try {
        final lsResult = await Process.run('ls', ['-l', filePath]);
        if (lsResult.exitCode == 0) {
          _appendLog("ls -l output: ${lsResult.stdout.toString().trim()}");
        } else {
          _appendLog("ls -l failed: ${lsResult.stderr}");
        }
      } catch (e) {
        _appendLog("ls command failed: $e");
      }

      // Method 2: Using stat command for numeric permissions
      try {
        final statResult = await Process.run('stat', ['-c', '%a %n', filePath]);
        if (statResult.exitCode == 0) {
          _appendLog(
            "stat permissions: ${statResult.stdout.toString().trim()}",
          );
        } else {
          _appendLog("stat failed: ${statResult.stderr}");
        }
      } catch (e) {
        _appendLog("stat command failed: $e");
      }

      // Method 3: Check if file exists and basic info
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        _appendLog("File exists: true, Size: ${stat.size} bytes");
        _appendLog("File type: ${stat.type}");
        _appendLog("Modified: ${stat.modified}");
      } else {
        _appendLog("File exists: false");
      }

      _appendLog("=== End permissions check ===");
    } catch (e) {
      _appendLog("Permission check failed: $e");
    }
  }

  Future<void> _runFrpc() async {
    if (_process != null) {
      _appendLog("FRPC already running.");
      return;
    }
    if (_frpcPath == null || _configPath == null) {
      _appendLog("FRPC not initialized properly.");
      return;
    }

    try {
      _appendLog("Starting FRPC...");
      _appendLog("Command: $_frpcPath -c $_configPath");

      // Check if binary exists and is executable
      final frpcFile = File(_frpcPath!);
      if (!await frpcFile.exists()) {
        _appendLog("ERROR: FRPC binary not found at $_frpcPath");
        return;
      }

      // Try to get file stats
      final stat = await frpcFile.stat();
      _appendLog("File size: ${stat.size} bytes");

      // Final permission check before running
      await _checkFilePermissions(_frpcPath!, "Before execution");

      _process = await Process.start(_frpcPath!, ['-c', _configPath!]);

      _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
        _appendLog(data);
      });

      _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
        _appendLog("[ERR] $data");
      });

      _process!.exitCode.then((code) {
        _appendLog("FRPC exited with code $code");
        setState(() {
          _process = null;
        });
      });
    } catch (e) {
      _appendLog("Error starting FRPC: $e");
      setState(() {
        _process = null;
      });
    }
  }

  Future<void> _stopFrpc() async {
    if (_process != null) {
      _appendLog("Stopping FRPC...");
      try {
        _process!.kill(ProcessSignal.sigterm);
        // Wait a moment, then force kill if needed
        await Future.delayed(const Duration(seconds: 2));
        if (_process != null) {
          _process!.kill(ProcessSignal.sigkill);
        }
      } catch (e) {
        _appendLog("Error stopping FRPC: $e");
      }
      _process = null;
    }
  }

  Future<void> _saveConfig() async {
    if (_configPath != null) {
      try {
        await File(
          _configPath!,
        ).writeAsString(_configController.text, flush: true);
        _appendLog("Config saved successfully.");
      } catch (e) {
        _appendLog("Error saving config: $e");
      }
    }
  }

  void _clearLog() {
    setState(() {
      _log = "";
    });
  }

  void _appendLog(String msg) {
    setState(() {
      final timestamp = DateTime.now().toString().substring(11, 19);
      _log += "[$timestamp] ${msg.trim()}\n";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FRPC Runner"),
        actions: [
          IconButton(
            onPressed: _clearLog,
            icon: const Icon(Icons.clear),
            tooltip: "Clear Log",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Config editor
            Expanded(
              child: TextField(
                controller: _configController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "FRPC Config (frpc.ini)",
                ),
                style: const TextStyle(fontFamily: "monospace", fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),

            // Control buttons
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isInitialized ? _saveConfig : null,
                  child: const Text("Save Config"),
                ),
                ElevatedButton(
                  onPressed: _isInitialized && _process == null
                      ? _runFrpc
                      : null,
                  child: const Text("Run"),
                ),
                ElevatedButton(
                  onPressed: _process != null ? _stopFrpc : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                  child: const Text("Stop"),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _process != null
                    ? Colors.green.shade800
                    : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _process != null ? "Running" : "Stopped",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Log output
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  reverse: true, // Auto-scroll to bottom
                  child: SelectableText(
                    _log.isEmpty ? "No logs yet..." : _log,
                    style: const TextStyle(
                      fontFamily: "monospace",
                      fontSize: 11,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
