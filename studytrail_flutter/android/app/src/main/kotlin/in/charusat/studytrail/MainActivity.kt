package `in`.charusat.studytrail

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val calendar = CalendarChannel(this)
    private val focus by lazy { FocusNotice(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        calendar.attach(flutterEngine.dartExecutor.binaryMessenger)
        focus.attach(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        focus.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // The focus notification was tapped while the app was open behind it.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(FocusNotice.EXTRA_TAP, false)) focus.onTap()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        calendar.onPermissionResult(requestCode, grantResults)
    }
}
