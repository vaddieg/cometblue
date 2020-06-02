//
//  main.swift
//  cometblue
//
//  Created by vad on 5/30/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//

import Foundation
import CoreBluetooth



print("Started!")

extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
}

class ScanDelegate : NSObject, CBCentralManagerDelegate, CometBlueDeviceDelegate {
	func cometBlue(_ dev: CometBlueDevice, discoveredCharacteristics chars: [CometBlueDevice.Characteristics]){
	}
	
	func cometBlueAuthorized(_ device: CometBlueDevice) {
		device.readParameters(nil)
	}
	
	func cometBlueFinishedReading(_ device: CometBlueDevice) {
		print("read finished")
		
		let encoder = JSONEncoder()
		encoder.outputFormatting = .prettyPrinted
		encoder.dateEncodingStrategy = .iso8601
		let jsonData = try! encoder.encode(device)
		let jsonString = String(data: jsonData, encoding: .utf8)!
		print(jsonString)
		
		exit(0)
	}
	
	func cometBlueFinishedWriting(_ device: CometBlueDevice) {
		//ignre
	}
	
	var peripheral : CBPeripheral?
	var central : CBCentralManager?
	var processed = Set<UUID>()
	
	var device : CometBlueDevice?
	
	let cometService = [CBUUID(string:CometBlueDevice.discoveryUUID)]
	
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		//Look only for comet blue devices
		central.scanForPeripherals(withServices: cometService, options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
		self.central = central
	}
	
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {

		if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String  {
			print("Discovered matching device w/ name: \(localName)")
		}
		
		if processed.contains(peripheral.identifier) { return }
			//debugPrint("Discovered: \(peripheral) data \(advertisementData)")
		print("comet device \(peripheral.identifier) signal:\(RSSI)")
		if RSSI.int32Value < -85 {
			print("too weak signal, skipping connect")
			return
		}
			
		processed.insert(peripheral.identifier)
		
		central.stopScan()
		
		self.peripheral = peripheral;
		//peripheral.delegate = self
		central.connect(peripheral)
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		
		device = CometBlueDevice()
		device!.linkToConnectedPeripheral(peripheral)
		device!.delegate = self
	}

}

let delegate = ScanDelegate()
let manager = CBCentralManager(delegate: delegate, queue: DispatchQueue.global())

sleep(160)


			//DBG call
//			DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
//				print("HACKING...")
//				self.saveTemeratures()
//			}
