import AppKit
import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            MCleanModalHeader(
                title: "MClean Help",
                subtitle: "Scan safely, review findings, and choose Stage or Trash deliberately."
            ) {
                dismiss()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HelpHeroImage(name: "HelpDashboard")

                    HelpSection(
                        title: "Start With A Scan Mode",
                        systemImage: "bolt",
                        text: "Quick is tuned for common cleanup locations. Deep adds broader review categories. Developer focuses on build products, package caches, simulators, Docker storage, and language tooling caches."
                    )

                    HelpSection(
                        title: "Review Before Cleanup",
                        systemImage: "checklist.checked",
                        text: "Use the results table, filters, previews, duplicate review, and app-leftover grouping to understand what each item is before selecting it."
                    )

                    HelpSection(
                        title: "Use Stage For A Safer Test",
                        systemImage: "tray.and.arrow.down",
                        text: "Stage moves selected files out of their original locations first. Test your apps, then restore staged items, move them to Trash, or delete them permanently from Stage."
                    )

                    HelpHeroImage(name: "HelpSettings")

                    HelpSection(
                        title: "Tune Settings",
                        systemImage: "slider.horizontal.3",
                        text: "Settings store scan options, custom profiles, excluded folders, Stage reminders, scheduled scan reporting, and whether direct Trash actions are shown."
                    )

                    HelpSection(
                        title: "Understand Full Disk Access",
                        systemImage: "lock.shield",
                        text: "MClean can scan normal user folders without Full Disk Access. Grant it only when you want protected locations like Safari, Mail, Messages, backups, and large app containers included."
                    )
                }
                .padding(22)
            }
        }
        .frame(minWidth: 820, minHeight: 640)
    }
}

private struct HelpHeroImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = NSImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        Label("Screenshot unavailable", systemImage: "photo")
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct HelpSection: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
