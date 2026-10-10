package com.anugerahsurya.laporyuk

import android.graphics.Bitmap
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lapor_sur/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "externalRoot" -> result.success(Environment.getExternalStorageDirectory().absolutePath)
                "hasAllFilesAccess" -> result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) Environment.isExternalStorageManager() else true
                )
                "scanFiles" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    if (paths.isNotEmpty()) MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
                    result.success(null)
                }
                "saveJpeg" -> {
                    // Runs off the UI thread: encoding a full frame takes a moment.
                    Thread {
                        try {
                            saveJpeg(
                                call.argument<ByteArray>("rgba")!!,
                                call.argument<Int>("width")!!,
                                call.argument<Int>("height")!!,
                                call.argument<String>("path")!!,
                                call.argument<Int>("quality") ?: 90,
                                call.argument<Double>("lat"),
                                call.argument<Double>("lng"),
                                call.argument<Long>("timeMillis"),
                            )
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("JPEG", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveJpeg(
        rgba: ByteArray, width: Int, height: Int, path: String, quality: Int,
        lat: Double?, lng: Double?, timeMillis: Long?,
    ) {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bmp.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
        File(path).parentFile?.mkdirs()
        FileOutputStream(path).use { bmp.compress(Bitmap.CompressFormat.JPEG, quality, it) }
        bmp.recycle()

        val exif = ExifInterface(path)
        if (lat != null && lng != null) {
            exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE, toDms(lat))
            exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, if (lat >= 0) "N" else "S")
            exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE, toDms(lng))
            exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, if (lng >= 0) "E" else "W")
        }
        if (timeMillis != null) {
            val stamp = SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).format(Date(timeMillis))
            exif.setAttribute(ExifInterface.TAG_DATETIME, stamp)
            exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, stamp)
        }
        exif.setAttribute(ExifInterface.TAG_SOFTWARE, "Lapor Yuk")
        exif.saveAttributes()
    }

    /** Decimal degrees -> EXIF rational "d/1,m/1,s/10000". */
    private fun toDms(value: Double): String {
        var v = Math.abs(value)
        val d = v.toInt()
        v = (v - d) * 60
        val m = v.toInt()
        val s = Math.round((v - m) * 60 * 10000)
        return "$d/1,$m/1,$s/10000"
    }
}
