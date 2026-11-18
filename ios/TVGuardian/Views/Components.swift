import SwiftUI

struct StatusBadge: View {
    var status: SupportStatus
    var body: some View {
        Label(status.rawValue.capitalized, systemImage: status == .supported ? "checkmark.circle" : status == .unsupported ? "minus.circle" : "questionmark.circle")
            .font(.caption.weight(.semibold)).foregroundStyle(status == .supported ? Color.teal : status == .unsupported ? .secondary : .orange)
            .padding(.horizontal, 8).padding(.vertical, 5).background(.quaternary, in: Capsule())
    }
}

struct ScopeNote: View {
    var title = "Controller-only enforcement"
    var text = "Rules apply to launches through TV Guardian. The physical remote, other controllers, casting and HDMI devices can bypass them. Set native TV locks separately."
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "info.circle").font(.callout.bold())
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FeatureRow: View {
    var feature: Feature
    var evidence: CapabilityEvidence
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(feature.title).font(.callout.weight(.medium)); Spacer(); StatusBadge(status: evidence.status) }
            Text(evidence.reason).font(.footnote).foregroundStyle(.secondary)
            if let date = evidence.checkedAt { Text("\(evidence.route) • \(date.formatted())").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }
}

struct TVAppIcon: View {
    @EnvironmentObject private var model: GuardianModel
    let app: TVApplication
    var body: some View {
        Group {
            if let data = model.icons[app.id], let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.teal.opacity(0.75)).padding(7) }
        }.frame(width: 44, height: 44).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
    }
}
