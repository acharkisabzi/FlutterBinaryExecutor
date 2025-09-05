package com.example.abcdmdrchd

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.annotation.NonNull
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "frpc_path"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFrpcPath" -> {
                    try {
                        // Get the native library directory
                        val nativeLibDir = applicationInfo.nativeLibraryDir
                        println("Debug: Native lib dir = $nativeLibDir")
                        
                        // List all files in the directory
                        val directory = File(nativeLibDir)
                        val files = directory.listFiles()
                        println("Debug: Files in $nativeLibDir:")
                        files?.forEach { file ->
                            println("Debug: - ${file.name} (${file.length()} bytes)")
                        }

                        val frpcPath = "$nativeLibDir/libfrpc.so"
                        val frpcFile = File(frpcPath)
                        
                        if (!frpcFile.exists()) {
                            val error = "FRPC binary not found at $frpcPath\n" +
                                      "Directory contents: ${files?.joinToString(", ") { it.name } ?: "empty"}"
                            println("Debug: $error")
                            result.error("FILE_ERROR", error, null)
                            return@setMethodCallHandler
                        }

                        // Make sure the file is readable and executable
                        if (!frpcFile.canRead() || !frpcFile.canExecute()) {
                            frpcFile.setReadable(true)
                            frpcFile.setExecutable(true)
                        }

                        println("Debug: Found FRPC at $frpcPath (${frpcFile.length()} bytes)")
                        result.success(frpcPath)
                        
                    } catch (e: Exception) {
                        println("Debug: Exception: ${e.message}")
                        e.printStackTrace()
                        result.error("ERROR", "Failed to get FRPC path: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}