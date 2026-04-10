import CoreWLAN

struct WiFiDetails {
    let ssid: String?
    let interfaceName: String?
}

struct WiFiDetailsProvider {
    func currentDetails() -> WiFiDetails {
        let interface = CWWiFiClient.shared().interface()
        return WiFiDetails(
            ssid: interface?.ssid(),
            interfaceName: interface?.interfaceName
        )
    }
}
