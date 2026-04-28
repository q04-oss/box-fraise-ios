import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c
    @State private var selectedDetent: PresentationDetent = .fraction(0.12)
    @State private var tappedBusiness: Business?
    @State private var locationManager = FraiseLocationManager()
    @State private var didCentreOnUser = false
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
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
        }
        // User location re-centre button
        .overlay(alignment: .bottomTrailing) {
            if locationManager.coordinate != nil {
                Button {
                    Haptics.impact(.light)
                    guard let coord = locationManager.coordinate else { return }
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                        ))
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                }
                .padding(.trailing, Spacing.md)
                .padding(.bottom, UIScreen.main.bounds.height * 0.15)
            }
        }
        // Business callout card
        .overlay(alignment: .bottom) {
            if let biz = tappedBusiness {
                BusinessCallout(business: biz) {
                    Haptics.impact(.medium)
                    tappedBusiness = nil
                    animateToLocation(biz)
                    state.selectLocation(biz)
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
                    [.fraction(0.12), .fraction(0.5), .large],
                    selection: $selectedDetent
                )
                .presentationDragIndicator(.hidden)
                .presentationBackground(.regularMaterial)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
                .interactiveDismissDisabled()
                .presentationCornerRadius(24)
        }
        .onChange(of: state.activeLocation) { _, loc in
            guard let loc, let coord = loc.coordinate else { return }
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: coord.latitude - 0.003, longitude: coord.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
            selectedDetent = .fraction(0.5)
        }
        .onChange(of: locationManager.coordinate) { _, coord in
            guard let coord else { return }
            state.userLocation = coord
            // Centre on user only once on first fix, unless a location is already selected
            if !didCentreOnUser && state.activeLocation == nil {
                didCentreOnUser = true
                withAnimation {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                    ))
                }
            }
        }
        .onChange(of: state.requestedDetent) { _, frac in
            if let frac {
                selectedDetent = .fraction(frac)
                state.requestedDetent = nil
            }
        }
        .onChange(of: state.businesses) { _, businesses in
            // Once businesses load, if we still have no user location centre on nearest
            guard !businesses.isEmpty, !didCentreOnUser, state.userLocation == nil,
                  let nearest = state.nearestCollection, let coord = nearest.coordinate else { return }
            didCentreOnUser = true
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                ))
            }
        }
        .onChange(of: state.pendingScreen) { _, screen in
            guard let screen else { return }
            switch screen {
            case "order-history":    state.panel = .orderHistory
            case "popups":           state.panel = .popups
            case "profile":          state.panel = state.isSignedIn ? .profile : .auth
            case "verify":           state.panel = .nfcVerify
            case "standingOrders":   state.panel = state.isSignedIn ? .standingOrders : .auth
            case "inbox":            state.panel = state.isSignedIn ? .fraiseInbox : .auth
            case "referrals":        state.panel = state.isSignedIn ? .referrals : .auth
            case "meet":             state.panel = state.isSignedIn ? .meet : .auth
            default:                 state.panel = .home
            }
            state.pendingScreen = nil
            selectedDetent = .fraction(0.55)
        }
    }

    private func handlePinTap(_ biz: Business) {
        Haptics.impact(.light)
        if biz.isApproved {
            tappedBusiness = biz
        } else {
            state.panel = .partnerDetail(biz)
            selectedDetent = .fraction(0.5)
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
    @Environment(\.fraiseColors) private var c
    let approved: Bool
    let isCollection: Bool

    var body: some View {
        if approved && isCollection {
            Teardrop()
                .fill(c.text)
                .frame(width: 22, height: 28)
                .overlay {
                    Circle()
                        .fill(c.background)
                        .frame(width: 7, height: 7)
                        .offset(y: -3)
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        } else if approved {
            Teardrop()
                .stroke(c.text, lineWidth: 1.5)
                .background(Teardrop().fill(c.background))
                .frame(width: 16, height: 20)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        } else {
            Teardrop()
                .stroke(c.muted.opacity(0.4), lineWidth: 1)
                .background(Teardrop().fill(c.background.opacity(0.7)))
                .frame(width: 13, height: 17)
        }
    }
}

struct Teardrop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let cx = w / 2
        // Circle radius occupies top ~70% of height
        let r = w * 0.46
        let cy = r + 1
        // Start at tip (bottom centre)
        path.move(to: CGPoint(x: cx, y: h))
        // Left side tangent up to circle
        path.addQuadCurve(
            to: CGPoint(x: cx - r, y: cy),
            control: CGPoint(x: cx - r * 0.8, y: h * 0.7)
        )
        // Top arc (circle)
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Right side tangent down to tip
        path.addQuadCurve(
            to: CGPoint(x: cx, y: h),
            control: CGPoint(x: cx + r * 0.8, y: h * 0.7)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Sheet content router

struct SheetContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.fraiseColors) private var c

    // String ID used to drive identity-based transitions
    private var panelID: String {
        switch state.panel {
        case .home:                return "home"
        case .auth:                return "auth"
        case .profile:             return "profile"
        case .popups:              return "popups"
        case .order:               return "order"
        case .orderHistory:        return "orderHistory"
        case .staff:               return "staff"
        case .nfcVerify:           return "nfcVerify"
        case .walkIn:              return "walkIn"
        case .standingOrders:      return "standingOrders"
        case .fraiseInbox:         return "fraiseInbox"
        case .referrals:           return "referrals"
        case .meet:                return "meet"
        case .partnerDetail(let b): return "partnerDetail-\(b.id)"
        }
    }

    var body: some View {
        ZStack {
            c.background.ignoresSafeArea()
            panelView
                .id(panelID)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 18)),
                    removal:   .opacity.combined(with: .offset(y: -6))
                ))
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: panelID)
        }
        .fraiseTheme()
    }

    @ViewBuilder
    private var panelView: some View {
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
        case .standingOrders:      StandingOrdersPanel()
        case .fraiseInbox:         FraiseInboxPanel()
        case .referrals:           ReferralsPanel()
        case .meet:                MeetPanel()
        case .partnerDetail(let b): PartnerDetailPanel(business: b)
        }
    }
}

// MARK: - Location Manager

@Observable
final class FraiseLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var coordinate: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        manager.stopUpdatingLocation() // one-shot — we only need initial position
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }
}
