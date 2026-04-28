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
}

// Named type replaces the anonymous (CBPeripheral, Int) tuple so mutation
// sites are readable and the compiler can enforce field access.
private struct DiscoveredPeer {
    let peripheral: CBPeripheral
    let rssi: Int
}

// MARK: - Session

@Observable
final class MeetSession: NSObject {

    static let serviceUUID   = CBUUID(string: "6F2A15EA-0001-4001-8001-000000000001")
    static let tokenCharUUID = CBUUID(string: "6F2A15EA-0001-4001-8001-000000000002")
    static let rssiThreshold = -65  // ~1 metre

    var state: MeetState = .idle
    var myToken: String = ""

    private var peripheral: CBPeripheralManager?
    private var central: CBCentralManager?
    private var characteristic: CBMutableCharacteristic?
    private var discovered: [UUID: DiscoveredPeer] = [:]

    // MARK: - Lifecycle

    func start(token: String) {
        myToken = token
        state = .starting
        // queue: nil → delegates called on main queue, keeping all state mutations on main thread.
        peripheral = CBPeripheralManager(delegate: self, queue: nil)
        central    = CBCentralManager(delegate: self, queue: nil)
    }

    func stop() {
        peripheral?.stopAdvertising()
        peripheral?.removeAllServices()
        central?.stopScan()
        for (_, peer) in discovered { central?.cancelPeripheralConnection(peer.peripheral) }
        peripheral = nil
        central    = nil
        discovered = [:]
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
        cm.scanForPeripherals(withServices: [Self.serviceUUID],
                              options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        state = .scanning
    }

    func centralManager(_ cm: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        guard rssi > Self.rssiThreshold,
              discovered[peripheral.identifier] == nil else { return }
        peripheral.delegate = self
        discovered[peripheral.identifier] = DiscoveredPeer(peripheral: peripheral, rssi: rssi)
        cm.connect(peripheral)
    }

    func centralManager(_ cm: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ cm: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        discovered.removeValue(forKey: peripheral.identifier)
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
