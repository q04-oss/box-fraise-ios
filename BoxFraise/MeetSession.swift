import CoreBluetooth
import Observation

// MARK: - Meet state

enum MeetState: Equatable {
    case idle
    case starting
    case scanning
    case found(token: String)
    case confirming
    case done
    case error(String)

    /// Terminal states require no further user interaction with the session.
    var isTerminal: Bool {
        switch self {
        case .done, .error:                              return true
        case .idle, .starting, .scanning, .found, .confirming: return false
        }
    }
}

// Named type replaces the anonymous (CBPeripheral, Int) tuple so mutation
// sites are readable and the compiler can enforce field access.
private struct DiscoveredPeer {
    let peripheral: CBPeripheral
    let rssi: Int
    // rssi in dBm. Aliased for readability at call sites that care about signal strength.
    var signalStrength: Int { rssi }
}

// MARK: - Session

@Observable
final class MeetSession: NSObject {

    static let serviceUUID   = CBUUID(string: "6F2A15EA-0001-4001-8001-000000000001")
    static let tokenCharUUID = CBUUID(string: "6F2A15EA-0001-4001-8001-000000000002")
    // -65 dBm ≈ 1 metre in open air. The threshold filters out devices in adjacent rooms or on the street.
    // Signal strength varies with environment — walls, bodies, and RF interference all reduce range.
    static let rssiThreshold = -65

    var state: MeetState = .idle
    var myToken: String = ""

    private var peripheral: CBPeripheralManager?
    private var central: CBCentralManager?
    private var characteristic: CBMutableCharacteristic?
    private var discoveredPeers: [UUID: DiscoveredPeer] = [:]

    // MARK: - Lifecycle

    func start(token: String) {
        myToken = token
        state = .starting
        // queue: nil → delegates called on main queue, keeping all state mutations on main thread.
        // CBPeripheral.identifier is stable within a session; may change across app restarts — do not persist.
        peripheral = CBPeripheralManager(delegate: self, queue: nil)
        central    = CBCentralManager(delegate: self, queue: nil)
    }

    /// Idempotent — safe to call multiple times. Resets to .idle regardless of current state.
    func stop() {
        peripheral?.stopAdvertising()
        peripheral?.removeAllServices()
        central?.stopScan()
        for (_, peer) in discoveredPeers { central?.cancelPeripheralConnection(peer.peripheral) }
        peripheral = nil
        central    = nil
        discoveredPeers = [:]
        state = .idle
    }
}

// MARK: - Peripheral delegate

extension MeetSession: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ pm: CBPeripheralManager) {
        guard pm.state == .poweredOn else { return }
        let char = CBMutableCharacteristic(
            type: Self.tokenCharUUID,
            properties: .read,
            value: myToken.data(using: .utf8),
            permissions: .readable
        )
        characteristic = char
        let svc = CBMutableService(type: Self.serviceUUID, primary: true)
        svc.characteristics = [char]
        pm.add(svc)
    }

    func peripheralManager(_ pm: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "fraise",
        ])
    }

    func peripheralManager(_ pm: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == Self.tokenCharUUID {
            request.value = myToken.data(using: .utf8)
            pm.respond(to: request, withResult: .success)
        }
    }
}

// MARK: - Central delegate

extension MeetSession: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ cm: CBCentralManager) {
        guard cm.state == .poweredOn else { return }
        // AllowDuplicates: false — prevents repeated didDiscover calls for the same peripheral.
        // We connect on first discovery only; duplicates would trigger redundant connection attempts.
        cm.scanForPeripherals(withServices: [Self.serviceUUID],
                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        state = .scanning
    }

    func centralManager(_ cm: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi > Self.rssiThreshold,
              discoveredPeers[peripheral.identifier] == nil else { return }
        peripheral.delegate = self
        discoveredPeers[peripheral.identifier] = DiscoveredPeer(peripheral: peripheral, rssi: rssi)
        cm.connect(peripheral)
    }

    func centralManager(_ cm: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ cm: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        discoveredPeers.removeValue(forKey: peripheral.identifier)
    }
}

// MARK: - Peripheral delegate (as central)

extension MeetSession: CBPeripheralDelegate {

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else { return }
        p.discoverCharacteristics([Self.tokenCharUUID], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let char = service.characteristics?.first(where: { $0.uuid == Self.tokenCharUUID }) else { return }
        p.readValue(for: char)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.tokenCharUUID,
              let data = characteristic.value,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty, token != myToken else { return }

        central?.cancelPeripheralConnection(p)
        central?.stopScan()
        state = .found(token: token)
    }
}
