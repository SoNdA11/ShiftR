package com.shiftr.shiftr_ble

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val virtualTrainer = VirtualTrainerServer()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VirtualTrainerServer.CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val trainerName = call.argument<String>("trainerName")
                        virtualTrainer.start(this, flutterEngine, trainerName)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("START_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    virtualTrainer.stop()
                    result.success(null)
                }
                "updateData" -> {
                    val power = call.argument<Int>("power") ?: 0
                    val cadence = when (val c = call.argument<Any>("cadence")) {
                        is Double -> c
                        is Float -> c.toDouble()
                        is Int -> c.toDouble()
                        is Long -> c.toDouble()
                        else -> 0.0
                    }
                    val speed = when (val s = call.argument<Any>("speed")) {
                        is Double -> s
                        is Float -> s.toDouble()
                        is Int -> s.toDouble()
                        is Long -> s.toDouble()
                        else -> 0.0
                    }
                    virtualTrainer.updateData(power, cadence, speed)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        virtualTrainer.stop()
        super.onDestroy()
    }
}
