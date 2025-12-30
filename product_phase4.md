Phase 4 Cursor Instructions (Copy & Paste)
Here are the specific instructions for Cursor to implement the Memory, Multi-Monitor, and Lifecycle features.
Context:
We have the Body (UI), Brain (Logic), and Scaffolding.
Now we are finalizing the app with Memory Integration and Multi-Screen Support.
Constraint: The app must be "Volatile" (no disk persistence) and "Invisible" (blackboard is hidden).
🛑 Step 1: Update Logic & Models
Update MicroInstruction:
Add let value_to_copy: String? to the struct.
Add let memory_to_save: [String: String]? to the struct.
Update SessionContext:
Add var blackboard: [String: String] = [:].
Add func reset() method that clears history, blackboard, and current goals.
Update Navigator Prompt:
Tell the AI: "If the current step requires the user to input data we previously saw (e.g., an API Key from the Blackboard), put that value in value_to_copy."
Tell the AI: "If the current screen shows critical new data (e.g., a generated ID), extract it into memory_to_save."
🛑 Step 2: Implement "Follow Mouse" Logic (Services/ScreenManager.swift)
Create a new service ScreenManager:
Tracking: Use NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) (or a polling timer if permissions are tricky) to track NSEvent.mouseLocation.
Detection: Determine which NSScreen contains the mouse point.
Action:
If the screen changes:
Move the FloatingPanel to the .bottom of the new screen (with offset).
Call ScreenCaptureService.updateTargetScreen(displayID: ...) to restart the stream on the new display.
Note: Ensure the panel moves smoothly (use window.setFrame(..., display: true, animate: true)).
🛑 Step 3: Update UI for Memory (Views/HUDView.swift)
Modify the HUDView:
Copy Button:
Inside the instruction row, check if let val = appState.currentInstruction?.value_to_copy.
If valid, render a Button with a "doc.on.doc" (Copy) icon.
Action: NSPasteboard.general.clearContents(); NSPasteboard.general.setString(val, forType: .string).
Show a temporary "Copied!" label or toast when clicked.
Reset/Close:
Add a "Close" (X) button to the floating panel.
Action: Call appState.resetSession(), which clears all data and returns the UI to the "Input Goal" state.
🛑 Step 4: Integration Check
Ensure the loop is closed:
Navigator output -> Updates Blackboard -> Updates UI (Copy Button).
Screen Change -> Updates Window Position -> Updates Capture Stream.
Reset -> Wipes memory -> Stops AI -> Ready for new task.