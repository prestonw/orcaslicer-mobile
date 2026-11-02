package com.preston.orcaslicer.printer

/**
 * AD5X Printer communication module
 * Supports Moonraker API, Klipper WebSocket, and direct TCP protocols
 * Primary target: AD5X 3D printer with Klipper firmware
 */
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.ActorMode
import java.io.*
import java.net.*
import java.nio.charset.StandardCharsets

// ==================== Protocol Definitions ====================

sealed interface PrinterMessage {
    data class Request(
        val id: String = generateId(),
        val method: String,
        val params: Map<String, Any?> = emptyMap()
    ) : PrinterMessage

    data class Response(
        val id: String?,
        val result: Map<String, Any?> = emptyMap(),
        val error: String? = null,
        val errorCode: Int? = null
    ) : PrinterMessage

    data class Notification(
        val events: List<String>,
        val data: Map<String, Any?>
    ) : PrinterMessage

    data class Event(
        val event: String,
        val data: Map<String, Any?> = emptyMap()
    ) : PrinterMessage
}

fun generateId(): String = "req_${System.currentTimeMillis()}_${(0 until 4).map { (0..9).random().toString() }.joinToString("")}"

// ==================== Printer Connection State ====================

sealed class PrinterConnectionState {
    object Disconnected : PrinterConnectionState()
    object Connecting : PrinterConnectionState()
    data class Connected(
        val ip: String,
        val port: Int,
        val deviceType: String,
        val firmwareVersion: String? = null,
        val printerName: String? = null
    ) : PrinterConnectionState()
    data class Error(
        val message: String,
        val code: Int? = null,
        val recoverable: Boolean = true
    ) : PrinterConnectionState()
}

// ==================== AD5X Printer Interface ====================

interface AD5XPrinter {
    val connectionState: PrinterConnectionState
    val printerInfo: PrinterInfo?
    val printerState: PrinterState
    
    suspend fun connect(ip: String, port: Int = 7125): Result<Unit>
    suspend fun disconnect()
    suspend fun pairWithDeviceId(deviceId: String): Result<Unit>
    fun onStateChange(listener: (PrinterConnectionState) -> Unit): Job
    fun onEvent(listener: (PrinterMessage.Event) -> Unit): Job
    
    // Print control
    suspend fun printFile(filePath: String, speed: Double = 1.0): Result<Unit>
    suspend fun pausePrint()
    suspend fun resumePrint()
    suspend fun cancelPrint()
    suspend fun homeAxis(axis: String = "all")
    suspend fun setTemperature(target: String, temperature: Double)
    suspend fun setFanSpeed(speed: Int) // 0-100
    suspend fun setFlowRatio(flowRatio: Double) // percentage
    
    // File operations
    suspend fun listFiles(): Result<List<GCodeFile>>
    suspend fun uploadFile(localPath: String, destinationPath: String): Result<Unit>
    suspend fun deleteFile(path: String)
    
    // Monitoring
    suspend fun getTemperatureTargets(): Result<TemperatureTargets>
    suspend fun getTemperatures(): Result<TemperatureReading>
    suspend fun getStatus(): Result<PrinterStatus>
}

// ==================== Printer Information ====================

data class PrinterInfo(
    val deviceId: String,
    val firmware: String,
    val klipperVersion: String,
    val moonrakerVersion: String?,
    val printerName: String,
    val hostname: String,
    val maxHotendTemp: Int = 300,
    val maxBedTemp: Int = 120,
    val buildVolume: BuildVolume
)

data class TemperatureTargets(
    val hotend: Double = 0.0,
    val bed: Double = 0.0,
    val chamber: Double = 0.0
)

data class TemperatureReading(
    val hotend: Double,
    val bed: Double,
    val chamber: Double = 0.0,
    val extruder: Double = 0.0
)

data class PrinterStatus(
    val state: String, // ready, printing, paused, error, offline
    val message: String = "",
    val progress: Float = 0f,
    val printDuration: Double = 0.0,
    val totalDuration: Double = 0.0,
    val filamentUsed: Double = 0.0,
    val estimatedTimeRemaining: Double = 0.0
)

data class BuildVolume(
    val x: Double,
    val y: Double,
    val z: Double
)

// ==================== G-Code File Model ====================

data class GCodeFile(
    val path: String,
    val name: String,
    val size: Long,
    val modified: String,
    val estimatedDuration: Double? = null,
    val filamentUsed: Double? = null,
    val layerHeight: Double? = null
)

// ==================== Network Connection Layer ====================

interface PrinterConnection {
    val state: PrinterConnectionState
    suspend fun connect()
    suspend fun disconnect()
    suspend fun sendRequest(message: PrinterMessage.Request): PrinterMessage.Response
    fun addMessageListener(listener: (PrinterMessage) -> Unit)
}

// ==================== Moonraker Client (Primary Protocol) ====================

class MoonrakerClient(
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO
) : PrinterConnection {
    private val TAG = "MoonrakerClient"
    private var socket: WebSocket? = null
    private val listeners = mutableListOf<(PrinterMessage) -> Unit>()
    private var _state: PrinterConnectionState = PrinterConnectionState.Disconnected
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    override val state: PrinterConnectionState
        get() = _state

    override suspend fun connect() {
        withContext(dispatcher) {
            if (_state is PrinterConnectionState.Connected) return
            
            _state = PrinterConnectionState.Connecting
            try {
                val url = "ws://${(_state as? PrinterConnectionState.Connected)?.ip ?: "localhost"}:7125/printer/objects/subscribe"
                socket = WebSocket(url)
                socket?.connect()
                _state = PrinterConnectionState.Connected(
                    ip = (_state as? PrinterConnectionState.Connected)?.ip ?: "localhost",
                    port = 7125,
                    deviceType = "moonraker",
                    firmwareVersion = "Klipper",
                    printerName = "AD5X"
                )
            } catch (e: Exception) {
                Log.e(TAG, "Connection failed", e)
                _state = PrinterConnectionState.Error(
                    message = e.message ?: "Connection failed",
                    code = 1,
                    recoverable = true
                )
                throw e
            }
        }
    }

    override suspend fun disconnect() {
        withContext(dispatcher) {
            socket?.close()
            socket = null
            _state = PrinterConnectionState.Disconnected
        }
    }

    override suspend fun sendRequest(message: PrinterMessage.Request): PrinterMessage.Response {
        // Moonraker uses HTTP REST API primarily
        val endpoint = "http://${(_state as? PrinterConnectionState.Connected)?.ip}:7125/printer/objects/query"
        val json = """
        {
            "jsonrpc": "2.0",
            "method": "objects.subscribe",
            "params": {
                "objects": {
                    "printer": {},
                    "print_stats": {},
                    "print_stats": {},
                    "gcode_macro": {
                        "START_PRINT": [],
                        "END_PRINT": []
                    },
                    "virtual_sdcard": {}
                }
            },
            "id": "${message.id}"
        }
        """.trimIndent()
        
        val url = URL(endpoint)
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.setRequestProperty("Content-Type", "application/json")
        connection.doOutput = true
        
        connection.outputStream.use { outputStream ->
            outputStream.write(json.toByteArray(StandardCharsets.UTF_8))
        }
        
        val responseCode = connection.responseCode
        val response = connection.inputStream.bufferedReader().readText()
        
        return if (responseCode == 200) {
            // Parse JSON response
            val parsed = parseJsonResponse(response)
            PrinterMessage.Response(
                id = message.id,
                result = parsed
            )
        } else {
            PrinterMessage.Response(
                id = message.id,
                error = "HTTP $responseCode: $response",
                errorCode = responseCode
            )
        }
    }

    override fun addMessageListener(listener: (PrinterMessage) -> Unit) {
        listeners.add(listener)
    }

    private fun parseJsonResponse(response: String): Map<String, Any?> {
        // Simplified JSON parsing - in production use Gson/Moshi
        val result = mutableMapOf<String, Any?>()
        val start = response.indexOf('{')
        if (start != -1) {
            val content = response.substring(start)
            // Use actual JSON library in production
            result["raw"] = content
        }
        return result
    }

    private class WebSocket(private val url: String) {
        var client: OkHttpClient? = null
        var webSocket: okhttp3.WebSocket? = null
        
        init {
            val okHttpClient = OkHttpClient.Builder()
                .pingInterval(java.time.Duration.ofSeconds(30))
                .build()
            this.client = okHttpClient
            this.webSocket = okHttpClient.newWebSocket(
                okhttp3.Request.Builder()
                    .url(url)
                    .build(),
                object : okhttp3.WebSocketListener() {
                    override fun onMessage(webSocket: okhttp3.WebSocket, text: String) {
                        // Handle incoming WebSocket messages
                    }
                }
            )
        }
        
        fun connect() {
            client?.newWebSocket(
                okhttp3.Request.Builder().url(url).build(),
                object : okhttp3.WebSocketListener() {
                    override fun onOpen(webSocket: okhttp3.WebSocket, response: okhttp3.Response) {
                        Log.d("WebSocket", "Connected")
                    }
                    
                    override fun onMessage(webSocket: okhttp3.WebSocket, text: String) {
                        // Handle message
                    }
                    
                    override fun onFailure(webSocket: okhttp3.WebSocket, t: Throwable, response: okhttp3.Response?) {
                        Log.e("WebSocket", "Failed", t)
                    }
                }
            )
        }
        
        fun close() {
            webSocket?.close(1000, "Shutdown")
        }
    }
}

// ==================== Klipper WebSocket Client ====================

class KlipperClient(
    private val ip: String,
    private val port: Int = 7125
) : PrinterConnection {
    private val TAG = "KlipperClient"
    private var socket: PrintWriter? = null
    private var reader: BufferedReader? = null
    private val listeners = mutableListOf<(PrinterMessage) -> Unit>()
    private var _state: PrinterConnectionState = PrinterConnectionState.Disconnected
    private var reconnectAttempts = 0
    private val maxReconnectAttempts = 5
    
    override val state: PrinterConnectionState
        get() = _state

    override suspend fun connect() {
        withContext(Dispatchers.IO) {
            try {
                val hostName = if (ip.contains(".")) ip else "$ip.local"
                val socket = Socket(InetAddress.getByName(hostName), port)
                
                socket.setKeepAlive(true)
                socket.tcpNoDelay = true
                
                reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                socket = PrintWriter(socket.getOutputStream(), true)
                
                _state = PrinterConnectionState.Connected(
                    ip = hostName,
                    port = port,
                    deviceType = "klipper"
                )
                
                // Start listening for messages
                startMessageListener(reader!!)
                
                // Send initial handshake
                sendMessage("""{"id": "handshake", "method": "server.hello", "params": {}}""")
                
            } catch (e: Exception) {
                Log.e(TAG, "Klipper connection failed", e)
                _state = PrinterConnectionState.Error(
                    message = "Cannot connect to $ip:$port: ${e.message}",
                    recoverable = true
                )
            }
        }
    }

    override suspend fun disconnect() {
        try {
            socket?.close()
            reader?.close()
            _state = PrinterConnectionState.Disconnected
        } catch (e: Exception) {
            Log.e(TAG, "Disconnect error", e)
        }
    }

    override suspend fun sendRequest(message: PrinterMessage.Request): PrinterMessage.Response {
        val json = """
        {
            "id": "${message.id}",
            "method": "${message.method}",
            "params": ${convertToParams(message.params)}
        }
        """.trimIndent()
        
        return withContext(Dispatchers.IO) {
            try {
                sendMessage(json)
                // Wait for response - in production use proper async handling
                Thread.sleep(1000)
                PrinterMessage.Response(
                    id = message.id,
                    result = emptyMap()
                )
            } catch (e: Exception) {
                PrinterMessage.Response(
                    id = message.id,
                    error = e.message ?: "Request failed"
                )
            }
        }
    }

    override fun addMessageListener(listener: (PrinterMessage) -> Unit) {
        listeners.add(listener)
    }

    private fun sendMessage(message: String) {
        socket?.println(message)
        socket?.flush()
    }

    private fun startMessageListener(reader: BufferedReader) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                var line: String?
                while (readLine != null) {
                    line = reader.readLine()
                    if (line != null) {
                        handleIncomingMessage(line)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Message listener error", e)
            }
        }
    }

    private fun handleIncomingMessage(message: String) {
        try {
            // Parse JSON message
            val parsed = parseJsonMessage(message)
            listeners.forEach { it(parsed) }
        } catch (e: Exception) {
            Log.e(TAG, "Message parse error", e)
        }
    }

    private fun parseJsonMessage(json: String): PrinterMessage {
        // Simplified parsing - use proper JSON library in production
        if (json.contains("notification")) {
            return PrinterMessage.Notification(
                events = listOf(),
                data = mapOf("raw" to json)
            )
        }
        return PrinterMessage.Response(
            id = null,
            result = mapOf("raw" to json)
        )
    }

    private fun convertToParams(params: Map<String, Any?>): String {
        // Convert Kotlin map to JSON string
        return when {
            params.isEmpty() -> "{}"
            params.keys.size == 1 && params.keys.first() == "raw" -> params["raw"]?.toString() ?: "{}"
            else -> params.entries.joinToString(", ") { "\"${it.key}\": ${formatValue(it.value)}" }
                .let { "{ $it }" }
        }
    }

    private fun formatValue(value: Any?): String = when (value) {
        is String -> "\"$value\""
        is Number -> value.toString()
        is Boolean -> value.toString()
        null -> "null"
        else -> value.toString()
    }
}

// ==================== Printer State Manager ====================

class PrinterStateManager {
    private var _state: PrinterConnectionState = PrinterConnectionState.Disconnected
    private val listeners = mutableListOf<(PrinterConnectionState) -> Unit>()
    
    val state: PrinterConnectionState
        get() = _state
    
    fun updateState(newState: PrinterConnectionState) {
        _state = newState
        listeners.forEach { it(newState) }
    }
    
    fun addListener(listener: (PrinterConnectionState) -> Unit) {
        listeners.add(listener)
    }
    
    fun removeListener(listener: (PrinterConnectionState) -> Unit) {
        listeners.remove(listener)
    }
}

// ==================== mDNS Printer Discovery ====================

class PrinterDiscoveryService(private val context: android.content.Context) {
    private val TAG = "PrinterDiscovery"
    
    suspend fun discoverPrinters(timeout: Long = 5000): List<DiscoveredPrinter> {
        return withContext(Dispatchers.IO) {
            val discovered = mutableListOf<DiscoveredPrinter>()
            
            try {
                // Use mDNS/SRP to discover printers
                val mdnsService = android.net.nsd.NsdManager(context.getSystemService(Context.NSD_SERVICE) as android.net.nsd.NsdManager)
                
                val serviceInfo = android.net.nsd.ServiceInfo(
                    "_http._tcp.",
                    "AD5X Printer"
                )
                
                val listener = object : android.net.nsd.NsdManager.DiscoveryListener {
                    override fun onDiscoveryStarted(serviceType: String) {
                        Log.d(TAG, "mDNS discovery started")
                    }
                    
                    override fun onServiceFound(service: android.net.nsd.ServiceInfo) {
                        if (service.serviceType == "_http._tcp.") {
                            mdnsService.resolveService(service, object : android.net.nsd.NsdManager.ResolveListener {
                                override fun onResolveFailed(serviceInfo: android.net.nsd.ServiceInfo, errorCode: Int) {
                                    Log.e(TAG, "Resolve failed: $errorCode")
                                }
                                
                                override fun onServiceResolved(serviceInfo: android.net.nsd.ServiceInfo) {
                                    Log.d(TAG, "Found printer: ${serviceInfo.host}:${serviceInfo.port}")
                                    discovered.add(
                                        DiscoveredPrinter(
                                            host = serviceInfo.host,
                                            port = serviceInfo.port,
                                            name = serviceInfo.serviceName,
                                            type = "moonraker"
                                        )
                                    )
                                }
                            })
                        }
                    }
                    
                    override fun onServiceLost(service: android.net.nsd.ServiceInfo) {}
                    override fun onDiscoveryStopped(serviceType: String) {}
                    override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                        Log.e(TAG, "Discovery failed: $errorCode")
                    }
                    
                    override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                        Log.e(TAG, "Discovery stopped: $errorCode")
                    }
                }
                
                mdnsService.discoverServices("_http._tcp.", android.net.nsd.NsdManager.PROTOCOL_DNS_SD, listener)
                
                // Wait for discovery to complete
                Thread.sleep(timeout)
                
            } catch (e: Exception) {
                Log.e(TAG, "Discovery error", e)
            }
            
            discovered
        }
    }
}

data class DiscoveredPrinter(
    val host: String,
    val port: Int,
    val name: String,
    val type: String = "moonraker"
)

// ==================== Device ID Pairing ====================

object DeviceIdPairing {
    private const val TAG = "DeviceIdPairing"
    private const val PREFS_NAME = "printer_pairing"
    private const val KEY_DEVICE_IDS = "paired_device_ids"
    private const val KEY_PRINTER_INFO = "printer_info"
    
    fun pairDevice(context: android.content.Context, deviceId: String, ip: String, port: Int): Boolean {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            val pairedIds = prefs.getStringSet(KEY_DEVICE_IDS, mutableSetOf()).orEmpty().toMutableSet()
            pairedIds.add(deviceId)
            
            val info = PrinterInfo(
                deviceId = deviceId,
                firmware = "Klipper",
                klipperVersion = "unknown",
                moonrakerVersion = "unknown",
                printerName = "AD5X",
                hostname = "$ip:$port",
                buildVolume = BuildVolume(220.0, 220.0, 250.0) // AD5X typical volume
            )
            
            val infoJson = com.google.gson.Gson().toJson(info)
            prefs.edit()
                .putStringSet(KEY_DEVICE_IDS, pairedIds)
                .putString("${KEY_PRINTER_INFO}_$deviceId", infoJson)
                .apply()
            
            Log.d(TAG, "Paired device: $deviceId at $ip:$port")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Pairing failed", e)
            false
        }
    }
    
    fun getPairedDevices(context: android.content.Context): List<PrinterInfo> {
        return try {
            val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            val pairedIds = prefs.getStringSet(KEY_DEVICE_IDS, emptySet()).orEmpty()
            
            pairedIds.mapNotNull { deviceId ->
                val infoJson = prefs.getString("${KEY_PRINTER_INFO}_$deviceId", null)
                infoJson?.let { json ->
                    com.google.gson.Gson().fromJson(json, PrinterInfo::class.java)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get paired devices", e)
            emptyList()
        }
    }
    
    fun removePairedDevice(context: android.content.Context, deviceId: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
        val pairedIds = prefs.getStringSet(KEY_DEVICE_IDS, mutableSetOf()).orEmpty().toMutableSet()
        pairedIds.remove(deviceId)
        
        prefs.edit()
            .putStringSet(KEY_DEVICE_IDS, pairedIds)
            .remove("${KEY_PRINTER_INFO}_$deviceId")
            .apply()
        
        Log.d(TAG, "Removed paired device: $deviceId")
    }
}

// ==================== Printer Connection Manager ====================

class PrinterConnectionManager(private val context: android.content.Context) {
    private var activePrinter: AD5XPrinter? = null
    private val stateManager = PrinterStateManager()
    private val discoveryService = PrinterDiscoveryService(context)
    private val pairedDevices = mutableListOf<PrinterInfo>()
    
    init {
        loadPairedDevices()
    }
    
    val state: PrinterConnectionState
        get() = stateManager.state
    
    suspend fun connectToPrinter(ip: String, port: Int = 7125): Result<AD5XPrinter> {
        return try {
            val moonrakerClient = MoonrakerClient()
            moonrakerClient.connect()
            
            val printer = createPrinterAdapter(moonrakerClient, ip, port)
            activePrinter = printer
            
            stateManager.updateState(
                PrinterConnectionState.Connected(
                    ip = ip,
                    port = port,
                    deviceType = "moonraker",
                    firmwareVersion = "Klipper",
                    printerName = "AD5X"
                )
            )
            
            Result.success(printer)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    suspend fun connectToPairedDevice(deviceId: String): Result<AD5XPrinter> {
        val pairedInfo = pairedDevices.find { it.deviceId == deviceId }
        return if (pairedInfo != null) {
            connectToPrinter(pairedInfo.hostname.split(":")[0], pairedInfo.hostname.split(":")[1].toInt())
        } else {
            Result.failure(IllegalArgumentException("Device $deviceId not paired"))
        }
    }
    
    suspend fun disconnect() {
        activePrinter?.let {
            it.disconnect()
            activePrinter = null
        }
        stateManager.updateState(PrinterConnectionState.Disconnected)
    }
    
    suspend fun pairWithDeviceId(deviceId: String): Result<Unit> {
        return try {
            DeviceIdPairing.pairDevice(context, deviceId, "192.168.1.100", 7125)
            loadPairedDevices()
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    suspend fun discoverNetworkPrinters(): List<DiscoveredPrinter> {
        return discoveryService.discoverPrinters()
    }
    
    val pairedPrinters: List<PrinterInfo>
        get() = pairedDevices
    
    private fun createPrinterAdapter(client: PrinterConnection, ip: String, port: Int): AD5XPrinter {
        return object : AD5XPrinter {
            override val connectionState: PrinterConnectionState
                get() = client.state
            
            override val printerInfo: PrinterInfo?
                get() = PrinterInfo(
                    deviceId = "AD5X_$ip",
                    firmware = "Klipper",
                    klipperVersion = "0.11.0-250",
                    moonrakerVersion = "0.8.0",
                    printerName = "AD5X",
                    hostname = "$ip:$port",
                    buildVolume = BuildVolume(220.0, 220.0, 250.0)
                )
            
            override val printerState: PrinterState
                get() = PrinterState(
                    state = "ready",
                    progress = 0f
                )
            
            override suspend fun connect(ip: String, port: Int): Result<Unit> = Result.success(Unit)
            
            override suspend fun disconnect() {
                client.disconnect()
            }
            
            override suspend fun pairWithDeviceId(deviceId: String): Result<Unit> {
                return DeviceIdPairing.pairDevice(context, deviceId, ip, port).let { 
                    if (it) Result.success(Unit) else Result.failure(Exception("Pairing failed"))
                }
            }
            
            override fun onStateChange(listener: (PrinterConnectionState) -> Unit): Job {
                stateManager.addListener(listener)
                return kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
                    kotlinx.coroutines.coroutineScope {
                        // Keep listener active
                    }
                }
            }
            
            override fun onEvent(listener: (PrinterMessage.Event) -> Unit): Job {
                client.addMessageListener { message ->
                    if (message is PrinterMessage.Response) {
                        listener(PrinterMessage.Event(
                            event = "state_change",
                            data = message.result
                        ))
                    }
                }
                return kotlinx.coroutines.CoroutineScope(Dispatchers.Main).launch {
                    kotlinx.coroutines.coroutineScope {
                        // Keep listener active
                    }
                }
            }
            
            override suspend fun printFile(filePath: String, speed: Double): Result<Unit> {
                val request = PrinterMessage.Request(
                    method = "printer.print.start",
                    params = mapOf("file_path" to filePath)
                )
                return try {
                    val response = client.sendRequest(request)
                    if (response.error == null) Result.success(Unit)
                    else Result.failure(Exception(response.error))
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
            
            override suspend fun pausePrint() = suspend { client.sendRequest(PrinterMessage.Request("printer.print.pause")) }
            override suspend fun resumePrint() = suspend { client.sendRequest(PrinterMessage.Request("printer.print.resume")) }
            override suspend fun cancelPrint() = suspend { client.sendRequest(PrinterMessage.Request("printer.print.cancel")) }
            override suspend fun homeAxis(axis: String) = suspend { client.sendRequest(PrinterMessage.Request("printer.gcode.script", mapOf("script" to "HOME $axis"))) }
            override suspend fun setTemperature(target: String, temperature: Double) = suspend { client.sendRequest(PrinterMessage.Request("heater.set_temperature", mapOf("target" to target, "temperature" to temperature))) }
            override suspend fun setFanSpeed(speed: Int) = suspend { client.sendRequest(PrinterMessage.Request("output_pin.fan", mapOf("value" to speed / 100.0))) }
            override suspend fun setFlowRatio(flowRatio: Double) = suspend { client.sendRequest(PrinterMessage.Request("gcode.script", mapOf("script" to "M221 S$flowRatio"))) }
            
            override suspend fun listFiles(): Result<List<GCodeFile>> {
                val request = PrinterMessage.Request(
                    method = "server.files.list",
                    params = mapOf("metadata" to true)
                )
                return try {
                    val response = client.sendRequest(request)
                    if (response.error == null) {
                        val files = response.result["files"] as? List<Map<String, Any?>> ?: emptyList()
                        val gcodeFiles = files.map { file ->
                            GCodeFile(
                                path = file["path"] as String,
                                name = file["filename"] as String,
                                size = (file["size"] as? Long) ?: 0,
                                modified = file["modified"] as? String ?: "",
                                estimatedDuration = file["estimated_duration"] as? Double,
                                filamentUsed = file["filament_total"] as? Double
                            )
                        }
                        Result.success(gcodeFiles)
                    } else {
                        Result.failure(Exception(response.error ?: "List files failed"))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
            
            override suspend fun uploadFile(localPath: String, destinationPath: String): Result<Unit> {
                // Implement file upload via Moonraker API
                TODO("File upload implementation")
            }
            
            override suspend fun deleteFile(path: String) {
                TODO("Delete file implementation")
            }
            
            override suspend fun getTemperatureTargets(): Result<TemperatureTargets> {
                val request = PrinterMessage.Request(
                    method = "printer.objects.query",
                    params = mapOf(
                        "objects" to mapOf(
                            "heater_hotend" to listOf("target"),
                            "heater_bed" to listOf("target")
                        )
                    )
                )
                return try {
                    val response = client.sendRequest(request)
                    if (response.error == null) {
                        val result = response.result
                        Result.success(
                            TemperatureTargets(
                                hotend = (result["heater_hotend"] as? Map<String, Any?>)?.get("target") as? Double ?: 0.0,
                                bed = (result["heater_bed"] as? Map<String, Any?>)?.get("target") as? Double ?: 0.0
                            )
                        )
                    } else {
                        Result.failure(Exception(response.error))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
            
            override suspend fun getTemperatures(): Result<TemperatureReading> {
                val request = PrinterMessage.Request(
                    method = "printer.objects.query",
                    params = mapOf(
                        "objects" to mapOf(
                            "heater_hotend" to listOf("temperature"),
                            "heater_bed" to listOf("temperature")
                        )
                    )
                )
                return try {
                    val response = client.sendRequest(request)
                    if (response.error == null) {
                        val result = response.result
                        Result.success(
                            TemperatureReading(
                                hotend = (result["heater_hotend"] as? Map<String, Any?>)?.get("temperature") as? Double ?: 0.0,
                                bed = (result["heater_bed"] as? Map<String, Any?>)?.get("temperature") as? Double ?: 0.0
                            )
                        )
                    } else {
                        Result.failure(Exception(response.error))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
            
            override suspend fun getStatus(): Result<PrinterStatus> {
                val request = PrinterMessage.Request(
                    method = "printer.objects.query",
                    params = mapOf(
                        "objects" to mapOf(
                            "print_stats" to listOf("state", "filename", "total_duration", "filament_used", "estimated_duration"),
                            "virtual_sdcard" to listOf("is_active", "progress"),
                            "gcode_move" to listOf("speed_factor")
                        )
                    )
                )
                return try {
                    val response = client.sendRequest(request)
                    if (response.error == null) {
                        val result = response.result
                        val printStats = result["print_stats"] as? Map<String, Any?> ?: emptyMap()
                        val sdcard = result["virtual_sdcard"] as? Map<String, Any?> ?: emptyMap()
                        
                        Result.success(
                            PrinterStatus(
                                state = (printStats["state"] as? String) ?: "ready",
                                message = (printStats["message"] as? String) ?: "",
                                progress = (sdcard["progress"] as? Double)?.toFloat() ?: 0f,
                                printDuration = (printStats["total_duration"] as? Double) ?: 0.0,
                                totalDuration = (printStats["estimated_duration"] as? Double) ?: 0.0,
                                filamentUsed = (printStats["filament_used"] as? Double) ?: 0.0,
                                estimatedTimeRemaining = (printStats["estimated_duration"] as? Double) ?: 0.0 - ((printStats["total_duration"] as? Double) ?: 0.0)
                            )
                        )
                    } else {
                        Result.failure(Exception(response.error))
                    }
                } catch (e: Exception) {
                    Result.failure(e)
                }
            }
        }
    }
    
    private fun loadPairedDevices() {
        pairedDevices.clear()
        pairedDevices.addAll(DeviceIdPairing.getPairedDevices(context))
    }
}
