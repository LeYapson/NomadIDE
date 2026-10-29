package dev.nomadmcu.nomad_mcu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var picoboot: PicobootUsb? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Accès USB brut pour écrire un RP2040 en BOOTSEL (voir PicobootUsb).
        picoboot = PicobootUsb(this, flutterEngine)
    }
}
