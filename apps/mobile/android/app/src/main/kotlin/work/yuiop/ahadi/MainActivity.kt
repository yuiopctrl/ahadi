package work.yuiop.ahadi

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "work.yuiop.ahadi/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val mimeType = call.argument<String>("mimeType") ?: "image/png"
                val title = call.argument<String>("title") ?: "Share"
                if (path.isNullOrBlank()) {
                    result.error("INVALID_INPUT", "Missing image path", null)
                    return@setMethodCallHandler
                }
                val file = File(path)
                val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = mimeType
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(intent, title))
                result.success(null)
            }
    }
}
