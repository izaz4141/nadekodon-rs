package id.glicole.nadekodon

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {
    private val CHANNEL = "id.glicole.nadekodon/ytdlp"
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ytdlpExtractInfo") {
                val url = call.argument<String>("url")
                if (url != null) {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val python = Python.getInstance()
                            val ytdlpModule = python.getModule("ytdlp_wrapper")
                            val jsonResult = ytdlpModule.callAttr("run_ytdlp", url).toString()
                            
                            withContext(Dispatchers.Main) {
                                result.success(jsonResult)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("PYTHON_ERROR", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "URL is required", null)
                }
            } else if (call.method == "ytdlpDownload") {
                val url = call.argument<String>("url")
                val options = call.argument<String>("options")
                val id = call.argument<String>("id")

                if (url != null && options != null && id != null) {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val python = Python.getInstance()
                            val ytdlpModule = python.getModule("ytdlp_wrapper")
                            
                            val callback = object {
                                fun onProgress(jsonProgress: String) {
                                    CoroutineScope(Dispatchers.Main).launch {
                                        channel.invokeMethod("onProgress", mapOf("id" to id, "data" to jsonProgress))
                                    }
                                }
                            }

                            val jsonResult = ytdlpModule.callAttr("download_video", url, options, callback).toString()
                            
                            withContext(Dispatchers.Main) {
                                result.success(jsonResult)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("PYTHON_ERROR", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "URL, options, and ID are required", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
