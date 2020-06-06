#  CometBlue
[![Platform](https://img.shields.io/badge/Platforms-macOS%20-iOS%20-4E4E4E.svg?colorA=28a745)](https://github.com/vaddieg/cometblue)
[![Swift support](https://img.shields.io/badge/Swift-4.0%20%7C%204.2%20%7C%205.0%20%7C%205.1%20-lightgrey.svg?colorA=28a745&colorB=4E4E4E)](https://github.com/vaddieg/cometblue)
[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg?style=flat&colorA=28a745&&colorB=4E4E4E)](https://github.com/apple/swift-package-manager)

Command-line tool for macOS for managing CometBlue, EUROprog, Cygonix and other compatible BLE thermostats. Implemented in Swift using CoreBluetooth framework. Code is compatible with iOS

## Installation
```
git clone https://github.com/vaddieg/cometblue.git
cd cometblue
swift build -c release
cp .build/release/cometblue /usr/local/bin
```
for iOS  (JB, ssh, ldid)  
```
cd Sources/cometblue
./build_ios.sh
scp cometblue root@your-jailbroken-iphone:/usr/bin/cometblue
```

 ## Usage
 ```
 cometblue discover <options>
 cometblue [ get | set | backup | restore] <device_id> <options>  

Commands:
 * discover			Scan for compatible BLE devices to find out device_ids 
 * get  		 		Read value(s) from device
 * set		  	 	Write value(s) to device
 * backup			 Backups device settings to specified file
 * restore			Restores device settings from specified file
Options:
 * -t [timeout]		Timeout for 'discover' command, default is 60s
 * -s [threshold]		Signal level threshold for 'discover', default = -80dB
 * -p [pin]			Pin to access the device, default = 0
 * -k [key.path]		Keypath of the value for reading or writing, default is root "."
 * -f [human | json] 	Specifies human readable or json as output format for 'get' command, default is 'human'
 * -o [path]			Output file path for 'backup' command, default is ./backup.json
 * -i [path]			Input file path for 'restore' command, default is ./backup.json
```

 ## Examples:
 ```
 $ cometblue discover -s -75  
 AABBCC-5555-AAAA-DDEECC signal:-60  
 CCBBAA-2222-AAAA-FFFFFFF signal:-65  
 
 $ cometblue get AABBCC-5555-AAAA-DDEECC -k temperatures.targetHi  
 22.5  
 $ cometblue get AABBCC-5555-AAAA-DDEECC -k temperatures -f json  
 {"offset" : 1, "manual" : 15, "targetLow" : 18, "targetHi" : 22.5, "current" : 18}  
 $ cometblue set AABBCC-5555-AAAA-DDEECC -k status.flags.childlock true  
 Set OK  
 ```
 ### Miscellanous
 Use 'auto' as device id to attemt connecting the nearest (highest signal) device  
 Use 'cometblue [device_id] get -f json' to discover keypath structure  
 Set for 'deviceDate' with zero arg sets the current date time  
 Pin change is not supported  
 Tool is able to backup/restore day/holiday whole schedules, but editing isn't (yet?) supported  

## Credits
https://github.com/im-0/cometblue used a reference to discover device APIs

