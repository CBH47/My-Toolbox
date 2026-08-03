package com.example.my_toolbox

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channelName = "toolbox/network"

	private fun describeTransports(caps: NetworkCapabilities?): String {
		if (caps == null) return "none"
		val transports = mutableListOf<String>()
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("wifi")
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("cell")
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("eth")
		if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) transports.add("vpn")
		if (transports.isEmpty()) transports.add("other")
		return transports.joinToString("+")
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getNetworkDiagnostics" -> {
						try {
							val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
							val active = cm.activeNetwork
							val activeCaps = cm.getNetworkCapabilities(active)
							val bound = cm.boundNetworkForProcess
							val boundCaps = cm.getNetworkCapabilities(bound)

							var wifiCount = 0
							var cellCount = 0
							for (network in cm.allNetworks) {
								val caps = cm.getNetworkCapabilities(network)
								if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) wifiCount++
								if (caps?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true) cellCount++
							}

							val info = hashMapOf<String, Any>(
								"active" to describeTransports(activeCaps),
								"bound" to describeTransports(boundCaps),
								"wifiCount" to wifiCount,
								"cellCount" to cellCount
							)
							result.success(info)
						} catch (e: Exception) {
							result.error("DIAG_FAILED", e.message, null)
						}
					}
					"bindToWifiNetwork" -> {
						try {
							val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
							val wifiNetwork = cm.allNetworks.firstOrNull { network ->
								val caps = cm.getNetworkCapabilities(network)
								caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
							}

							if (wifiNetwork != null) {
								val ok = cm.bindProcessToNetwork(wifiNetwork)
								result.success(ok)
							} else {
								result.success(false)
							}
						} catch (e: Exception) {
							result.error("BIND_FAILED", e.message, null)
						}
					}
					else -> result.notImplemented()
				}
			}
	}
}
