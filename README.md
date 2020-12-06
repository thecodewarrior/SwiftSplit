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
     bug. You can check that it's still connected with the "LiveSplit clients" field in SwiftSplit, which should read 
     "1". If that field reads "0", you need to connect. If it reads "2" or higher then you will need to save your splits 
     and reload the LiveSplit One tab, otherwise each split will trigger multiple times.

### Loading the Run
6. Load up your splits in LiveSplit One
7. Load the corresponding route JSON in SwiftSplit by either clicking "Load Route" or dragging the `.json` file onto the 
   "Route" box in SwiftSplit. 

## Pre-made splits
Pre-made splits and route JSON files for Any% can be found [here](https://github.com/thecodewarrior/SwiftSplit/tree/master/example).
The listed `.lss` files can be imported directly into LiveSplit One and the corresponding `.json` files can be loaded 
into SwiftSplit.

# Route JSON
Routes are configured using a JSON file and use "events" generated by SwiftSplit. They consist of a reset event and a 
list of route events. SwiftSplit expects route events in a specific order and triggers splits on those events. The reset
event can trigger at any point during the route and will reset the run. 

Here's an example for Old Site Any%:
```json
{
    "useFileTime": false,
    "reset": "reset chapter",
    "route": [
        "start chapter 2 ## Start",
        "d8 > d3 ## - Mirror",
        "3x > 3 ## Intervention",
        "10 > 2 ## - Escape",
        "13 > end_0 ## Awake",
        "complete chapter 2"
    ]
}
```

## Events
Events are triggered when SwiftSplit observes a change in the game state, which is checked 10 times every second. A 
single state change frequently causes multiple events, generally with differing levels of specificity. 

Note that the *exact* text of an event is important. Spaces and capitalization have to match, with a couple additions:
- Inserting an exclamation point (`!`) at the beginning of an event will cause that event to not trigger a split. This 
  can be useful when your route passes between two screens multiple times but you only want one split. 
- Anything after a ` ##` (*exactly* one space and two pound signs) will be trimmed off. This can be useful for 
  explaining events.

SwiftSplit has an "Event Stream" panel that displays events as they are triggered, which can be useful when creating 
route files. (You can copy the text out of the panel to paste directly into the route file too).

### Chapter start/end events
- `reset chapter` - Triggered when any chapter is reset (either by restarting the chapter or exiting to the map)
- `start chapter <n>` - Triggered when chapter `<n>` is started
- `reset chapter <n>` - Triggered when chapter `<n>` is reset
- `complete chapter <n>` - Triggered when chapter `<n>` is completed
- **A-side specific:**
  - `start a-side <n>` - Triggered when chapter `<n>`'s A-side is started
  - `reset a-side <n>` - Triggered when chapter `<n>`'s A-side is reset
  - `complete a-side <n>` - Triggered when chapter `<n>`'s A-side is completed
- **B-side specific:**
  - `start b-side <n>` - Triggered when chapter `<n>`'s B-side is started
  - `reset b-side <n>` - Triggered when chapter `<n>`'s B-side is reset
  - `complete b-side <n>` - Triggered when chapter `<n>`'s B-side is completed
- **C-side specific:**
  - `start c-side <n>` - Triggered when chapter `<n>`'s C-side is started
  - `reset c-side <n>` - Triggered when chapter `<n>`'s C-side is reset
  - `complete c-side <n>` - Triggered when chapter `<n>`'s C-side is completed

### Screen transition event
- `<from screen> > <to screen>` - Triggered when transitioning between two screens (you can find the screen IDs by
  enabling debug and hovering over the screen in the map editor.)

### Collectable events
- **Cassettes:**
  - `cassette` - Triggered when any cassette is collected
  - `chapter <n> cassette` - Triggered when the cassette in the specified chapter is collected
  - `<n> total cassettes` - Triggered when a cassette is collected. `<n>` is the total number of cassettes collected in
    the current file
- **Heart Gems:**
  - `heart` - Triggered when any heart gem is collected
  - `chapter <n> heart` - Triggered when the heart gem in the specified chapter is collected
  - `<n> total hearts` - Triggered when a heart gem is collected. `<n>` is the total number of heart gems collected in 
    the current file
- **Strawberries:**
  - `strawberry` - Triggered when any strawberry is collected
  - `<n> chapter strawberries` - Triggered when a total of `<n>` strawberries are collected in a chapter
  - `<n> file strawberries` - Triggered when a total of `<n>` strawberries are collected in the file

