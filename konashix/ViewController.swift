// Copyright (c) 2015, Takashi Toyoshima <toyoshim@gmail.com>
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// The views and conclusions contained in the software and documentation are those
// of the authors and should not be interpreted as representing official policies,
// either expressed or implied, of the FreeBSD Project.
//

import Cocoa
import CoreBluetooth
import Foundation

class ViewController: NSViewController, CBPeripheralManagerDelegate {

    private enum DownloadState {
        case Idle
        case Prepare
        case Download
    }

    private var manager : CBPeripheralManager? = nil

    private var wsUpgradeCharacteristicControlPoint : CBMutableCharacteristic? = nil
    private var wsUpgradeCharacteristicData : CBMutableCharacteristic? = nil
    private var wsUpgradeCharacteristicAppInfo : CBMutableCharacteristic? = nil
    private var wsUpgradeService : CBMutableService? = nil

    private var advertising = false

    private var state = DownloadState.Idle

    private let wsUpgradeServiceUUID = CBUUID(string: "9E5D1E47-5C13-43A0-8635-82AD38A1386F")
    private let wsUpgradeCharacteristicControlPointUUID = CBUUID(string: "E3DD50BF-F7A7-4E99-838E-570A086C666B")
    private let wsUpgradeCharacteristicDataUUID = CBUUID(string: "92E86C7A-D961-4091-B74F-2409E72EFE36")
    private let wsUpgradeCharacteristicAppInfoUUID = CBUUID(string: "347F7608-2E2D-47EB-91E9-75D4EDC4DE3B")
    private let wsUpgradeCharacteristicAppInfoKonashiUUID = CBUUID(string: "347F7608-2E2D-47EB-913B-75D4EDC4DE3B")

    private let wsUpgradeCommandPrepareDownload : UInt8 = 1
    private let wsUpgradeCommandDownload : UInt8 = 2
    private let wsUpgradeCommandVerify : UInt8 = 3

    private let wsUpgradeStatusOk : UInt8 = 0

    private func log(message: String) {
        print("\(state): \(message)")
    }

    private func ack() {
        if wsUpgradeCharacteristicControlPoint == nil {
            return
        }
        manager?.updateValue(NSData(bytes: [wsUpgradeStatusOk], length: 1),
                             forCharacteristic: wsUpgradeCharacteristicControlPoint!,
                             onSubscribedCentrals: nil)
    }

    private func processControlPoint(data: NSData) {
        log("\(data)")
        switch state {
        case .Idle:
            return handlePrepare(data)
        case .Prepare:
            return handleDownload(data)
        case .Download:
            return handleVerify(data)
        }
    }

    private func processData(data: NSData) {
        if state != .Download {
            log("unexpected data transfer")
            return
        }
        // length <= 20
        log("receiving data(length=\(data.length))")
    }

    private func handlePrepare(data: NSData) {
        if data.length != 1 {
            return log("unexpected data length: \(data.length)")
        }
        var value = Array<UInt8>(count: 1, repeatedValue: 0)
        data.getBytes(&value, length: 1)
        if value[0] != wsUpgradeCommandPrepareDownload {
            return log("unexpected command: \(value[0])")
        }
        state = .Prepare
        return ack()
    }

    private func handleDownload(data: NSData) {
        if data.length != 5 {
            return log("unexpected data length: \(data.length)")
        }
        var value = Array<UInt8>(count: 5, repeatedValue: 0)
        data.getBytes(&value, length: 5)
        if value[0] != wsUpgradeCommandDownload {
            return log("unexpected command: \(value[0])")
        }
        var length = 0 as UInt32
        for i in 0...3 {
            length *= 256;
            length += UInt32(value[4 - i])
        }
        log("binary length: \(length)")
        state = .Download
        return ack()
    }

    private func handleVerify(data: NSData) {
        if data.length != 5 {
            return log("unexpected data length: \(data.length)")
        }
        var value = Array<UInt8>(count: 5, repeatedValue: 0)
        data.getBytes(&value, length: 5)
        if value[0] != wsUpgradeCommandVerify {
            return log("unexpected command: \(value[0])")
        }

        // value[1:4] is 32-bit CRC

        state = .Idle
        return ack()
    }

    // NSViewController:
    override func viewDidLoad() {
        super.viewDidLoad()

        // Construct service information.
        wsUpgradeCharacteristicControlPoint = CBMutableCharacteristic(
            type: wsUpgradeCharacteristicControlPointUUID,
            properties: [CBCharacteristicProperties.Write, CBCharacteristicProperties.Notify, CBCharacteristicProperties.Indicate],
            value: nil,
            permissions: [CBAttributePermissions.Writeable])

        wsUpgradeCharacteristicData = CBMutableCharacteristic(
            type: wsUpgradeCharacteristicDataUUID,
            properties: [CBCharacteristicProperties.Write],
            value: nil,
            permissions: [CBAttributePermissions.Writeable])

        let appInfo = [0xff, 0xff, 0x01, 0x00] as [UInt8]
        wsUpgradeCharacteristicAppInfo = CBMutableCharacteristic(
            type: wsUpgradeCharacteristicAppInfoKonashiUUID,
            properties: [CBCharacteristicProperties.Read],
            value: NSData(bytes: appInfo, length: appInfo.count),
            permissions: [CBAttributePermissions.Readable])

        wsUpgradeService = CBMutableService(type: wsUpgradeServiceUUID, primary: true)
        wsUpgradeService!.characteristics = [wsUpgradeCharacteristicControlPoint!, wsUpgradeCharacteristicData!, wsUpgradeCharacteristicAppInfo!]

        manager = CBPeripheralManager(delegate: self, queue: nil)
        manager!.addService(wsUpgradeService!)
    }

    override var representedObject: AnyObject? {
        didSet {
        }
    }

    // CBPeripheralManagerDelegate:
    func peripheralManagerDidUpdateState(peripheral : CBPeripheralManager) {
        if peripheral.state != .PoweredOn {
            peripheral.stopAdvertising()
            advertising = false
            return
        }

        if advertising {
            return
        }

        // Start advertising.
        let advertisementData:[String:AnyObject!] = [
            CBAdvertisementDataLocalNameKey: "konashix"]
        peripheral.startAdvertising(advertisementData)
        advertising = true
    }

    func peripheralManager(peripheral : CBPeripheralManager, central : CBCentral, didSubscribeToCharacteristic characteristic : CBCharacteristic) {
        state = .Idle
    }

    func peripheralManager(peripheral : CBPeripheralManager, didReceiveWriteRequests requests : [CBATTRequest]) {
        for request in requests {
            if request.value == nil {
                log("empty command")
                continue
            }
            if request.characteristic.UUID.isEqual(wsUpgradeCharacteristicControlPointUUID) {
                processControlPoint(request.value!)
            } else if request.characteristic.UUID.isEqual(wsUpgradeCharacteristicDataUUID) {
                processData(request.value!)
            } else {
                log("didReceiveWriteRequests for unexpected characteristic: \(request)")
            }
            peripheral.respondToRequest(request, withResult: CBATTError.Success)
        }
    }
}
