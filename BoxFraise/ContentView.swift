import SwiftUI
import MapKit

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var selectedDetent: PresentationDetent = .fraction(0.55)
    @State private var tappedBusiness: Business?
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 53.5461, longitude: -113.4938),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    ))

    var body: some View {
        ZStack {
            Map(position: $cameraPosition) {
                UserAnnotation()

                ForEach(state.approvedBusinesses) { biz in
                    if let coord = biz.coordinate {
                        Annotation("", coordinate: coord) {
                            BusinessPin(approved: true, isCollection: biz.isCollection)
                                .onTapGesture { handlePinTap(biz) }
                        }
                    }
                }

                ForEach(state.unapprovedBusinesses) { biz in
                    if let coord = biz.coordinate {
                        Annotation("", coordinate: coord) {
                            BusinessPin(approved: false, isCollection: biz.isCollection)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
        }
        // Business callout card
        .overlay(alignment: .bottom) {
            if let biz = tappedBusiness {
                BusinessCallout(business: biz) {
                    tappedBusiness = nil
                    animateToLocation(biz)
                    state.selectLocation(biz)
                    selectedDetent = .fraction(0.55)
                } onDismiss: {
                    tappedBusiness = nil
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, UIScreen.main.bounds.height * 0.57)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: tappedBusiness != nil)
            }
        }
        .sheet(isPresented: .constant(true)) {
            SheetContent()
                .presentationDetents(
                    [.fraction(0.08), .fraction(0.55), .large],
                    selection: $selectedDetent
                )
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .interactiveDismissDisabled()
                .presentationCornerRadius(16)
        }
        .onChange(of: state.activeLocation) { _, loc in
            guard let loc, let coord = loc.coordinate else { return }
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: coord.latitude - 0.003, longitude: coord.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
            selectedDetent = .fraction(0.55)
        }
        .onChange(of: state.pendingScreen) { _, screen in
            guard let screen else { return }
            switch screen {
            case "order-history": state.panel = .orderHistory
            case "popups":        state.panel = .popups
            case "profile":       state.panel = state.isSignedIn ? .profile : .auth
            case "verify":        state.panel = .nfcVerify
            default:              state.panel = .home
            }
            state.pendingScreen = nil
            selectedDetent = .fraction(0.55)
        }
    }

    private func handlePinTap(_ biz: Business) {
        if biz.isApproved {
            tappedBusiness = biz
        } else {
            // Unapproved — show partner detail in sheet
            state.panel = .partnerDetail(biz)
            selectedDetent = .fraction(0.55)
        }
    }

    private func animateToLocation(_ biz: Business) {
        guard let coord = biz.coordinate else { return }
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: coord.latitude - 0.003, longitude: coord.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
}

// MARK: - Business Pin

struct BusinessPin: View {
    let approved: Bool
    let isCollection: Bool

    var body: some View {
        if isCollection {
            Circle()
                .fill(approved ? Color(hex: "1C1C1E") : Color.gray.opacity(0.4))
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(approved ? 0.3 : 0.1), radius: 3, y: 1)
        } else {
            Circle()
                .strokeBorder(approved ? Color(hex: "1C1C1E") : Color.gray.opacity(0.4), lineWidth: 1.5)
                .background(Circle().fill(Color.white.opacity(approved ? 1 : 0.5)))
                .frame(width: 10, height: 10)
        }
    }
}

// MARK: - Sheet content router

struct SheetContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    var body: some View {
        ZStack {
            c.background.ignoresSafeArea()
            switch state.panel {
            case .home:                HomePanel()
            case .auth:                AuthPanel()
            case .profile:             ProfilePanel()
            case .popups:              PopupsPanel()
            case .order:               OrderPanel()
            case .orderHistory:        OrderHistoryPanel()
            case .staff:               StaffPanel()
            case .nfcVerify:           NFCVerifyPanel()
            case .walkIn:              WalkInPanel()
            case .partnerDetail(let b): PartnerDetailPanel(business: b)
            }
        }
        .fraiseTheme()
    }
}
