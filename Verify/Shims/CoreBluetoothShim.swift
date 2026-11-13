import Foundation

// ---- CoreBluetooth 最小桩
public enum CBManagerState: Int {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

public final class CBUUID {
    public let uuidString: String
    public init(string: String) { uuidString = string }
    public static let characteristicNotify = CBUUID(string: "x")
}

public final class CBService {
    public var uuid: CBUUID { CBUUID(string: "0000") }
    public var characteristics: [CBCharacteristic]? { nil }
}

public final class CBCharacteristic {
    public struct Properties: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let broadcast = Properties(rawValue: 1)
        public static let read = Properties(rawValue: 2)
        public static let writeWithoutResponse = Properties(rawValue: 4)
        public static let write = Properties(rawValue: 8)
        public static let notify = Properties(rawValue: 16)
        public static let indicate = Properties(rawValue: 32)
        public static let authenticatedSignedWrites = Properties(rawValue: 64)
    }
    public var uuid: CBUUID { CBUUID(string: "0000") }
    public var value: Data? { nil }
    public var properties: Properties { .write }
    public var isNotifying: Bool { true }
}

public enum CBCharacteristicWriteType {
    case withResponse, withoutResponse
}

public final class CBPeripheral {
    public var identifier: UUID { UUID() }
    public var name: String? { nil }
    public var services: [CBService]? { nil }
    public var delegate: CBPeripheralDelegate?
    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {}
    public func discoverCharacteristics(_ uuids: [CBUUID]?, for service: CBService) {}
    public func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic) {}
    public func writeValue(_ data: Data, for characteristic: CBCharacteristic,
                           type: CBCharacteristicWriteType) {}
    public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int { 182 }
}

public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber)
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
}

public protocol CBPeripheralDelegate: AnyObject {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
}

public final class CBCentralManager {
    public init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?) {}
    public var state: CBManagerState { .poweredOn }
    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
    public func stopScan() {}
    public func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {}
    public func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
}

public let CBCentralManagerScanOptionAllowDuplicatesKey = "kCBScanOptionAllowDuplicates"
public let CBAdvertisementDataLocalNameKey = "kCBAdvDataLocalName"
public let CBAdvertisementDataServiceUUIDsKey = "kCBAdvDataServiceUUIDs"
