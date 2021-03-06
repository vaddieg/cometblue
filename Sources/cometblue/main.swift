//
//  main.swift
//  cometblue
//
//  Created by vad on 5/30/20.
//  Copyright © 2020 Vadym Zimin. All rights reserved.
//

import Foundation
import CoreBluetooth



extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
}

func printUsage() {
	let text = """
	cometblue tool v0.1
	## Usage
	### cometblue discover <options>
	### cometblue [ get | set | backup | restore] <device_id> <options>
	### Commands:
	discover			Scan for compatible BLE devices to find out device_ids
	get				Read value(s) from device
	set				Write value(s) to device
	backup			Backups device settings to specified file
	restore			Restores device settings from specified file
	### Options:
	-t [timeout]		Timeout for 'discover' command, default is 60s
	-s [threshold]		Signal level threshold for 'discover', default = -80dB
	-p [pin]			Pin to access the device, default = 0
	-k [key.path]		Keypath of the value for reading or writing, default is root "."
	-f [human | json] 	Specifies human readable or json as output format for 'get' command, default is 'human'
	-o [path]			Output file path for 'backup' command, default is ./backup.json
	-i [path]			Input file path for 'restore' command, default is ./backup.json

	### Examples:
	$ cometblue discover -s -75
	AABBCC-5555-AAAA-DDEECC signal:-60
	CCBBAA-2222-AAAA-FFFFFFF signal:-65
	$ cometblue get AABBCC-5555-AAAA-DDEECC -k temperatures.targetHi
	22.5
	$ cometblue get AABBCC-5555-AAAA-DDEECC -k temperatures -f json
	{"offset" : 1, "manual" : 15, "targetLow" : 18, "targetHi" : 22.5, "current" : 18}
	$ cometblue set AABBCC-5555-AAAA-DDEECC -k status.flags.childlock true
	Set OK

	### Miscellanous
	Use 'auto' as device id to attemt connecting the nearest (highest signal) device
	Use 'cometblue [device_id] get -f json' to discover keypath structure
	Set for 'deviceDate' with zero arg sets the current date time
	Pin change is not supported
	Tool is able to backup/restore day/holiday whole schedules, but editing isn't (yet?) supported
	"""
	print(text)
}


guard CommandLine.argc > 1 else {
	printUsage()
	exit(0)
}

do {
	let cli = try CLIProvider(with: CommandLine.arguments)
	try cli.start()
	
} catch let error as CLIProvider.CLIError {
	print(error.description)
	exit(1)
} catch let error {
	print(error)
	exit(1)
}
