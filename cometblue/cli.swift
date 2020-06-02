//
//  cli.swift
//  cometblue
//
//  Created by vad on 6/2/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//

import Foundation
import CoreBluetooth

class CLIProvider : NSObject, CBCentralManagerDelegate, CometBlueDeviceDelegate {
	enum Command : String {
		case discover
		case get
		case set
		case backup
		case restore
	}
	
	let command : Command
	var deviceID : String?
	var options = [String:String]()
	var writeValue : String?
	
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
		// parse options
		var i = optionsStartIndex
		while i < args.count-1 {
			options[args[i]] = args[i+1]
			i = i+2
		}
		
		// validate options
		let allowed = Set<String>(CLIProvider.validOptions[command]!)
		let specified = Set<String>(options.keys)
		let unknown = specified.subtracting(allowed)
		guard unknown.count == 0 else {
			throw CLIError.unknownOption(opt: "\(command.rawValue): argument \(unknown.randomElement()!) is not suported")
		}
		
		// value for write ops
		if command == .set {
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
	
	
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		
	}
	
	func cometBlue(_ device: CometBlueDevice, discoveredCharacteristics chars: [CometBlueDevice.Characteristics]) {
		
	}
	
	func cometBlueAuthorized(_ device: CometBlueDevice) {
		
	}
	
	func cometBlueFinishedReading(_ device: CometBlueDevice) {
		
	}
	
	func cometBlueFinishedWriting(_ device: CometBlueDevice) {
		
	}
	
	static let validOptions = [
		Command.discover : ["-t", "-s"],
		Command.get : ["-p", "-k", "-f"],
		Command.set : ["-p", "-k", "-f"],
		Command.backup : ["-p", "-o"],
		Command.restore : ["-p", "-i"]
	]
	
	public enum CLIError : Error {
		case genericError
		case unknownCommand(cmd: String)
		case missingDeviceArg
		case unknownOption(opt: String)
		case wrongOptionValue(opt: String, val: String)
		case noValueToWrite
		
		var description : String {
			get {
				switch self {
				case .genericError: 			return "Generic Error"
				case .unknownCommand(let cmd):	return "Unknown command \(cmd)"
				case .missingDeviceArg:			return "Device_id is not specified"
				case .unknownOption(let opt):	return "Unknown option \(opt)"
				case .noValueToWrite:			return "Specify value to write"
				default:						return "Unknown Error"
				}
			}
		}
	}
	
	public static func printUsage() {
		
	}
}
