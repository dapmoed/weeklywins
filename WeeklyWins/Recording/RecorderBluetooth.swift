@preconcurrency import CoreBluetooth
import SwiftUI
import UIKit

@MainActor
final class RecorderBluetooth: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let shared = RecorderBluetooth()

    private static let serviceID = CBUUID(string: "5C802E33-A13B-4272-B674-BF48F1663900")
    private static let commandID = CBUUID(string: "5C802E33-A13B-4272-B674-BF48F1663901")
    private static let responseID = CBUUID(string: "5C802E33-A13B-4272-B674-BF48F1663902")
    private static let pairingKey = "weeklywins.bluetoothRecorder.id"

    @Published private(set) var pairedID = UserDefaults.standard.string(forKey: RecorderBluetooth.pairingKey).flatMap(UUID.init(uuidString:))
    @Published private(set) var status = "Диктофон не подключён"
    @Published private(set) var isConnected = false

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var command: CBCharacteristic?
    private var response: CBCharacteristic?
    private var wantsPairing = false
    private var needsSync = false
    private var reconnectImmediately = false
    private var ready = false
    private var discoveringServices = false
    private var syncTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var tag: UInt8 = 0
    private var pending: CheckedContinuation<Data, Error>?
    private var reply: RecorderBLEReply?
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    func activate() {
        guard pairedID != nil || wantsPairing else { return }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.weeklywins.recorder.bluetooth"
            ])
        } else if ready {
            scheduleSync()
        } else if let central, central.state == .poweredOn {
            findRecorder(using: central)
        }
    }

    func pair() {
        guard pairedID == nil else { return }
        wantsPairing = true
        status = "Поиск диктофона…"
        activate()
    }

    func forget() {
        wantsPairing = false
        ready = false
        discoveringServices = false
        needsSync = false
        reconnectImmediately = false
        pairedID = nil
        isConnected = false
        UserDefaults.standard.removeObject(forKey: Self.pairingKey)
        reconnectTask?.cancel()
        syncTask?.cancel()
        finishRequest(.failure(CancellationError()))
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        status = "Диктофон не подключён"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            findRecorder(using: central)
        case .unauthorized:
            status = "Разрешите WeeklyWins доступ к Bluetooth в настройках iPhone."
        case .poweredOff:
            status = "Включите Bluetooth на iPhone."
        case .unsupported:
            status = "Bluetooth недоступен на этом устройстве."
        default:
            break
        }
        if central.state != .poweredOn {
            ready = false
            discoveringServices = false
            isConnected = false
            finishRequest(.failure(RecorderSyncError.disconnected))
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let pairedID,
              let devices = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let saved = devices.first(where: { $0.identifier == pairedID }) else { return }
        peripheral = saved
        saved.delegate = self
        if saved.state == .connected { prepare(saved) }
    }

    func centralManager(_ central: CBCentralManager, didDiscover candidate: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let pairedID else {
            if wantsPairing && peripheral == nil { connect(candidate, using: central) }
            return
        }
        if candidate.identifier == pairedID && peripheral == nil { connect(candidate, using: central) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        prepare(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionEnded(peripheral, using: central)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionEnded(peripheral, using: central)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.commandID, Self.responseID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil,
              let command = service.characteristics?.first(where: { $0.uuid == Self.commandID }),
              let response = service.characteristics?.first(where: { $0.uuid == Self.responseID }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        self.command = command
        self.response = response
        peripheral.setNotifyValue(true, for: response)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, characteristic === response else { return }
        guard error == nil, characteristic.isNotifying else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        ready = true
        discoveringServices = false
        scheduleSync()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, characteristic === command, let error else { return }
        if pairedID == nil {
            wantsPairing = false
        }
        finishRequest(.failure(error))
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier, characteristic === response else { return }
        if let error {
            finishRequest(.failure(error))
            return
        }
        guard let frame = characteristic.value else { return }
        if frame == Data([0, 0x84, 0, 0]) {
            scheduleSync()
            return
        }
        guard frame.first == tag, var reply else { return }
        do {
            if let payload = try reply.consume(frame) {
                isConnected = true
                finishRequest(.success(payload))
            } else {
                self.reply = reply
            }
        } catch {
            finishRequest(.failure(error))
        }
    }

    private func findRecorder(using central: CBCentralManager) {
        guard central.state == .poweredOn, pairedID != nil || wantsPairing else { return }
        if let pairedID,
           let known = peripheral ?? central.retrievePeripherals(withIdentifiers: [pairedID]).first {
            if known.state == .connected {
                if !ready { prepare(known) }
            } else if known.state == .disconnected {
                connect(known, using: central)
            }
        } else if peripheral == nil && !central.isScanning {
            status = "Поиск диктофона…"
            central.scanForPeripherals(withServices: [Self.serviceID])
        }
    }

    private func connect(_ device: CBPeripheral, using central: CBCentralManager) {
        central.stopScan()
        peripheral = device
        device.delegate = self
        status = "Ожидаем диктофон…"
        central.connect(device)
    }

    private func prepare(_ device: CBPeripheral) {
        guard !ready, !discoveringServices else { return }
        discoveringServices = true
        peripheral = device
        device.delegate = self
        status = "Подключение к диктофону…"
        device.discoverServices([Self.serviceID])
    }

    private func connectionEnded(_ device: CBPeripheral, using central: CBCentralManager) {
        guard peripheral?.identifier == device.identifier else { return }
        ready = false
        isConnected = false
        discoveringServices = false
        command = nil
        response = nil
        needsSync = false
        syncTask?.cancel()
        finishRequest(.failure(RecorderSyncError.disconnected))

        guard pairedID != nil else {
            wantsPairing = false
            peripheral = nil
            status = "Диктофон не подключён. Можно снова начать сопряжение."
            return
        }
        status = "Ожидаем диктофон…"
        if reconnectImmediately {
            reconnectImmediately = false
            findRecorder(using: central)
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            findRecorder(using: central)
        }
    }

    private func scheduleSync() {
        needsSync = true
        guard ready, syncTask == nil, let device = peripheral else { return }
        needsSync = false
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecorderBluetooth").appendingPathComponent(device.identifier.uuidString)
        let client = RecorderSyncClient(partialDirectory: folder) { [weak self] command, payload in
            guard let self else { throw RecorderSyncError.disconnected }
            let reply = try await self.exchange(command, payload: payload)
            if command == .clock && reply.isEmpty && self.pairedID == nil && self.wantsPairing {
                self.pairedID = device.identifier
                UserDefaults.standard.set(device.identifier.uuidString, forKey: Self.pairingKey)
                self.wantsPairing = false
            }
            return reply
        }

        syncTask = Task {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "RecorderBluetoothImport") { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.syncTask?.cancel()
                    self.finishRequest(.failure(CancellationError()))
                    if self.pairedID != nil, let connected = self.peripheral {
                        self.reconnectImmediately = true
                        self.ready = false
                        self.central?.cancelPeripheralConnection(connected)
                    }
                    self.endBackgroundTask()
                }
            }
            defer {
                endBackgroundTask()
                syncTask = nil
                if needsSync { scheduleSync() }
            }

            status = "Импортируем записи…"
            do {
                let count = try await RecordingService.shared.synchronizeRecorder(using: client)
                isConnected = true
                status = count == 0 ? "Записи импортируются автоматически." : "Импортировано записей: \(count)."
            } catch is CancellationError {
                if ready { status = "Импорт продолжится при следующем запуске." }
            } catch RecorderSyncError.recorderBusy {
                isConnected = true
                status = "Диктофон записывает. Импорт начнётся после остановки."
            } catch {
                if ready {
                    status = error.localizedDescription
                    let interrupted = (error as? RecorderSyncError).map {
                        switch $0 {
                        case .timedOut, .incompleteTransfer: return true
                        default: return false
                        }
                    } ?? false
                    if pairedID == nil || interrupted {
                        ready = false
                        central?.cancelPeripheralConnection(device)
                    }
                }
            }
        }
    }

    private func exchange(_ operation: RecorderBLECommand, payload: Data) async throws -> Data {
        try Task.checkCancellation()
        guard ready, let peripheral, let command, pending == nil else { throw RecorderSyncError.disconnected }
        tag = tag == .max ? 1 : tag + 1
        var packet = Data([tag, operation.rawValue])
        packet.append(payload)
        reply = RecorderBLEReply(tag: tag)

        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let duration: Duration = pairedID == nil ? .seconds(60) : .seconds(12)
            timeout = Task {
                do { try await Task.sleep(for: duration) } catch { return }
                finishRequest(.failure(RecorderSyncError.timedOut))
            }
            peripheral.writeValue(packet, for: command, type: .withResponse)
        }
    }

    private func finishRequest(_ result: Result<Data, Error>) {
        timeout?.cancel()
        timeout = nil
        reply = nil
        let waiting = pending
        pending = nil
        waiting?.resume(with: result)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
