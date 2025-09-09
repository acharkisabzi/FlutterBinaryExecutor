import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

String packageInfo = '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _getAppInfo();
  runApp(const MyApp());
}

Future<void> _getAppInfo() async {
  final Info = await PackageInfo.fromPlatform();
  packageInfo = Info.packageName;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Binary Executor Demo',
      theme: ThemeData.dark(),
      home: const BinaryExecutorHome(),
    );
  }
}

class BinaryExecutorHome extends StatefulWidget {
  const BinaryExecutorHome({super.key});

  @override
  State<BinaryExecutorHome> createState() => _BinaryExecutorHomeState();
}

class _BinaryExecutorHomeState extends State<BinaryExecutorHome> {
  // =============================================================================
  // CONFIGURATION SECTION - Modify these variables for your specific use case
  // =============================================================================

  // Your app's package name, No need to set it here, the value is automatically set later.

  // Name of the binary file to execute (without path)
  //MAKE SURE TO ADD YOUR BINARY FILES IN android/app/src/main/jniLibs/<your_device_architecture>/<your_binary_file.so>
  static const String binaryFileName = 'libfrpc.so';

  // Name of the config file in assets and app documents
  static const String configFileName = 'frpc.ini';

  // Command line arguments template (use {configPath} placeholder)
  //MAKE SURE TO ADD YOUR CONFIG FILES IN ASSETS FOLDER
  static const List<String> commandArguments = ['-c', '{configPath}'];

  // Display name for UI
  static const String appDisplayName = 'FRPC';

  // =============================================================================
  // END CONFIGURATION SECTION
  // =============================================================================

  String _log = "";
  Process? _process;
  String? _binaryPath;
  String? _configPath;
  final TextEditingController _configController = TextEditingController();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeBinary();
  }

  @override
  void dispose() {
    _configController.dispose();
    _stopBinary();
    super.dispose();
  }

  Future<void> _initializeBinary() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _appendLog("Using directory: ${dir.path}");

      _appendLog("Locating $binaryFileName binary...");
      String? binaryPath = await _findBinary();

      if (binaryPath == null) {
        throw Exception("Could not locate $binaryFileName binary");
      }

      _appendLog("$binaryFileName binary located at: $binaryPath");

      // Verify binary exists and get metadata
      final file = File(binaryPath);
      final exists = await file.exists();
      _appendLog("$binaryFileName exists: $exists");
      if (exists) {
        final stat = await file.stat();
        _appendLog("$binaryFileName size: ${stat.size} bytes");
        _appendLog("$binaryFileName mode: ${stat.mode}");
      }

      // Setup config file
      final configFile = File('${dir.path}/$configFileName');
      if (!await configFile.exists()) {
        _appendLog("Copying config file from assets...");
        try {
          final cfg = await rootBundle.loadString('assets/$configFileName');
          await configFile.writeAsString(cfg, flush: true);
        } catch (e) {
          _appendLog("Warning: Could not load config from assets: $e");
          // Create a default empty config
          await configFile.writeAsString('# Default config\n', flush: true);
        }
      } else {
        _appendLog("Config file already exists");
      }

      _configController.text = await configFile.readAsString();

      setState(() {
        _binaryPath = binaryPath;
        _configPath = configFile.path;
        _isInitialized = true;
      });

      _appendLog("Initialization complete");
      _appendLog("Binary path: $_binaryPath");
      _appendLog("Config path: $_configPath");
    } catch (e) {
      _appendLog("Error during initialization: $e");
    }
  }

  /// Generic binary finder that works with any package name and binary name
  Future<String?> _findBinary() async {
    try {
      final mapsFile = File('/proc/self/maps');
      if (!await mapsFile.exists()) {
        _appendLog("/proc/self/maps not found");
        return null;
      }

      final content = await mapsFile.readAsString();
      final lines = content.split('\n');

      for (final line in lines) {
        if (line.contains(packageInfo) && line.contains('.so')) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            final potentialPath = parts.last;
            if (potentialPath.contains('/lib/') &&
                potentialPath.endsWith('.so')) {
              final dir = Directory(potentialPath).parent;
              final targetBinaryPath = '${dir.path}/$binaryFileName';
              if (await File(targetBinaryPath).exists()) {
                _appendLog("Found via /proc/self/maps: $targetBinaryPath");
                return targetBinaryPath;
              }
            }
          }
        }
      }

      _appendLog("$binaryFileName not found in memory maps");
      return null;
    } catch (e) {
      _appendLog("Error finding binary: $e");
      return null;
    }
  }

  Future<void> _checkFilePermissions(String filePath, String context) async {
    try {
      _appendLog("=== File permissions check ($context) ===");

      // Using ls -l for detailed permissions
      try {
        final lsResult = await Process.run('ls', ['-l', filePath]);
        if (lsResult.exitCode == 0) {
          _appendLog("ls -l: ${lsResult.stdout.toString().trim()}");
        } else {
          _appendLog("ls -l failed: ${lsResult.stderr}");
        }
      } catch (e) {
        _appendLog("ls command failed: $e");
      }

      // Using stat for numeric permissions
      try {
        final statResult = await Process.run('stat', ['-c', '%a %n', filePath]);
        if (statResult.exitCode == 0) {
          _appendLog("stat: ${statResult.stdout.toString().trim()}");
        } else {
          _appendLog("stat failed: ${statResult.stderr}");
        }
      } catch (e) {
        _appendLog("stat command failed: $e");
      }

      // Flutter File API metadata
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

  /// Generic method to build command arguments with placeholder replacement
  List<String> _buildCommandArguments() {
    return commandArguments.map((arg) {
      return arg.replaceAll('{configPath}', _configPath ?? '');
    }).toList();
  }

  Future<void> _runBinary() async {
    if (_process != null) {
      _appendLog("$appDisplayName already running.");
      return;
    }
    if (_binaryPath == null || _configPath == null) {
      _appendLog("$appDisplayName not initialized properly.");
      return;
    }

    try {
      final args = _buildCommandArguments();
      _appendLog("Starting $appDisplayName...");
      _appendLog("Command: $_binaryPath ${args.join(' ')}");

      // Verify binary exists
      final binaryFile = File(_binaryPath!);
      if (!await binaryFile.exists()) {
        _appendLog("ERROR: Binary not found at $_binaryPath");
        return;
      }

      // Get file metadata
      final stat = await binaryFile.stat();
      _appendLog("File size: ${stat.size} bytes");

      // Permission check before execution
      await _checkFilePermissions(_binaryPath!, "Before execution");

      // Start the process
      _process = await Process.start(_binaryPath!, args);

      _process!.stdout.transform(const SystemEncoding().decoder).listen((data) {
        _appendLog(data);
      });

      _process!.stderr.transform(const SystemEncoding().decoder).listen((data) {
        _appendLog("[ERR] $data");
      });

      _process!.exitCode.then((code) {
        _appendLog("$appDisplayName exited with code $code");
        setState(() {
          _process = null;
        });
      });
    } catch (e) {
      _appendLog("Error starting $appDisplayName: $e");
      setState(() {
        _process = null;
      });
    }
  }

  Future<void> _stopBinary() async {
    if (_process != null) {
      _appendLog("Stopping $appDisplayName...");
      try {
        _process!.kill(ProcessSignal.sigterm);
        await Future.delayed(const Duration(seconds: 2));
        if (_process != null) {
          _process!.kill(ProcessSignal.sigkill);
        }
      } catch (e) {
        _appendLog("Error stopping $appDisplayName: $e");
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

  Future<void> _testDirectoryWritability() async {
    if (_binaryPath != null) {
      final binaryDir = Directory(_binaryPath!).parent.path;
      try {
        final testFile = File('$binaryDir/write_test.tmp');
        await testFile.writeAsString('test');
        await testFile.delete();
        _appendLog("✅ Binary directory is writable");
      } catch (e) {
        _appendLog("❌ Binary directory is not writable: $e");
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
        title: Text("$appDisplayName Runner"),
        actions: [
          IconButton(
            onPressed: _clearLog,
            icon: const Icon(Icons.clear),
            tooltip: "Clear Log",
          ),
          if (_isInitialized)
            IconButton(
              onPressed: _testDirectoryWritability,
              icon: const Icon(Icons.folder_open),
              tooltip: "Test Directory Writability",
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Configuration info banner
            if (_isInitialized)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade800.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade600),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Configuration",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade200,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Package: $packageInfo\nBinary: $binaryFileName\nConfig: $configFileName",
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: "monospace",
                      ),
                    ),
                  ],
                ),
              ),

            // Config editor
            Expanded(
              flex: 2,
              child: TextField(
                controller: _configController,
                maxLines: null,
                expands: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "$appDisplayName Config ($configFileName)",
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
                      ? _runBinary
                      : null,
                  child: const Text("Run"),
                ),
                ElevatedButton(
                  onPressed: _process != null ? _stopBinary : null,
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
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    _log.isEmpty ? "No logs yet..." : _log,
                    style: const TextStyle(
                      fontFamily: "monospace",
                      fontSize: 7,
                      height: 1.2,
                      color: Colors.green,
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
