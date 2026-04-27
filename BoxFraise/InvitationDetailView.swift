import SwiftUI
import MapKit

struct InvitationDetailView: View {
    let invitation: FraiseInvitation

    @Environment(AppState.self) var appState
    @Environment(\.fraiseColors) var c
    @Environment(\.dismiss) var dismiss

    @State private var loading      = false
    @State private var error: String? = nil
    @State private var localStatus  = ""
    @State private var justAccepted = false

    private var effectiveStatus: String {
        localStatus.isEmpty ? invitation.status : localStatus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {

                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(invitation.businessName).font(.mono(11)).foregroundStyle(c.muted).tracking(0.5)
                    Text(invitation.title).font(.mono(20, weight: .medium)).foregroundStyle(c.text)
                }

                // Description
                if let desc = invitation.description, !desc.isEmpty {
                    Text(desc).font(.mono(13)).foregroundStyle(c.muted).lineSpacing(5)
                }

                // Details
                CardRows(rows: [
                    "status":    effectiveStatus,
                    "price":     "CA$\(invitation.priceCents / 100)",
                    "seats":     "\(invitation.seatsClaimed) / \(invitation.maxSeats)",
                    "date":      invitation.eventDate ?? "tbd — set when threshold met",
                    "threshold": "\(invitation.minSeats) minimum",
                ])

                // Map — only shown when event is confirmed and location is set
                if invitation.isConfirmed, let lat = invitation.lat, let lng = invitation.lng {
                    locationCard(lat: lat, lng: lng)
                }

                if let error { ErrorText(message: error) }

                actionButtons
            }
            .padding(Spacing.lg)
        }
        .background(c.background)
        .fraiseNav("invitation")
    }

    // MARK: - Location card

    private func locationCard(lat: Double, lng: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            if let loc = invitation.locationText {
                SectionLabel(text: "location")
                Text(loc).font(.mono(13)).foregroundStyle(c.text)
            }
            Map(initialPosition: .region(region)) {
                Marker(invitation.businessName, coordinate: coordinate)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.border, lineWidth: 0.5))
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionButtons: some View {
        let status = effectiveStatus
        if justAccepted {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("you're in.")
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(c.text)
                if let balance = appState.member?.creditBalance {
                    Text("\(balance) akène\(balance == 1 ? "" : "s") remaining")
                        .font(.mono(12)).foregroundStyle(c.muted)
                }
                Text("you'll be notified when the date is set.")
                    .font(.mono(12)).foregroundStyle(c.muted)
                GhostButton(label: "decline (akène returned)") { Task { await decline() } }
            }
        } else if status == "pending" {
            VStack(spacing: Spacing.sm) {
                Text("accepting spends 1 akène. you have \(appState.member?.creditBalance ?? 0).")
                    .font(.mono(11)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading)
                PrimaryButton(label: "accept →", loading: loading) { Task { await accept() } }
                GhostButton(label: "decline") { Task { await decline() } }
            }
        } else if status == "accepted" {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("you're in.")
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .foregroundStyle(c.text)
                Text("you'll be notified when the date is set.")
                    .font(.mono(12)).foregroundStyle(c.muted)
                GhostButton(label: "decline (akène returned)") { Task { await decline() } }
            }
        } else if status == "confirmed" {
            CardRows(rows: ["confirmed": invitation.eventDate ?? "date tbd"])
        }
    }

    private func accept() async {
        guard let token = Keychain.memberToken else { return }
        loading = true; error = nil
        do {
            try await APIClient.shared.acceptInvitation(eventId: invitation.eventId, token: token)
            localStatus  = "accepted"
            justAccepted = true
            await appState.refreshMe()
            await appState.refreshInvitations()
        }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func decline() async {
        guard let token = Keychain.memberToken else { return }
        loading = true; error = nil
        do { try await APIClient.shared.declineInvitation(eventId: invitation.eventId, token: token)
             await appState.refreshInvitations(); await appState.refreshMe(); dismiss() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}
