package com.potv.potv

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "com.potv.potv/update_center"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installedVersion" -> {
                            @Suppress("DEPRECATION")
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                info.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                info.versionCode.toLong()
                            }
                            result.success(mapOf(
                                "name" to (info.versionName ?: "0.0.0"),
                                "code" to code.toInt(),
                            ))
                        }
                        "canInstallPackages" -> {
                            val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                            result.success(allowed)
                        }
                        "openInstallSettings" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(intent)
                            }
                            result.success(null)
                        }
                        "requestInstall" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()) {
                                result.error("INSTALL_PERMISSION", "Autoriza la instalación para POTV.", null)
                                return@setMethodCallHandler
                            }

                            val rawPath = call.argument<String>("path")
                            if (rawPath.isNullOrBlank()) {
                                result.error("INVALID_PATH", "Archivo APK no encontrado.", null)
                                return@setMethodCallHandler
                            }
                            val selected = File(rawPath).canonicalFile
                            val allowedDirectory = File(cacheDir, "potv-updates").canonicalFile
                            if (selected.parentFile != allowedDirectory ||
                                selected.name != "potv-update.apk" ||
                                !selected.isFile ||
                                selected.length() < 1024L) {
                                result.error("INVALID_APK", "La APK descargada no está en la carpeta segura.", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.updates",
                                selected
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("UPDATE_CENTER_ERROR", error.message ?: "Error del instalador.", null)
                }
            }
    }
}
