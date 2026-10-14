package com.potv.potv

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterFragmentActivity() {
    private val updateChannel = "com.potv.potv/update_center"
    private val preloadChannel = "potv/media3_preload"

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    private fun signingDigests(info: PackageInfo): Set<String> {
        val signatures =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = info.signingInfo ?: return emptySet()
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                info.signatures
            }
        return signatures
            ?.map { signature ->
                MessageDigest
                    .getInstance("SHA-256")
                    .digest(signature.toByteArray())
                    .joinToString("") { "%02x".format(it) }
            }
            ?.toSet()
            ?: emptySet()
    }

    private fun resolveUpdateApk(rawPath: String?): File? {
        if (rawPath.isNullOrBlank()) return null
        val selected = File(rawPath).canonicalFile
        val allowedDirectory = File(cacheDir, "potv-updates").canonicalFile
        return if (
            selected.parentFile?.canonicalFile == allowedDirectory &&
            selected.name == "potv-update.apk" &&
            selected.isFile &&
            selected.length() >= 1024L
        ) {
            selected
        } else {
            null
        }
    }

    private fun validateUpdateApk(selected: File): Map<String, Any?> {
        val signingFlags =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }
        val archive =
            packageManager.getPackageArchiveInfo(selected.path, signingFlags)
                ?: return mapOf(
                    "ok" to false,
                    "code" to "INVALID_APK",
                    "message" to "Android no reconoce el archivo como una APK válida.",
                )
        if (archive.packageName != packageName) {
            return mapOf(
                "ok" to false,
                "code" to "PACKAGE_MISMATCH",
                "message" to "La actualización no pertenece a POTV.",
            )
        }

        @Suppress("DEPRECATION")
        val installed = packageManager.getPackageInfo(packageName, signingFlags)
        val installedCode = versionCode(installed)
        val candidateCode = versionCode(archive)
        if (candidateCode <= installedCode) {
            return mapOf(
                "ok" to false,
                "code" to "VERSION_NOT_NEWER",
                "message" to "La APK no es más reciente que la versión instalada.",
                "installedCode" to installedCode,
                "candidateCode" to candidateCode,
            )
        }

        val installedSigners = signingDigests(installed)
        val candidateSigners = signingDigests(archive)
        if (
            installedSigners.isEmpty() ||
            candidateSigners.isEmpty() ||
            installedSigners.intersect(candidateSigners).isEmpty()
        ) {
            return mapOf(
                "ok" to false,
                "code" to "SIGNATURE_MISMATCH",
                "message" to "La APK fue firmada con un certificado diferente.",
                "installedCode" to installedCode,
                "candidateCode" to candidateCode,
            )
        }

        return mapOf(
            "ok" to true,
            "code" to "OK",
            "message" to "APK compatible con esta instalación de POTV.",
            "installedCode" to installedCode,
            "candidateCode" to candidateCode,
            "candidateName" to (archive.versionName ?: ""),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "potv/media3_cast_player",
            Media3CastPlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            preloadChannel,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "preload" -> {
                        val uri = call.argument<String>("uri").orEmpty()
                        val title = call.argument<String>("title").orEmpty()
                        val subtitles = call.argument<List<Map<String, Any?>>>("subtitles")
                        val loaded =
                            PotvMedia3Preload.preload(
                                this,
                                uri,
                                title,
                                subtitles,
                            )
                        result.success(loaded)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error(
                    "PRELOAD_ERROR",
                    error.message ?: "No se pudo precargar el contenido.",
                    null,
                )
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannel,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "installedVersion" -> {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = versionCode(info)
                        result.success(
                            mapOf(
                                "name" to (info.versionName ?: "0.0.0"),
                                "code" to code.toInt(),
                            ),
                        )
                    }
                    "canInstallPackages" -> {
                        val allowed =
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                        result.success(allowed)
                    }
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent =
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                )
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    "validateInstallPackage" -> {
                        val selected = resolveUpdateApk(call.argument<String>("path"))
                        if (selected == null) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "code" to "INVALID_APK",
                                    "message" to "La APK no está en la carpeta segura de POTV.",
                                ),
                            )
                            return@setMethodCallHandler
                        }
                        result.success(validateUpdateApk(selected))
                    }
                    "requestInstall" -> {
                        if (
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                        ) {
                            result.error(
                                "INSTALL_PERMISSION",
                                "Autoriza la instalación para POTV.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        val selected = resolveUpdateApk(call.argument<String>("path"))
                        if (selected == null) {
                            result.error(
                                "INVALID_APK",
                                "La APK descargada no está en la carpeta segura.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        val validation = validateUpdateApk(selected)
                        if (validation["ok"] != true) {
                            result.error(
                                validation["code"] as? String ?: "INVALID_APK",
                                validation["message"] as? String
                                    ?: "La APK no es compatible con esta instalación.",
                                validation,
                            )
                            return@setMethodCallHandler
                        }
                        val uri =
                            FileProvider.getUriForFile(
                                this,
                                "$packageName.updates",
                                selected,
                            )
                        val intent =
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(
                                    uri,
                                    "application/vnd.android.package-archive",
                                )
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error(
                    "UPDATE_CENTER_ERROR",
                    error.message ?: "Error del instalador.",
                    null,
                )
            }
        }
    }
}
