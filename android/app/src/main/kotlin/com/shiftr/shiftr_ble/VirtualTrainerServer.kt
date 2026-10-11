package com.shiftr.shiftr_ble

import android.bluetooth.*
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class VirtualTrainerServer {
    companion object {
        const val CHANNEL = "com.shiftr/virtual_trainer"
        val CPS_UUID = UUID.fromString("00001818-0000-1000-8000-00805f9b34fb")
        val CPS_MEASUREMENT_UUID = UUID.fromString("00002a63-0000-1000-8000-00805f9b34fb")
        val CPS_FEATURE_UUID = UUID.fromString("00002a65-0000-1000-8000-00805f9b34fb")
        val SENSOR_LOCATION_UUID = UUID.fromString("00002a5d-0000-1000-8000-00805f9b34fb")
        val FTMS_UUID = UUID.fromString("00001826-0000-1000-8000-00805f9b34fb")
        val FTMS_FEATURE_UUID = UUID.fromString("00002acc-0000-1000-8000-00805f9b34fb")
        val INDOOR_BIKE_DATA_UUID = UUID.fromString("00002ad2-0000-1000-8000-00805f9b34fb")
        val FTMS_CONTROL_POINT_UUID = UUID.fromString("00002ad9-0000-1000-8000-00805f9b34fb")
        val CCC_DESCRIPTOR_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var connectedDevice: BluetoothDevice? = null
    private var channel: MethodChannel? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var originalBtName: String? = null

    private var cpsMeasurementChar: BluetoothGattCharacteristic? = null
    private var indoorBikeDataChar: BluetoothGattCharacteristic? = null
    private var controlPointChar: BluetoothGattCharacteristic? = null

    private var lastPower: Int = 0
    private var lastCadence: Double = 0.0

    private var pendingHandler: Runnable? = null

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            channel?.invokeMethod("onAdvertising", true)
        }

        override fun onStartFailure(errorCode: Int) {
            val msg = when (errorCode) {
                ADVERTISE_FAILED_DATA_TOO_LARGE -> "data too large"
                ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "too many advertisers"
                ADVERTISE_FAILED_ALREADY_STARTED -> "already started"
                ADVERTISE_FAILED_INTERNAL_ERROR -> "internal error"
                ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "feature unsupported"
                else -> "unknown: $errorCode"
            }
            channel?.invokeMethod("onError", "advertise failed: $msg")
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevice = device
                channel?.invokeMethod("onConnected", null)
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                if (device == connectedDevice) connectedDevice = null
                channel?.invokeMethod("onDisconnected", null)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, characteristic.value)
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor
        ) {
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, descriptor.value)
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            descriptor.value = value
            gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid == FTMS_CONTROL_POINT_UUID) {
                handleControlPoint(device, requestId, value, responseNeeded)
            } else if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }
    }

    fun start(context: Context, engine: FlutterEngine, trainerName: String?) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)

        val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        if (adapter == null || !adapter.isEnabled) {
            channel?.invokeMethod("onError", "Bluetooth not enabled")
            return
        }
        bluetoothAdapter = adapter

        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        if (gattServer == null) {
            channel?.invokeMethod("onError", "Failed to open GATT server")
            return
        }

        setupServices()

        val leAdvertiser = adapter.bluetoothLeAdvertiser
        if (leAdvertiser == null) {
            channel?.invokeMethod("onError", "BLE advertising not supported on this device")
            return
        }

        if (!trainerName.isNullOrBlank()) {
            originalBtName = adapter.name
            try {
                adapter.name = trainerName
                channel?.invokeMethod("onLog", "Changed BT name to: $trainerName")
            } catch (e: Exception) {
                channel?.invokeMethod("onLog", "Could not change BT name: ${e.message}")
            }
        }

        startAdvertising(leAdvertiser)

        channel?.invokeMethod("onReady", null)
    }

    private fun setupServices() {
        val cpsService = BluetoothGattService(CPS_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val cccCps = BluetoothGattDescriptor(CCC_DESCRIPTOR_UUID, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE)
        cpsMeasurementChar = BluetoothGattCharacteristic(
            CPS_MEASUREMENT_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        cpsMeasurementChar!!.addDescriptor(cccCps)
        cpsService.addCharacteristic(cpsMeasurementChar!!)

        val cpsFeature = BluetoothGattCharacteristic(
            CPS_FEATURE_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        cpsFeature.value = byteArrayOf(0x00, 0x00, 0x00, 0x00)
        cpsService.addCharacteristic(cpsFeature)

        val sensorLocation = BluetoothGattCharacteristic(
            SENSOR_LOCATION_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        sensorLocation.value = byteArrayOf(0x00)
        cpsService.addCharacteristic(sensorLocation)

        gattServer?.addService(cpsService)

        val ftmsService = BluetoothGattService(FTMS_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        val ftmsFeature = BluetoothGattCharacteristic(
            FTMS_FEATURE_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        // Machine features: Cadence(bit1) | ResistanceLevel(bit4) | InstantaneousPower(bit5) = 0x32
        // Target features: ResistanceTarget(bit2) | PowerTarget(bit3) = 0x0C
        ftmsFeature.value = byteArrayOf(0x32, 0x00, 0x00, 0x00, 0x0C, 0x00, 0x00, 0x00)
        ftmsService.addCharacteristic(ftmsFeature)

        val flags = byteArrayOf(0x40.toByte(), 0x00)
        val powerBytes = byteArrayOf(0x00, 0x00)
        val initialIndoor = flags + powerBytes
        val cccFtms = BluetoothGattDescriptor(CCC_DESCRIPTOR_UUID, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE)
        indoorBikeDataChar = BluetoothGattCharacteristic(
            INDOOR_BIKE_DATA_UUID,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        indoorBikeDataChar!!.value = initialIndoor
        indoorBikeDataChar!!.addDescriptor(cccFtms)
        ftmsService.addCharacteristic(indoorBikeDataChar!!)

        controlPointChar = BluetoothGattCharacteristic(
            FTMS_CONTROL_POINT_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_INDICATE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )
        ftmsService.addCharacteristic(controlPointChar!!)

        gattServer?.addService(ftmsService)
    }

    private fun startAdvertising(leAdvertiser: BluetoothLeAdvertiser) {
        advertiser = leAdvertiser

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(FTMS_UUID))
            .build()

        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun handleControlPoint(device: BluetoothDevice, requestId: Int, value: ByteArray, responseNeeded: Boolean) {
        if (value.isEmpty()) {
            if (responseNeeded) gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            return
        }

        val opCode = value[0].toInt() and 0xFF
        when (opCode) {
            0x04 -> {
                if (value.size >= 3) {
                    val resistance = value[1].toInt() and 0xFF
                    channel?.invokeMethod("onResistanceRequest", resistance)
                }
                sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            }
            0x05 -> {
                if (value.size >= 4) {
                    val power = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
                    channel?.invokeMethod("onTargetPowerRequest", power)
                }
                sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            }
            0x00 -> sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            0x01 -> sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            0x07 -> sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            0x08 -> sendControlPointResponse(device, requestId, opCode.toByte(), 0x01, responseNeeded)
            else -> sendControlPointResponse(device, requestId, opCode.toByte(), 0x02, responseNeeded)
        }
    }

    private fun sendControlPointResponse(device: BluetoothDevice, requestId: Int, opCode: Byte, resultCode: Byte, responseNeeded: Boolean) {
        if (!responseNeeded) return
        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        val status = byteArrayOf(0x80.toByte(), opCode, resultCode)
        val notifyChar = controlPointChar
        if (notifyChar != null) {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                gattServer?.notifyCharacteristicChanged(device, notifyChar, false, status)
            } else {
                @Suppress("DEPRECATION")
                notifyChar.value = status
                gattServer?.notifyCharacteristicChanged(device, notifyChar, false)
            }
        }
    }

    fun updateData(power: Int, cadence: Double, speed: Double) {
        lastPower = power
        lastCadence = cadence

        notifyCpsMeasurement(power)

        // Add a 15ms delay to prevent characteristic notification updates from overlapping
        // and causing buffer corruption in the Android BLE stack.
        pendingHandler?.let { android.os.Handler(android.os.Looper.getMainLooper()).removeCallbacks(it) }
        val handler = Runnable {
            notifyIndoorBikeData(power, cadence, speed)
            pendingHandler = null
        }
        pendingHandler = handler
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(handler, 15)
    }

    private fun notifyCpsMeasurement(power: Int) {
        val dev = connectedDevice ?: return
        val char = cpsMeasurementChar ?: return

        val flags = byteArrayOf(0x00.toByte(), 0x00.toByte())
        val powerBytes = byteArrayOf((power and 0xFF).toByte(), ((power shr 8) and 0xFF).toByte())
        val cpsData = flags + powerBytes

        if (android.os.Build.VERSION.SDK_INT >= 33) {
            gattServer?.notifyCharacteristicChanged(dev, char, false, cpsData)
        } else {
            @Suppress("DEPRECATION")
            char.value = cpsData
            gattServer?.notifyCharacteristicChanged(dev, char, false)
        }
    }

    private fun notifyIndoorBikeData(power: Int, cadence: Double, speed: Double) {
        val dev = connectedDevice ?: return
        val char = indoorBikeDataChar ?: return

        val flags = byteArrayOf(0x44.toByte(), 0x00)
        val speedInt = (speed * 100).toInt().coerceIn(0, 65535)
        val speedBytes = byteArrayOf((speedInt and 0xFF).toByte(), ((speedInt shr 8) and 0xFF).toByte())
        val cadenceInt = (cadence * 2).toInt().coerceIn(0, 65535)
        val cadenceBytes = byteArrayOf((cadenceInt and 0xFF).toByte(), ((cadenceInt shr 8) and 0xFF).toByte())
        val powerBytes = byteArrayOf((power and 0xFF).toByte(), ((power shr 8) and 0xFF).toByte())
        val indoorData = flags + speedBytes + cadenceBytes + powerBytes

        if (android.os.Build.VERSION.SDK_INT >= 33) {
            gattServer?.notifyCharacteristicChanged(dev, char, false, indoorData)
        } else {
            @Suppress("DEPRECATION")
            char.value = indoorData
            gattServer?.notifyCharacteristicChanged(dev, char, false)
        }
    }

    fun stop() {
        try {
            // Restore original Bluetooth name
            val adapter = bluetoothAdapter
            val origName = originalBtName
            if (adapter != null && origName != null) {
                try {
                    adapter.name = origName
                } catch (_: Exception) {}
            }
            connectedDevice?.let { gattServer?.cancelConnection(it) }
            advertiser?.stopAdvertising(advertiseCallback)
            gattServer?.close()
        } catch (_: Exception) {}
        gattServer = null
        advertiser = null
        connectedDevice = null
        bluetoothAdapter = null
        originalBtName = null
        cpsMeasurementChar = null
        indoorBikeDataChar = null
        controlPointChar = null
    }
}
