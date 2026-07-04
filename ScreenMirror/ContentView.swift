import SwiftUI
import ReplayKit

struct ContentView: View {
    @AppStorage("android_ip", store: UserDefaults(suiteName: "group.com.hdhvxud.ScreenMirror"))
    private var androidIP: String = "192.168.42.100"
    @AppStorage("android_port", store: UserDefaults(suiteName: "group.com.hdhvxud.ScreenMirror"))
    private var androidPort: String = "12345"
    @State private var showPicker = false

    var body: some View {
        VStack {
            TextField("Android IP", text: $androidIP)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            TextField("Port", text: $androidPort)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            Button("Start Broadcast") {
                showPicker = true
            }
        }
        .padding()
        .broadcastPicker(isPresented: $showPicker,
                         preferredExtensionIdentifier: nil)
    }
}