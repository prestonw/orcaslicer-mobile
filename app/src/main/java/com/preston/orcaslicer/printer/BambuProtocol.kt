/*
 * Bambu Protocol Implementation for AD5X Printer
 * Handles WebSocket/MQTT communication, device pairing, and command/response handling
 * Protocol: WebSocket over TCP (port 80 or 8082) with JSON messages
 */

package com.preston.orcaslicer.printer

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.*
import org.json.*
import java.io.*
import java.net.*
import java.security.MessageDigest
import javax.net.ssl.SSLSocketFactory

// ==================== AD5X Printer Models ====================

/**
 * Represents a paired AD5X printer
 */
data class PairedPrinter(
    val deviceID: String,
    val ip: String,
    val port: Int = 80,
    val name: String = "AD5X",
    val firmware: String? = null,
    val model: String = "AD5X",
    val pairedAt: Long = System.currentTimeMillis(),
    var online: Boolean = false
)

/**
 * Printer state derived from AD5X telemetry
 */
data class PrinterState(
    val state: String = "offline",
    val progress: Float = 0f,
    val hotendTemp: Float = 0f,
    val bedTemp: Float = 0f,
    val chamberTemp: Float = 0f,
    val fanSpeed: Int = 0,
    val printTime: Long = 0,
    val remainingTime: Long = 0,
    val filamentUsed: Float = 0f,
    val currentLayer: Int = 0,
    val totalLayers: Int = 0
)

/**
 * Print job status
 */
sealed class PrintStatus {
    object Idle : PrintStatus()
    object Printing : PrintStatus()
    object Paused : PrintStatus()
    object Error : PrintStatus()
    object Finishing : PrintStatus()
    data class Custom(val state: String, val message: String = "") : PrintStatus()
}

// ==================== Bambu WebSocket Protocol ====================

/**
 * AD5X WebSocket communication handler
 * Protocol: JSON over WebSocket with MQTT-style topics
 */
class BambuProtocol private constructor() {
    companion object {
        private const val TAG = "BambuProtocol"
        private const val MSG_ID = 123456789L
        
        /**
         * Build the login/login payload for AD5X
         * DeviceID + Token based authentication
         */
        fun buildLoginPayload(deviceID: String, token: String = ""): String {
            val msg = JSONObject().apply {
                put("method", "user.login")
                put("params", JSONObject().apply {
                    put("deviceID", deviceID)
                    if (token.isNotEmpty()) {
                        put("token", token)
                    }
                })
                put("id", MSG_ID)
            }
            return msg.toString()
        }
        
        /**
         * Build the login response parser
         */
        fun parseLoginResponse(json: String): Result<String> {
            return try {
                val obj = JSONObject(json)
                val code = obj.optInt("code", -1)
                if (code == 0) {
                    // Success - extract token if available
                    val result = obj.optJSONObject("result")
                    val token = result?.optString("token", "")
                    Result.success(token)
                } else {
                    val error = obj.optString("msg", "Unknown error")
                    Result.failure(Exception("Login failed: $error (code: $code)"))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse login response", e)
                Result.failure(e)
            }
        }
        
        /**
         * Build a control command payload
         */
        fun buildCommand(command: String, params: Map<String, Any> = emptyMap()): String {
            val msg = JSONObject().apply {
                put("method", command)
                if (params.isNotEmpty()) {
                    put("params", JSONObject(params.mapValues { it.value.toString() }))
                }
                put("id", MSG_ID)
            }
            return msg.toString()
        }
        
        /**
         * Build the deviceinfo request
         */
        fun buildDeviceInfoRequest(): String {
            return buildCommand("deviceinfo.get")
        }
        
        /**
         * Build the print start command
         */
        fun buildStartPrintCommand(printFile: String, speed: String = "0", profile: String = ""): String {
            val params = mutableMapOf<String, String>().apply {
                put("command", "start")
                put("print_type", "File")
                put("project_id", "0")
                put("profile_id", "0")
                put("public", "false")
                put("file_path", printFile)
                if (speed.isNotEmpty()) put("speed", speed)
                if (profile.isNotEmpty()) put("profile_id", profile)
            }
            return buildCommand("projector.start", params)
        }
        
        /**
         * Build the print pause command
         */
        fun buildPausePrintCommand(): String {
            return buildCommand("printer.pause")
        }
        
        /**
         * Build the print resume command
         */
        fun buildResumePrintCommand(): String {
            return buildCommand("printer.resume")
        }
        
        /**
         * Build the print stop command
         */
        fun buildStopPrintCommand(): String {
            return buildCommand("printer.stop")
        }
        
        /**
         * Parse telemetry/heartbeat message
         */
        fun parseTelemetry(json: String): PrinterState? {
            return try {
                val obj = JSONObject(json)
                // Extract the "msg" field which contains the telemetry JSON
                val msgStr = obj.optString("msg", null)
                if (msgStr == null) return null
                
                val msg = JSONObject(msgStr)
                val info = msg.optJSONObject("info")
                if (info == null) return null
                
                val chamber = info.optJSONObject("chamber_temperature")
                val temp = info.optJSONObject("temperatures")
                
                PrinterState(
                    state = info.optString("state", "offline"),
                    progress = info.optDouble("print_progress", 0.0).toFloat(),
                    hotendTemp = temp?.optDouble("hotend_temp", 0.0).toFloat() ?: 0f,
                    bedTemp = temp?.optDouble("bed_temp", 0.0).toFloat() ?: 0f,
                    chamberTemp = chamber?.optDouble("chamber_temp", 0.0).toFloat() ?: 0f,
                    fanSpeed = temp?.optInt("bed_fan_speed", 0) ?: 0,
                    printTime = info.optLong("print_total_duration", 0) / 1000,
                    remainingTime = info.optLong("remaining_time", 0) / 1000,
                    filamentUsed = info.optDouble("total_filament_used", 0.0).toFloat(),
                    currentLayer = info.optInt("current_layer", 0),
                    totalLayers = info.optInt("total_layers", 0)
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse telemetry", e)
                null
            }
        }
        
        /**
         * Build heartbeat/subscribe message to keep connection alive
         */
        fun buildSubscribeMessage(): String {
            return JSONObject().apply {
                put("method", "logon")
                put("params", JSONObject().apply {
                    put("heartbeat_interval", 10)
                })
                put("id", MSG_ID)
            }.toString()
        }
    }
}
