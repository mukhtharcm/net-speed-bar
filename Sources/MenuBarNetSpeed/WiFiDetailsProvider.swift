import CoreWLAN

struct WiFiDetailsProvider {
    func currentSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }
}
