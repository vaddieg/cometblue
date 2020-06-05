//
//  CometBlueDevice.swift
//  cometblue
//
//  Created by vad on 6/1/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//


import Foundation
import CoreBluetooth

/// Shitty debug NSLog-like function
func DLog(_ items: Any ..., separator: String = " ", terminator: String = "\n") {
	#if DEBUG
	print(Date(),": ", terminator:"")
	for item in items {
		print(item, terminator:"")
		print(separator, terminator:"")
	}
	print("", terminator:terminator)
	#endif
}

public protocol CometBlueDeviceDelegate : class {
	func cometBlue(_ device:CometBlueDevice, discoveredCharacteristics chars:[CometBlueDevice.Characteristics])
	func cometBlueAuthorized(_ device:CometBlueDevice) //from that point you can read and write
	func cometBlueFinishedReading(_ device:CometBlueDevice)
	func cometBlueFinishedWriting(_ device:CometBlueDevice)
	func comentBlue(_ device:CometBlueDevice, gotError err:Error?)
}

/// Supports Codable for backup/restore purposes
public final class CometBlueDevice : NSObject, CBPeripheralDelegate, Codable {

	/// Properties
	var batteryStatus : UInt8?
	var deviceDate : Date?
	var status : StatusOptions?
	var temperatures : Temperatures?
	/// Properties w/ no details supported
	var dayBlob : Data?
	var holydayBlob : Data?
	
	/// Access CBCharacteristic objects by own enum type
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
	let charsToRead = [Characteristics.battery, .dateTime, .temperatures, .status, .day, .holyday]
	let charsToWrite = [Characteristics.status, .day, .holyday, .temperatures, .dateTime]
	
	//detect batch RW finish to trigger delegate
	var readsLeft = Set<Characteristics>()
	var writesLeft = Set<Characteristics>()
	
	/// Main entry
	public func linkToConnectedPeripheral(_ periph : CBPeripheral?, pin: UInt = 0) {
		self.peripheral = periph
		self.pin = pin
		
		if let p = periph {
			print("Connected to: \(p.identifier)")
			p.delegate = self
			DLog("discovering services")
			p.discoverServices([CBUUID(string: CometBlueDevice.discoveryUUID)])
		}
	}
	
	public func readParameters(_ params:[Characteristics]?) {
		assert(discoveredCharacs.count > 0, "characteristics not yer discovered?")
		syncQueue.sync {
			readsLeft.removeAll()
			let scope = params ?? charsToRead
			for readChar in scope {
				guard let cbChar = discoveredCharacs[readChar] else {
					delegate?.comentBlue(self, gotError: DeviceError.notDiscovered(char: readChar)); return
				}
				readsLeft.insert(readChar)
				peripheral?.readValue(for: cbChar)
			}
		}
	}
	
	func writeParamers(_ params:[Characteristics]?) {
		assert(discoveredCharacs.count > 0, "characteristics not yer discovered?")
		syncQueue.sync {
			writesLeft.removeAll()
			let scope = params ?? charsToWrite
			for writeChar in scope {
				guard let cbChar = discoveredCharacs[writeChar] else {
					delegate?.comentBlue(self, gotError: DeviceError.notDiscovered(char: writeChar)); return
				}
				writesLeft.insert(writeChar)
				switch writeChar {
				case .dateTime:
					let date = Date() /// ignore, use only current local date
					var calendar = Calendar(identifier: .gregorian)
					calendar.timeZone = TimeZone(secondsFromGMT: 0)!
					
					var buf = Array<UInt8>(repeating: 0, count: 5)
					buf[0] = UInt8(calendar.component(.minute, from: date))
					buf[1] = UInt8(calendar.component(.hour, from: date))
					buf[2] = UInt8(calendar.component(.day, from: date))
					buf[3] = UInt8(calendar.component(.month, from: date))
					buf[4] = UInt8(calendar.component(.year, from: date) - 2000)
					let data = Data(bytes: buf, count: buf.count)
					self.peripheral!.writeValue(data, for:cbChar, type:.withResponse)
					deviceDate = date
					
				case .temperatures:
					let bytes = temperatures!.toByteArray()
					let data = Data(bytes: bytes, count: bytes.count)
					self.peripheral!.writeValue(data, for:cbChar, type:.withResponse)
				case .status:
					let data = Data(bytes: &status, count: 4)
					let subdata = data.subdata(in: 0..<3)
					self.peripheral!.writeValue(subdata, for:cbChar, type:.withResponse)
				case .day:
					if let dayData = dayBlob {
						self.peripheral!.writeValue(dayData, for:cbChar, type:.withResponse)
					}
				case .holyday:
					if let holyData = holydayBlob {
						self.peripheral!.writeValue(holyData, for:cbChar, type:.withResponse)
					}
				default:
					print("saving not yet supported for \(writeChar)")
				}
			}
		}
	}
	
	private func reportCommError(err: Error?) {
		delegate?.comentBlue(self, gotError: err)
	}
	
	//MARK: - CBPeripheral delegate -
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		guard let svcs = peripheral.services, error == nil && svcs.count == 1 else {
			reportCommError(err: error); return
		}
		DLog("services discovered")
		discoveredCharacs.removeAll()
		let charsWithPin = [Characteristics.sendPin] + charsToRead
		let uuidsToRead = charsWithPin.map { $0.cbuuid }
		peripheral.discoverCharacteristics(uuidsToRead, for: svcs[0])
	}
	
	public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor svc: CBService, error: Error?) {
		guard let chars = svc.characteristics, chars.count > 0 else {
			reportCommError(err: error); return
		}
		
		DLog("characteristics discovered")
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
			DLog("Write success for: \(internChar)")
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
			DLog("unknown characteristic"); return
		}
		
		
		switch internChar {
		case .battery:
			batteryStatus = 0
			data.copyBytes(to: &(batteryStatus!), count: 1)
			DLog("parsed battery \(batteryStatus!)")
			
		case .status:
			var buf = Array<UInt8>(repeating: 0, count: 4)
			data.copyBytes(to: &buf, count: 3)
			let intb = UnsafeRawPointer(buf).assumingMemoryBound(to: UInt.self).pointee.littleEndian
			status = StatusOptions(rawValue: intb)
			DLog("current opts \(status!)")
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
			DLog("Parsed date \(deviceDate!)")
		
		case .temperatures:
			var buf = Array<UInt8>(repeating: 0, count: 7)
			data.copyBytes(to: &buf, count: 7)
			temperatures = Temperatures(byteArray: buf)
			DLog("Parsed temps: \(temperatures!)")
			
		case .day:
			dayBlob = data
			DLog("Read day as blob \(data)")
		case .holyday:
			holydayBlob = data
			DLog("Read holyday as blob \(data)")
			
		default:
			print("Unhandled: \(data) for \(internChar)")
		}
		
		readsLeft.remove(internChar)
		if readsLeft.isEmpty {
			delegate?.cometBlueFinishedReading(self)
		}
		
	}
	
}

// MARK: - inner types

extension CometBlueDevice {
	/// Comet Blue, EUROtronic, other compatible devices can be uniquely discovered w/ this ID
	public static let discoveryUUID = "47e9ee00-47e9-11e4-8939-164230d1df67"
	public static let standardInfoUUID = "180a" // to read GATT-standard manufacturer, fmw. version, etc.
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
	
	struct StatusOptions : OptionSet, Codable {
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
			case rawValue, flags
		}
		
		/// Only for readability purposes
		enum FlagCodingKeys : String, CodingKey {
			case manualMode, antifrostActive, childlock,motorMoving
			case notReady, adapting, lowBattery, tempSatisfied
		}
		
		func encode(to encoder: Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(rawValue, forKey: .rawValue)
			
			var altcont = container.nestedContainer(keyedBy: FlagCodingKeys.self, forKey: .flags)
			try altcont.encode(self.contains(.manualMode), forKey: .manualMode)
			try altcont.encode(self.contains(.antifrostActive), forKey: .antifrostActive)
			try altcont.encode(self.contains(.childlock), forKey: .childlock)
			try altcont.encode(self.contains(.motorMoving), forKey: .motorMoving)
			try altcont.encode(self.contains(.notReady), forKey: .notReady)
			try altcont.encode(self.contains(.adapting), forKey: .adapting)
			try altcont.encode(self.contains(.lowBattery), forKey: .lowBattery)
			try altcont.encode(self.contains(.tempSatisfied), forKey: .tempSatisfied)
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			rawValue = try container.decode(UInt.self, forKey: .rawValue)
		}
		
		init(rawValue: UInt) {
			self.rawValue = rawValue
		}
	}
	
	struct Temperatures : Codable {
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
		case batteryStatus, deviceDate, temperatures, status, dayBlob, holydayBlob
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		
		if batteryStatus != nil { try container.encode(batteryStatus, forKey: .batteryStatus) }
		if deviceDate != nil { try container.encode(deviceDate, forKey: .deviceDate)  }
		if temperatures != nil { try container.encode(temperatures, forKey: .temperatures) }
		if status != nil { try container.encode(status, forKey: .status) }
		
		if let dayData = dayBlob {
			let base64rep = dayData.base64EncodedString()
			try container.encode(base64rep, forKey: .dayBlob)
		}
		
		if let holyData = holydayBlob {
			let base64rep = holyData.base64EncodedString()
			try container.encode(base64rep, forKey: .holydayBlob)
		}
		
	}
	
	convenience public init(from decoder: Decoder) throws {
		self.init()
		let container = try decoder.container(keyedBy: CodingKeys.self)
		
		batteryStatus = try container.decode(UInt8.self, forKey: .batteryStatus)
		deviceDate = try container.decode(Date.self, forKey: .deviceDate)
		temperatures = try container.decode(Temperatures.self, forKey: .temperatures)
		status = try container.decode(StatusOptions.self, forKey: .status)
		
		if let dayStr = try? container.decode(String.self, forKey: .dayBlob) {
			dayBlob = Data(base64Encoded: dayStr)
		}
		
		if let holyStr = try? container.decode(String.self, forKey: .holydayBlob) {
			holydayBlob = Data(base64Encoded: holyStr)
		}
	}
	
	/// MARK: - Errors
	public enum DeviceError : Error {
		case notDiscovered(char : Characteristics)
	}
}
