package dev.nomadmcu.nomad_mcu

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Accès USB brut à l'interface PICOBOOT d'un RP2040 en mode BOOTSEL (VID 0x2E8A, PID 0x0003).
 *
 * En BOOTSEL, la puce expose un disque de stockage (que les téléphones n'écrivent pas) et une interface
 * « vendor » à deux points d'entrée bulk, PICOBOOT, qui permet d'écrire la flash. Le protocole lui-même
 * est en Dart (`nomad_protocols`) : ce code ne fait que trouver l'appareil, demander la permission et
 * transférer des octets.
 *
 * Les transferts bloquent : ils tournent sur un thread dédié, jamais sur le thread principal.
 */
class PicobootUsb(private val context: Context, engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "dev.nomadmcu/picoboot"
        private const val ACTION_PERMISSION = "dev.nomadmcu.nomad_mcu.USB_PERMISSION"
        private const val VENDOR_RASPBERRY_PI = 0x2E8A
        private const val PRODUCT_RP2040_BOOTSEL = 0x0003
        private const val CLASS_VENDOR_SPECIFIC = 0xFF
    }

    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var openName: String? = null
    private var connection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var endpointOut: UsbEndpoint? = null
    private var endpointIn: UsbEndpoint? = null

    init {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(list())
            "requestPermission" -> requestPermission(call.argument<String>("name"), result)
            "open" -> background(result) { open(call.argument<String>("name")) }
            "bulkOut" -> background(result) {
                bulkOut(call.argument<ByteArray>("data")!!, call.argument<Int>("timeoutMs")!!)
            }
            "bulkIn" -> background(result) {
                bulkIn(call.argument<Int>("length")!!, call.argument<Int>("timeoutMs")!!)
            }
            "control" -> background(result) {
                control(
                    call.argument<Int>("requestType")!!,
                    call.argument<Int>("request")!!,
                    call.argument<Int>("length")!!,
                )
            }
            "close" -> background(result) { close(); null }
            else -> result.notImplemented()
        }
    }

    /** Les cartes RP2040 actuellement en BOOTSEL, avec l'état de la permission. */
    private fun list(): List<Map<String, Any>> =
        usb.deviceList.values
            .filter { it.vendorId == VENDOR_RASPBERRY_PI && it.productId == PRODUCT_RP2040_BOOTSEL }
            .map { mapOf("name" to it.deviceName, "hasPermission" to usb.hasPermission(it)) }

    /** Demande à l'utilisateur d'autoriser l'accès ; répond `true` s'il accepte. */
    private fun requestPermission(name: String?, result: MethodChannel.Result) {
        val device = name?.let { usb.deviceList[it] }
        if (device == null) {
            result.error("closed", "La carte n'est plus branchée.", null)
            return
        }
        if (usb.hasPermission(device)) {
            result.success(true)
            return
        }
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                context.unregisterReceiver(this)
                result.success(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        val filter = IntentFilter(ACTION_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
        // Mutable : le système y ajoute l'appareil et la réponse. Le paquet est fixé pour que l'intent reste explicite.
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val intent = Intent(ACTION_PERMISSION).setPackage(context.packageName)
        usb.requestPermission(device, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    /** Ouvre l'appareil et réserve l'interface PICOBOOT : vendor (0xFF) avec un point d'entrée OUT et un IN. */
    private fun open(name: String?): Any? {
        close()
        val device: UsbDevice = name?.let { usb.deviceList[it] } ?: throw UsbFailure("closed", "La carte n'est plus branchée.")
        if (!usb.hasPermission(device)) throw UsbFailure("permission", "Accès USB non autorisé.")
        val candidate = (0 until device.interfaceCount).map { device.getInterface(it) }.firstOrNull { itf ->
            itf.interfaceClass == CLASS_VENDOR_SPECIFIC && itf.endpointCount == 2
        } ?: throw UsbFailure("no_interface", "Interface PICOBOOT introuvable sur cette carte.")
        val out = (0 until candidate.endpointCount).map { candidate.getEndpoint(it) }
            .firstOrNull { it.direction == UsbConstants.USB_DIR_OUT }
        val inn = (0 until candidate.endpointCount).map { candidate.getEndpoint(it) }
            .firstOrNull { it.direction == UsbConstants.USB_DIR_IN }
        if (out == null || inn == null) throw UsbFailure("no_interface", "Points d'entrée PICOBOOT introuvables.")
        val conn = usb.openDevice(device) ?: throw UsbFailure("open", "Impossible d'ouvrir la carte en USB.")
        if (!conn.claimInterface(candidate, true)) {
            conn.close()
            throw UsbFailure("open", "Impossible de réserver l'interface PICOBOOT.")
        }
        connection = conn
        usbInterface = candidate
        endpointOut = out
        endpointIn = inn
        openName = device.deviceName
        return candidate.id
    }

    private fun bulkOut(data: ByteArray, timeoutMs: Int): Any? {
        val conn = connection ?: throw UsbFailure("not_open", "Connexion USB fermée.")
        val sent = conn.bulkTransfer(endpointOut, data, data.size, timeoutMs)
        if (sent < 0) throw failure("Échec d'envoi USB.")
        if (sent != data.size) throw UsbFailure("io", "Envoi USB incomplet ($sent sur ${data.size} octets).")
        return null
    }

    private fun bulkIn(length: Int, timeoutMs: Int): Any? {
        val conn = connection ?: throw UsbFailure("not_open", "Connexion USB fermée.")
        val buffer = ByteArray(length)
        val received = conn.bulkTransfer(endpointIn, buffer, length, timeoutMs)
        // 0 octet est un paquet vide valide (accusé de réception) ; -1 : échec ou délai dépassé.
        if (received < 0) throw failure("Aucune réponse de la carte en USB.")
        return buffer.copyOf(received)
    }

    /** Requête de contrôle « vendor » sur l'interface : `requestType` 0x41 (OUT) ou 0xC1 (IN). */
    private fun control(requestType: Int, request: Int, length: Int): Any? {
        val conn = connection ?: throw UsbFailure("not_open", "Connexion USB fermée.")
        val index = usbInterface?.id ?: 0
        val buffer = ByteArray(length)
        val done = conn.controlTransfer(requestType, request, 0, index, buffer, length, 1000)
        if (done < 0) throw failure("Échec de la requête USB de contrôle.")
        return if (requestType and UsbConstants.USB_DIR_IN != 0) buffer.copyOf(done) else null
    }

    private fun close() {
        try {
            usbInterface?.let { connection?.releaseInterface(it) }
            connection?.close()
        } catch (_: Exception) {
            // la carte a déjà disparu (elle redémarre après l'écriture)
        }
        connection = null
        usbInterface = null
        endpointOut = null
        endpointIn = null
        openName = null
    }

    /** « closed » si la carte a disparu du bus, sinon une erreur d'E/S ordinaire (délai dépassé compris). */
    private fun failure(message: String): UsbFailure {
        val gone = openName?.let { !usb.deviceList.containsKey(it) } ?: true
        return if (gone) UsbFailure("closed", "La carte a été débranchée.") else UsbFailure("io", message)
    }

    private class UsbFailure(val code: String, message: String) : Exception(message)

    /** Exécute [block] hors du thread principal et renvoie son résultat à Flutter. */
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: UsbFailure) {
                mainHandler.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                mainHandler.post { result.error("io", e.message, null) }
            }
        }
    }
}
