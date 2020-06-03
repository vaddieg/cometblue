//
//  CometBlueDevice.swift
//  cometblue
//
//  Created by vad on 6/1/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//

import Foundation
import CoreBluetooth

public protocol CometBlueDeviceDelegate : class {
	func cometBlue(_ device:CometBlueDevice, discoveredCharacteristics chars:[CometBlueDevice.Characteristics])
	func cometBlueAuthorized(_ device:CometBlueDevice) //from that point you can read and write
	func cometBlueFinishedReading(_ device:CometBlueDevice)
	func cometBlueFinishedWriting(_ device:CometBlueDevice)
}

public class CometBlueDevice : NSObject, CBPeripheralDelegate, Encodable {

	/// Properties
	var batteryStatus : UInt8?
	var deviceDate : Date?
	var status : StatusOptions?
	var temperatures : Temperatures?
	// details not supported
	var dayBlob : Data?
	var holydayBllob : Data?
	
	/// Cache of discovered CBCharacteristic objects
	private var discoveredCharacs = [Characteristics : CBCharacteristic]()
	private	var pin = UInt(0);
	
	var peripheral : CBPeripheral?
	
	/// If no delegate provided, CometBlueDevice reads default values automatically
	weak var delegate : CometBlueDeviceDelegate?
	private let syncQueue: DispatchQueue = DispatchQueue(label:"SerialRW")
	

	var isConnected : Bool {
		get { peripheral != nil ? peripheral?.state == .connected : false }
	}
	
	// what to read and what to write
	let charsToRead = [Characteristics.battery, .dateTime, .temperatures, .status]
	let charsToWrite = [Characteristics.dateTime, .temperatures]
	
	//detect batch RW finish to trigger delegate
	var readsLeft = Set<Characteristics>()
	var writesLeft = Set<Characteristics>()
	
	public func linkToConnectedPeripheral(_ periph : CBPeripheral?, pin: UInt = 0) {
		self.peripheral = periph
		self.pin = pin
		
		if let p = periph {
			print("Connected to: \(p.identifier)")
			p.delegate = self
			p.discoverServices([CBUUID(string: CometBlueDevice.discoveryUUID)])
		}
	}
	
	public func readParameters(_ params:[Characteristics]?) {
		assert(discoveredCharacs.count > 0, "characteristics not yer discovered?")
		syncQueue.sync {
			readsLeft.removeAll()
			let scope = params ?? charsToRead
			for readChar in scope {
				readsLeft.insert(readChar)
				peripheral?.readValue(for: discoveredCharacs[readChar]!)
			}
		}
	}
	
	func writeParamers(_ params:[Characteristics]?) {
		assert(discoveredCharacs.count > 0, "characteristics not yer discovered?")
		syncQueue.sync {
			writesLeft.removeAll()
			let scope = params ?? charsToWrite
			for writeChar in scope {
				writesLeft.insert(writeChar)
				switch writeChar {
				case .dateTime:
					print("sync time with this computer..")
					let date = Date()
					var calendar = Calendar(identifier: .gregorian)
					calendar.timeZone = TimeZone(secondsFromGMT: 0)!
					
					var buf = Array<UInt8>(repeating: 0, count: 5)
					buf[0] = UInt8(calendar.component(.minute, from: date))
					buf[1] = UInt8(calendar.component(.hour, from: date))
					buf[2] = UInt8(calendar.component(.day, from: date))
					buf[3] = UInt8(calendar.component(.month, from: date))
					buf[4] = UInt8(calendar.component(.year, from: date) - 2000)
					let data = Data(bytes: buf, count: buf.count)
					self.peripheral!.writeValue(data, for:discoveredCharacs[.temperatures]!, type:.withResponse)
					deviceDate = date
					
				case .temperatures:
					let bytes = temperatures!.toByteArray()
					let data = Data(bytes: bytes, count: bytes.count)
					self.peripheral!.writeValue(data, for:discoveredCharacs[.temperatures]!, type:.withResponse)
				case .status:
					//var buf = Array<UInt8>(repeating: 0, count: 4)
					let data = Data(bytes: &status, count: 4)
					let subdata = data.subdata(in: 0..<3)
					debugPrint("Resulting subdata \(subdata.count)")
					self.peripheral!.writeValue(subdata, for:discoveredCharacs[.status]!, type:.withResponse)
					//data.copyBytes(to: &buf, count: 3)
					//let intb = UnsafeRawPointer(buf).assumingMemoryBound(to: UInt.self).pointee.littleEndian
					//status = StatusOptions(rawValue: intb)
					
				default:
					print("saving not yet supported for \(writeChar)")
				}
			}
		}
	}
	
	private func reportCommError(err: Error?) {
		print("Error communicating \(peripheral!) error: \(err != nil ? String(describing: err!) : "unknown")")
	}
	
	//MARK: - CBPeripheral delegate -
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard let svcs = peripheral.services, svcs.count == 1 else {
			reportCommError(err: error); return
		}
		
		discoveredCharacs.removeAll()
		let charsWithPin = [Characteristics.sendPin] + charsToRead
		let uuidsToRead = charsWithPin.map { $0.cbuuid }
		peripheral.discoverCharacteristics(uuidsToRead, for: svcs[0])
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
		guard let chars = svc.characteristics, chars.count > 0 else {
			reportCommError(err: error); return
		}
		
		// Save all chars to dict
		for char in chars {
			if let charID = Characteristics(rawValue: char.uuid.uuidString.lowercased()) {
				discoveredCharacs[charID] = char
			} else {
				print("unextected characteristics ID discovered: \(char.uuid)")
			}
		}
		
		guard let pinSend = discoveredCharacs[.sendPin] else {
			print("can't find sendPin characteristics")
			return
		}
		
		peripheral.writeValue(Data(bytes: &pin, count: 4), for: pinSend, type: .withResponse)
		
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor char: CBCharacteristic, error: Error?) {
		guard error == nil else {
			reportCommError(err: error); return
		}
		print("write success")
		
		guard let internChar = Characteristics(rawValue: char.uuid.uuidString.lowercased()) else {
			print("unknown characteristic"); return
		}
		
		switch internChar {
		case .sendPin:
			//read all supported values
			if delegate != nil {
				delegate!.cometBlueAuthorized(self)
			} else {
				readParameters(nil)
			}
		default:
			print("Write success for: \(internChar)")
			writesLeft.remove(internChar)
			if writesLeft.isEmpty {
				delegate?.cometBlueFinishedWriting(self)
			}
		}
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor char: CBCharacteristic, error: Error?) {
		guard let data = char.value, error == nil else {
			reportCommError(err: error); return
		}
							
		// Try mapping to ownt characteristics type
		guard let internChar = Characteristics(rawValue: char.uuid.uuidString.lowercased()) else {
			debugPrint("unknown characteristic"); return
		}
		
		
		switch internChar {
		case .battery:
			batteryStatus = 0
			data.copyBytes(to: &(batteryStatus!), count: 1)
			debugPrint("parsed battery \(batteryStatus!)")
			
		case .status:
			var buf = Array<UInt8>(repeating: 0, count: 4)
			data.copyBytes(to: &buf, count: 3)
			let intb = UnsafeRawPointer(buf).assumingMemoryBound(to: UInt.self).pointee.littleEndian
			status = StatusOptions(rawValue: intb)
			debugPrint("current opts \(status!)")
		case .dateTime:
			var buf = Array<UInt8>(repeating: 0, count: 5)
			data.copyBytes(to: &buf, count: 5)
			var calendar = Calendar(identifier: .gregorian)
			calendar.timeZone = TimeZone(secondsFromGMT: 0)!
	
			let components = DateComponents(year: Int(buf[4]) + 2000,
											month: Int(buf[3]),
											day: Int(buf[2]),
											hour: Int(buf[1]),
											minute: Int(buf[0]),
											second: 0)
			deviceDate = calendar.date(from: components)
			debugPrint("Parsed date \(deviceDate!)")
		
		case .temperatures:
			var buf = Array<UInt8>(repeating: 0, count: 7)
			data.copyBytes(to: &buf, count: 7)
			temperatures = Temperatures(byteArray: buf)
			debugPrint("Parsed temps: \(temperatures!)")
			

			
		default:
			print("Unhandled:"+data.hexDescription)
		}
		
		readsLeft.remove(internChar)
		if readsLeft.isEmpty {
			delegate?.cometBlueFinishedReading(self)
		}
		
	}
	
}

// MARK: - inner types

extension CometBlueDevice {
	/// Comet Blue, EUROprog, other compatible devices can be uniquely discovered w/ this ID
	public static let discoveryUUID = "47e9ee00-47e9-11e4-8939-164230d1df67"
	//static let stdDeviceInfoService = "180a"
	public enum Characteristics : String, CaseIterable { //Unfortunatelly enum of CBUUIDs isn't possible
		case sendPin = 		"47e9ee30-47e9-11e4-8939-164230d1df67"
		case day = 			"47e9ee10-47e9-11e4-8939-164230d1df67" //not yet supported
		case holyday =		"47e9ee20-47e9-11e4-8939-164230d1df67" //not yet supported
		case battery = 		"47e9ee2c-47e9-11e4-8939-164230d1df67"
		case status =		"47e9ee2a-47e9-11e4-8939-164230d1df67" //3bytes?
		case temperatures = "47e9ee2b-47e9-11e4-8939-164230d1df67" //7bytes
		case dateTime =		"47e9ee01-47e9-11e4-8939-164230d1df67"
		case firmw2 = 		"47e9ee2d-47e9-11e4-8939-164230d1df67"
		case lcdTimeout = 	"47e9ee2e-47e9-11e4-8939-164230d1df67"
		// device reports far more characteristics to read/write
		
		var cbuuid : CBUUID { return CBUUID(string: self.rawValue) }
	}
	
	struct StatusOptions : OptionSet, Encodable {
		let rawValue: UInt
		
		static let manualMode = StatusOptions(rawValue: 1)
		static let antifrostActive = StatusOptions(rawValue: 1 << 4)
		static let childlock = StatusOptions(rawValue: 1 << 7)
		static let motorMoving = StatusOptions(rawValue: 1 << 8)
		static let notReady = StatusOptions(rawValue: 1 << 9)
		static let adapting = StatusOptions(rawValue: 1 << 10)
		static let lowBattery = StatusOptions(rawValue: 1 << 11)
		static let tempSatisfied = StatusOptions(rawValue: 1 << 19)
		
		private enum CodingKeys: String, CodingKey {
			case manualMode, antifrostActive, childlock,motorMoving
			case notReady, adapting, lowBattery, tempSatisfied
		}
		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(self.contains(.manualMode), forKey: .manualMode)
			try container.encode(self.contains(.antifrostActive), forKey: .antifrostActive)
			try container.encode(self.contains(.childlock), forKey: .childlock)
			try container.encode(self.contains(.motorMoving), forKey: .motorMoving)
			try container.encode(self.contains(.notReady), forKey: .notReady)
			try container.encode(self.contains(.adapting), forKey: .adapting)
			try container.encode(self.contains(.lowBattery), forKey: .lowBattery)
			try container.encode(self.contains(.tempSatisfied), forKey: .tempSatisfied)
		}
	}
	
	struct Temperatures : Encodable {
		var current = 0.0
		var manual = 0.0
		var targetLow = 0.0
		var targetHi = 0.0
		var offset = 0.0
		var windowDetection = 0
		var windowMinutes = 0
		
		init(byteArray: [UInt8]) {
			let temps = byteArray.map { Int8(bitPattern: $0) }
			current = Double(temps[0]) / 2.0
			manual = Double(temps[1]) / 2.0
			targetLow = Double(temps[2]) / 2.0
			targetHi = Double(temps[3]) / 2.0
			offset = Double(temps[4]) / 2.0
			windowDetection = Int(temps[5])
			windowMinutes = Int(temps[6])
		}
		
		func toByteArray()-> [UInt8] {
			var temps = Array<Int8>(repeating: 0, count: 7)
			temps[0] = -127 //cant write it
			temps[1] = Int8(manual * 2.0)
			temps[2] = Int8(targetLow * 2.0)
			temps[3] = Int8(targetHi * 2.0)
			temps[4] = Int8(offset * 2.0)
			temps[5] = Int8(windowDetection >= Int8.min && windowDetection <= Int8.max ? windowDetection : 0)
			temps[6] = Int8(windowMinutes >= Int8.min && windowMinutes <= Int8.max ? windowMinutes : 0)
			return temps.map { UInt8(bitPattern: $0) }
		}
	}
	
	//MARK: JSON coding
	
	private enum CodingKeys: String, CodingKey {
		case batteryStatus, deviceDate, temperatures, status//, dayBlob, holydayBlob
	}
	
//	public func encode(to encoder: Encoder) {
//
//	}
}
