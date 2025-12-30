Phase 3 Cursor Instructions (Copy & Paste)
Here are the specific instructions for Cursor to implement the UI & Interaction phase.
Context:
We have the Logic (Phase 2) and Scaffolding (Phase 1).
Now we need to build the SwiftUI Views and Interaction Logic for the floating HUD.
🛑 Step 1: Create UI Components (Views/Components/)
StatusIndicator.swift:
A circular view (approx 8x8 pt).
State: Accept an enum ProcessingState (idle, polling, thinking, success, error).
Animation:
polling: Infinite breathing animation (opacity 0.5 <-> 1.0).
thinking: Fast blink or rotation.
success: Turn green instantly.
error: Turn red.
DiagnosisView.swift:
A view with a yellow/orange background and rounded corners.
Display the diagnosis text (from Track B).
Include a small "Dismiss" or "Fixed" button.
CompactInputView.swift:
A TextField that appears when triggered.
Style it to blend with the HUD (dark/translucent background).
🛑 Step 2: Implement Main HUD View (Views/HUDView.swift)
Refactor the existing placeholder HUDView.
Layout:
Use a VStack inside the main container.
Top Row (HStack):
StatusIndicator (Left).
Text (Main Instruction) - multiline, scalable.
Spacer.
Button (Icon: "keyboard") -> Toggles Input Field.
Button (Icon: "arrow.right.circle.fill") -> "Force Next" action.
Middle Row:
CompactInputView (Visible only if isInputExpanded).
Bottom Row:
DiagnosisView (Visible only if appState.diagnosis is not nil).
Styling:
Use VisualEffectView (NSVisualEffectView) as the background for the "Glassmorphism" look suitable for macOS HUDs.
Corner Radius: 12-16pt.
🛑 Step 3: Connect State & Animations (ViewModels/HUDViewModel.swift)
Update the ViewModel to handle transitions.
Instruction Transition:
When instruction updates, wrap it in withAnimation.
Implement handleSuccess(): Set a temporary showSuccessCheckmark = true, wait 0.8s, then update instruction and set showSuccessCheckmark = false.
Focus Management (Crucial):
Add a function toggleInputMode().
When opening input: Call NSApp.activate(ignoringOtherApps: true) and window?.makeKey().
When closing input: Resign key window status so the user can type in the browser again.
Track B Trigger:
The "Refresh/Check" button (or logic) should trigger agentLogic.runDiagnosis().
If diagnosis returns a suggestion, update diagnosisResult to expand the view.
🛑 Step 4: Refine Window Controller (FloatingPanelController.swift)
Ensure the window behavior supports the new UI.
Enable hasShadow for better visibility.
Ensure isMovableByWindowBackground is true (so user can drag the HUD out of the way).
Auto-Resize: The window frame should animate to fit the content size (especially when Diagnosis/Input expands). Hint: Listen to SwiftUI content size changes.