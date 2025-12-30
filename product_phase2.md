🏗️ Phase 2 Cursor Instructions (Copy & Paste)
Here are the specific instructions for Cursor to implement the Logic & Brain phase.
Context:
We have the scaffolding. Now we need to implement the intelligence using Alibaba Qwen-VL-Plus.
We are following a Full Visual Flow (both Planner and Navigator use VL models).
🛑 Step 1: Enhance Network Layer (QwenLLMService.swift)
Modify QwenLLMService to support flexible multi-modal requests.
Structs: Define the QwenRequest and QwenResponse structures matching Alibaba DashScope's API format. Ensure it supports ["type": "image_url", ...] in messages.
Methods:
sendPlannerRequest(goal: String, history: String, image: NSImage) async throws -> [MesoGoal]
sendNavigatorRequest(meso: MesoGoal, image: NSImage, blackboard: [String:String]) async throws -> MicroInstruction
sendWatcherRequest(criteria: String, image: NSImage) async throws -> Bool
sendSummarizerRequest(completedMeso: MesoGoal, actions: [String]) async throws -> String (For history compression)
Retry Logic:
Wrap the API calls in a retry block.
If JSON decoding fails or API errors, wait 1 second and try one more time.
Only throw error after the 2nd failure.
🛑 Step 2: Implement Data Models
Create/Update Models/AIModels.swift:
struct MesoGoal: Codable, Identifiable
struct MicroInstruction: Codable (Fields: instruction, success_criteria, memory_to_save)
struct SessionContext
var historySummary: [String] (The compressed history)
var blackboard: [String: String] (The key-value store)
🛑 Step 3: Implement The Prompts (System Prompts)
Create Config/Prompts.swift to store these large strings.
1. Planner Prompt:
"You are an expert macOS automation planner. User Goal: {GOAL}. History: {HISTORY}.
Analyze the screenshot. Break down the remaining path into 3-5 sequential milestones (Meso Goals).
Return JSON: {'goals': [{'id': 1, 'title': '...', 'description': '...'}]}."
2. Navigator Prompt:
"You are a precise macOS navigator. Current Milestone: {MESO}. Blackboard: {BLACKBOARD}.
Analyze the screenshot. Generate the NEXT IMMEDIATE STEP.
Rules:
Aggregate simple steps (e.g., 'Go to URL and Login').
Extract critical data (IDs, Keys) into memory_to_save.
Define success_criteria: A natural language description of what the screen looks like AFTER the step is done.
Return JSON: {'instruction': '...', 'success_criteria': '...', 'memory_to_save': {'key': 'value'}}."
3. Watcher Prompt:
"You are a strict boolean judge. Criteria: {CRITERIA}.
Look at the screenshot. Does it meet the criteria?
Return JSON: {'is_complete': true/false, 'reasoning': '...'}."
🛑 Step 4: Logic Controller (AgentLogicController.swift)
Create a new controller to orchestrate the loop.
Function: processNextStep()
Logic:
Check AppState. If no currentMesoGoal, call Planner.
Call Navigator with currentMesoGoal.
Update UI with instruction.
Start Watcher polling (triggered by ScreenCaptureService updates).
If Watcher returns true -> Call Summarizer -> Update History -> Loop back to 1.