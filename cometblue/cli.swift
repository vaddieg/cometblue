//
//  cli.swift
//  cometblue
//
//  Created by vad on 6/2/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//

import Foundation
import CoreBluetooth

/// Parses command-line arguments and serves CB delegate
class CLIProvider : NSObject, CBCentralManagerDelegate, CometBlueDeviceDelegate {
	/// Supported commands
	enum Command : String {
		case discover
		case get
		case set
		case backup
		case restore
	}
	
	/// Parsed arguments store
	let command : Command
	var deviceID : String?
	var options = [String:String]()
	var writeValue : String?
	
	private var rssiThreshold : Int?
	private var printJSON = false
	
	/// Corebluetooth stuff
	private let queue: DispatchQueue = DispatchQueue.global()
	private var manager : CBCentralManager?
	private var peripheral : CBPeripheral?
	private let jobDone = NSCondition()
	private var device : CometBlueDevice?
	private var finished = false
	private var error : Error?
	
	// MARK: - initialize
	
	init(with args:[String]) throws {
		guard args.count > 1 else {
			throw CLIError.genericError
		}
		
		guard let cmd = Command(rawValue:args[1]) else {
			throw CLIError.unknownCommand(cmd: args[1])
		}
		command = cmd
		var optionsStartIndex = 0
		
		switch command {
		case .discover:
			deviceID = nil
			optionsStartIndex = 2
		default:
			guard args.count > 2 else { throw CLIError.missingDeviceArg}
			deviceID = args[2]
			optionsStartIndex = 3
		}
		// parse option pairs
		var i = optionsStartIndex
		while i < args.count-1 {
			options[args[i]] = args[i+1]
			i = i+2
		}
		
		// validate options are applicable for the COMMAND
		let allowed = Set<String>(CLIProvider.validOptions[command]!)
		let specified = Set<String>(options.keys)
		let unknown = specified.subtracting(allowed)
		guard unknown.count == 0 else {
			throw CLIError.unknownOption(opt: "\(unknown.randomElement()!) not suported for \(command.rawValue)")
		}
		
		// value for write ops
		if command == .set {
			// required argumet, since bulk write isn't supported
			guard options["-k"] != nil else {
				throw CLIError.wrongOptionValue(opt: "-k", val: "value is missing")
			}
			guard i == args.count-1 else {
				throw CLIError.noValueToWrite
			}
			writeValue = args.last
		}
		
		super.init()
	}
	
	/// Main thread waits inside thin func until job done or failed
	func start() throws {
		jobDone.lock()
		manager = CBCentralManager(delegate: self, queue: queue)

		while (!finished && error == nil) {
			jobDone.wait(until: Date(timeIntervalSinceNow: 1))
		}
		jobDone.unlock()
		if let toThrow = error {
			throw toThrow
		}
	}
	
	/// Let program exit normally or w/ error
	private func interrupt(err : Error?) {
		error = err
		finished = true
		jobDone.signal()
	}
	
	/// Launch device discovery w/ specified timeout
	private func startScan(timeout deadline: UInt?) {
		//Setup timeout timer
		if let timeout = deadline {
			queue.asyncAfter(deadline: .now() + Double(timeout)) {
				switch self.command {
				case .discover: /// Timeout - normal interrupt for DISCOVER command
					print(self.printJSON ? "}" :  "--- Discovery finished in \(Int(timeout)) sec ----")
					self.interrupt(err: nil)
				default: // Error for other commands
					self.interrupt(err: CLIError.timeoutError(time: timeout))
				}
			}
		}
		
		let cometService = [CBUUID(string:CometBlueDevice.discoveryUUID)]
		manager!.scanForPeripherals(withServices: cometService, options: [CBCentralManagerScanOptionAllowDuplicatesKey : false])
	}
	
	/// on success, central:didConnect is called
	private func connect(per : CBPeripheral) {
		peripheral = per
		manager!.connect(per)
	}
	
	private func proceedCommand() {
		// apply -f
		if effectiveValue("-f") == "json" {
			printJSON = true;
		}
		
		guard let timeout = UInt(effectiveValue("-t")) else {
			interrupt(err:CLIError.wrongOptionValue(opt: "-t", val: effectiveValue("-t"))); return
		}
		
		switch command {
		case .discover:
			
			guard let threshold = Int(effectiveValue("-s")) else {
				interrupt(err:CLIError.wrongOptionValue(opt: "-s", val: effectiveValue("-s"))); return
			}
			rssiThreshold = threshold
			
			print(printJSON ? "{" : "--- Discovery started ----")
			startScan(timeout: timeout)
			
		default:
			guard deviceID! != "auto" else {
				print("Connecting to best device...")
				startScan(timeout: timeout)
				return
			}
			/// Periferal can be retrieved w/o scan if connected previously/cached
			let ids = [UUID(uuidString: deviceID!)!]
			let cachedPeripherals = manager!.retrievePeripherals(withIdentifiers:ids)
			
			guard cachedPeripherals.count == 1 else {
				print("device not cached, rediscovering...")
				startScan(timeout: timeout)
				return
			}
			
			print("Connecting to cached...")
			connect(per: cachedPeripherals[0])
			
		}
	}
	
	
	// MARK: CBCentralManagerDelegate
	
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		self.manager = central
		
		switch central.state {
		case .poweredOn:
			proceedCommand()
		default:
			interrupt(err: CLIError.bluetoothError)
		}
	}

	func centralManager(_ ctrl: CBCentralManager, didDiscover perif: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
		
		// Pure Discovery command if deviceID not specified
		guard deviceID != nil || RSSI.int32Value >= rssiThreshold! else {
			debugPrint("Skipped weak signal device")
			return
		}
		/// There is specific device to connect given
		if let deviceToConnect = deviceID {
			if deviceID == "auto" ||
				perif.identifier.uuidString.caseInsensitiveCompare(deviceToConnect) == .orderedSame
			{
				manager!.stopScan()
				print("Connecting...")
				connect(per: perif)
				return
			}
		}
		/// Print or store discovery
		print("\(perif.identifier) signal:\(RSSI)")
	}
	
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		device = CometBlueDevice()
		guard let pincode = UInt(effectiveValue("-p")) else {
			interrupt(err: CLIError.wrongOptionValue(opt: "-p", val: effectiveValue("-p")))
			return
		}
		
		device!.linkToConnectedPeripheral(peripheral, pin: pincode)
		device!.delegate = self
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		interrupt(err: error ?? CLIError.bluetoothError)
	}
	
	// MARK: CometBlueDeviceDelegate
	
	func cometBlue(_ device: CometBlueDevice, discoveredCharacteristics chars: [CometBlueDevice.Characteristics]) {	}
	
	func cometBlueAuthorized(_ device: CometBlueDevice) {
		let keyPath = effectiveValue("-k")
		var toRead = Optional([CometBlueDevice.Characteristics]())

		switch command {
		case .get:
			
			switch keyPath {
			case let path where path.hasPrefix("status"):
				toRead!.append(.status)
			case let path where path.hasPrefix("temperatures"):
				toRead!.append(.temperatures)
			case "batteryStatus":
				toRead!.append(.battery)
			case "deviceDate":
				toRead!.append(.dateTime)
			default:
				/// read fcking all
				toRead = nil
			}
			
			device.readParameters(toRead)
			
		case .set:
			// For some operations you need to read first
			// but leave it for now...
			var toWrite = [CometBlueDevice.Characteristics]()
			guard let val = writeValue else { return }
			
			switch keyPath {
			case "dateTime":
				toWrite.append(.dateTime)
			case "status.childlock":
				device.status = val == "true" ? [.childlock] : []
				toWrite.append(.status)
			default:
				print("Write w/o prior fetch isn't yet supported")
			}
			
			
			device.writeParamers(toWrite) //TODO
		default:
			print("todo ")
		}
	}
	
	func cometBlueFinishedReading(_ device: CometBlueDevice) {
		//todo respect isJson and keypath
		let encoder = JSONEncoder()
		encoder.outputFormatting = .prettyPrinted
		encoder.dateEncodingStrategy = .iso8601
		let jsonData = try! encoder.encode(device)
		let jsonString = String(data: jsonData, encoding: .utf8)!
		print(jsonString)
		
		interrupt(err: nil)
	}
	
	func cometBlueFinishedWriting(_ device: CometBlueDevice) {
		
		interrupt(err: nil)
	}
	
	static let validOptions = [
		Command.discover :	["-t", "-s", "-f"],
		Command.get : 		["-t", "-p", "-k", "-f"],
		Command.set : 		["-t", "-p", "-k"],
		Command.backup : 	["-p", "-o"],
		Command.restore : 	["-p", "-i"]
	]
	
	static let defaultValues = [
		"-t" : "60",
		"-s" : "-80",
		"-k" : "",
		"-p" : "0",
		"-f" : "human",
		"-o" : "backup.json",
		"-i" : "backup.json"
	]
	
	/// Provides value for option or default if not specified
	/// TODO use generics
	private func effectiveValue(_ option : String) -> String {
		return options[option] ?? CLIProvider.defaultValues[option] ?? ""
	}
	
	public enum CLIError : Error {
		case genericError
		case unknownCommand(cmd: String)
		case missingDeviceArg
		case unknownOption(opt: String)
		case wrongOptionValue(opt: String, val: String)
		case noValueToWrite
		case bluetoothError
		case timeoutError(time: UInt)
		
		var description : String {
			get {
				switch self {
				case .genericError: 			return "Generic Error"
				case .unknownCommand(let cmd):	return "Unknown command \(cmd)"
				case .missingDeviceArg:			return "Device_id is not specified"
				case .unknownOption(let opt):	return "Unknown option \(opt)"
				case .noValueToWrite:			return "Specify value to write"
				case .bluetoothError:			return "Bluetooth is unavailable"
				case .timeoutError(let time):	return "Failed to connect in \(time) seconds"
				case .wrongOptionValue(let opt, let val): return "Bad value '\(val)' for option \(opt)"
				//default:						return "Unknown Error"
				}
			}
		}
	}
	
}
