import SwiftUI

struct RemoteControlView: View {
    @EnvironmentObject private var model: GuardianModel
    @State private var powerOff = false
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text(model.selectedTV?.name ?? "Select a TV first").font(.title3.bold())
                Text(model.connectionMessage).font(.footnote).foregroundStyle(.secondary)
                ScopeNote(title: "Remote navigation is outside app rules", text: "Home, source and arrow keys can navigate to restricted apps. Guardian rules protect direct Launch buttons only. Use native TV locks for physical and virtual remote navigation.")
                VStack(spacing: 12) {
                    key(.up, icon: "chevron.up", label: "Up")
                    HStack(spacing: 12) { key(.left, icon: "chevron.left", label: "Left"); key(.enter, icon: "checkmark", label: "Select"); key(.right, icon: "chevron.right", label: "Right") }
                    key(.down, icon: "chevron.down", label: "Down")
                }
                HStack { key(.back, icon: "arrow.uturn.backward", label: "Back"); key(.home, icon: "house", label: "Home"); key(.source, icon: "rectangle.on.rectangle", label: "Source") }
                HStack { key(.volumeDown, icon: "speaker.minus", label: "Volume down"); key(.mute, icon: "speaker.slash", label: "Mute"); key(.volumeUp, icon: "speaker.plus", label: "Volume up") }
                HStack { key(.play, icon: "play.fill", label: "Play"); key(.pause, icon: "pause.fill", label: "Pause") }
                Button(role: .destructive) { powerOff = true } label: { Label("Power off", systemImage: "power").padding() }.buttonStyle(.bordered).disabled(model.busy || model.selectedTV == nil)
                Text("Key requests are sent over the authenticated TV channel. Physical effects are unverified. Power-on is available through SmartThings only when that device advertises support and remains reachable.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle("Remote Control")
            .confirmationDialog("Power off this TV?", isPresented: $powerOff, titleVisibility: .visible) { Button("Send power off request", role: .destructive) { model.key(.powerOff) } }
    }
    private func key(_ key: RemoteKey, icon: String, label: String) -> some View {
        Button { model.key(key) } label: { Image(systemName: icon).font(.title2).frame(minWidth: 64, minHeight: 58) }.buttonStyle(.bordered).disabled(model.busy || model.selectedTV == nil).accessibilityLabel(label)
    }
}
