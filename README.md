# DellKnobVolume

Small Swift utility that listens to a Dell USB volume knob over HID and adjusts the system output volume on macOS.

## Requirements
- macOS 12 or newer (tested on Apple Silicon)
- Xcode Command Line Tools (for `swiftc`)
- Tested with the Dell SK-8135 keyboard knob; other HID consumer-control devices may require minor adjustments.

## Download
Clone or download this repository:

```bash
git clone https://github.com/<your-account>/DellKnobVolume.git
cd DellKnobVolume
```

If you downloaded a ZIP, unzip it and open the folder in Terminal before continuing.

## Build
Compile the tool with the required frameworks:

```bash
swiftc main.swift -framework IOKit -framework CoreAudio -o DellKnobVolume
```

This produces the executable `DellKnobVolume` in the project directory.

## Run
Launch the binary directly:

```bash
./DellKnobVolume
```

You should see:

```
Running. Rotate the knob to change the volume (5% step).
```

Keep the process running while you use the knob.

## Debugging
To inspect HID traffic, enable debug logging at build time:

```bash
swiftc main.swift -framework IOKit -framework CoreAudio -o DellKnobVolume -DDEBUG
./DellKnobVolume
```

When compiled with `-DDEBUG`, the program prints any unhandled HID usage pairs so you can extend the switch statement if your device exposes different controls.

## Autostart on Login (LaunchAgent)
1. Build the binary and copy it to a persistent location, e.g.:

   ```bash
   mkdir -p ~/Applications/DellKnobVolume
   cp DellKnobVolume ~/Applications/DellKnobVolume/
   ```

2. Create a LaunchAgent plist at `~/Library/LaunchAgents/com.example.dellknobvolume.plist` with the following contents (update the paths to match your setup):

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
     <dict>
       <key>Label</key>
       <string>com.example.dellknobvolume</string>
       <key>ProgramArguments</key>
       <array>
         <string>/Users/your-user/Applications/DellKnobVolume/DellKnobVolume</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
     </dict>
   </plist>
   ```

3. Load the agent:

   ```bash
   launchctl load ~/Library/LaunchAgents/com.example.dellknobvolume.plist
   ```

The utility now starts automatically each time you log in. To unload it later, run:

```bash
launchctl unload ~/Library/LaunchAgents/com.example.dellknobvolume.plist
```
