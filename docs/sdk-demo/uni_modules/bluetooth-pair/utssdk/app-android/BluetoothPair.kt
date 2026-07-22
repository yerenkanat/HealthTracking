package uts.bluetoothpair.android

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.os.Build
import android.util.Log

object BluetoothPairPlugin {

    fun pair(mac: String) : Boolean {
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val bluetoothDevice = adapter.getRemoteDevice(mac)
        return createBind(bluetoothDevice)
    }

    fun unpair(mac: String) : Boolean{
        val adapter = BluetoothAdapter.getDefaultAdapter()
        val bluetoothDevice = adapter.getRemoteDevice(mac)
        return removeBind(bluetoothDevice)
    }

    fun createBind(device: BluetoothDevice?): Boolean {
        var bRet = false
        if (Build.VERSION.SDK_INT >= 20) {
            bRet = device!!.createBond()
        } else {
            val btClass: Class<*> = device!!.javaClass
            try {
                val createBondMethod = btClass.getMethod("createBond")
                val `object` = createBondMethod.invoke(device) as? Boolean ?: return false
                bRet = `object`
            } catch (var6: java.lang.Exception) {
                var6.printStackTrace()
            }
        }

        return bRet
    }

    fun createBind(device: BluetoothDevice?, transport: Int): Boolean {
        if (device == null) return false
        var bRet = false
        try {
            Log.e("BleViewModel", "进入双模蓝牙绑定")
            val bluetoothDeviceClass = device.javaClass
            val createBondMethod =
                bluetoothDeviceClass.getDeclaredMethod("createBond", transport.javaClass)
            createBondMethod.isAccessible = true
            val obj = createBondMethod.invoke(device, transport)
            if (obj !is Boolean) return false
            bRet = obj
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return bRet
    }

    fun removeBind(device: BluetoothDevice?) : Boolean{
        if(device == null) return false
        var bRet = false
        try{
            val bluetoothDeviceClass = device.javaClass
            val createBondMethod = bluetoothDeviceClass.getMethod("removeBond")
            createBondMethod.isAccessible = true
            val obj = createBondMethod.invoke(device)
            if(obj !is Boolean) return false
            bRet = obj
        }catch (e: Exception){
            e.printStackTrace()
        }
        return bRet
    }
}