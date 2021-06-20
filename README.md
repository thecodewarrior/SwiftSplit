<h1 align="center">
  <br>
    <img src="https://raw.github.com/thecodewarrior/SwiftSplit/master/Logo/Icon_512x512.png" title="SwiftSplit Icon" 
    width="256" height="256" alt="SwiftSplit Icon">
  <br>
  SwiftSplit
</h1>

SwiftSplit is a macOS autosplitter for Celeste, though given the time and motivation I hope to extend it to more than
just Celeste. It works by acting as a split server for [LiveSplit One](https://one.livesplit.org/), reading Celeste's
memory and translating that into split commands that LiveSplit understands.

## Using SwiftSplit

Launching and using SwiftSplit is fairly simple, with only three broad steps. 
- Launching SwiftSplit and connecting it to Celeste 
- Connecting LiveSplit One to the SwiftSplit server
- Loading your splits and route

### Connecting to Celeste
1. Open SwiftSplit
2. Open Celeste *after* SwiftSplit
   - If you are using Everest, you're free to restart into `orig/Celeste.exe` as normal
   - The first time SwiftSplit connects it will ask you to enter your administrator password. This is normal, and is 
     required for SwiftSplit to read information from Celeste.
3. SwiftSplit should automatically detect Celeste launching and report the "Connection status" as "Connecting…". During 
   this time *do not load any maps.* Stay on the main menu until the connection has been made. This may take up to 30 
   seconds after Celeste fully loads in extreme cases. 

### Connecting to [LiveSplit One](https://one.livesplit.org/)
4. Copy the LiveSplit server URL displayed in SwiftSplit
5. Click "Connect to Server" in LiveSplit One and paste that URL
   - Note: navigating away from the timer screen may make the server button say it isn't connected any more. This is a 
     bug. You can check if it's still connected in SwiftSplit.

### Loading the Run
6. Load up your splits in LiveSplit One
7. Load the corresponding route JSON in SwiftSplit by either clicking "Load Route" or dragging the `.json` file onto the 
   "Route" box in SwiftSplit. 

## Browser Compatibility

### Safari - Not compatible
Safari doesn't like the way SwiftSplit communicates with LiveSplit One, so LiveSplit stalls when trying to connect.

### Firefox - Mostly compatible
Unless you can keep LiveSplit open and visible, Firefox will slow down the LiveSplit One tab, causing it to record 
incorrect times. If you keep the LiveSplit window open on a second display this isn't an issue.

### Chrome - Compatible
Chrome doesn't seem to have the same optimization as Firefox, which in this case is a good thing. If you're using 
Firefox and your splits are coming out wrong, try with Chrome and see if that fixes it.

## Pre-made splits
You can get pre-made splits from the [examples directory](https://github.com/thecodewarrior/SwiftSplit/tree/master/example).
Included are:
- Full-game
  - Any%
- IL (chapters 1–9)
  - Any%
  - B-side
  - C-side
- Icons (chapters, berry, and celeste mountain) for use as split icons
For each of these the `.lss` file can be imported directly into LiveSplit One and the corresponding `.json` files can 
be loaded into SwiftSplit. 

