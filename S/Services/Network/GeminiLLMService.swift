import Foundation
import AppKit

/// V13: Simplified Gemini LLM Service - VLM analysis only
/// Removed: TR-P-D methods, step generation, video analysis
final class GeminiLLMService: LLMServiceProtocol, @unchecked Sendable {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let model = "gemini-2.0-flash-exp"
    private let maxRetries = 2
    
    init(apiKey: String = Secrets.geminiAPIKey) {
        self.apiKey = apiKey
    }
    
    // MARK: - Core VLM Methods
    
    func analyzeImage(_ image: NSImage, prompt: String) async -> String? {
        guard let base64Image = encodeImageToBase64(image) else {
            print("❌ [Gemini] Failed to encode image to base64")
            return nil
        }
        
        return await performVisionRequest(base64Image: base64Image, prompt: prompt)
    }
    
    func generateText(prompt: String, systemPrompt: String?) async -> String? {
        return await performTextRequest(prompt: prompt, systemPrompt: systemPrompt)
    }
    
    // MARK: - Private Helper Methods
    
    private func performVisionRequest(base64Image: String, prompt: String) async -> String? {
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 8192
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ [Gemini] Failed to serialize request body")
            return nil
        }
        
        request.httpBody = httpBody
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [Gemini] Invalid response type")
                    continue
                }
                
                guard httpResponse.statusCode == 200 else {
                    print("❌ [Gemini] HTTP \(httpResponse.statusCode)")
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("❌ [Gemini] Error: \(errorText)")
                    }
                    continue
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("❌ [Gemini] Failed to parse response")
                    continue
                }
                
                return text
            } catch {
                print("❌ [Gemini] Attempt \(attempt) failed: \(error)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        return nil
    }
    
    private func performTextRequest(prompt: String, systemPrompt: String?) async -> String? {
        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var parts: [[String: String]] = [["text": prompt]]
        if let systemPrompt = systemPrompt {
            parts.insert(["text": systemPrompt], at: 0)
        }
        
        let requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 8192
            ]
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ [Gemini] Failed to serialize request body")
            return nil
        }
        
        request.httpBody = httpBody
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [Gemini] Invalid response type")
                    continue
                }
                
                guard httpResponse.statusCode == 200 else {
                    print("❌ [Gemini] HTTP \(httpResponse.statusCode)")
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("❌ [Gemini] Error: \(errorText)")
                    }
                    continue
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("❌ [Gemini] Failed to parse response")
                    continue
                }
                
                return text
            } catch {
                print("❌ [Gemini] Attempt \(attempt) failed: \(error)")
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        
        return nil
    }
    
    private func encodeImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        let targetSize = CGSize(width: 1024, height: 1024)
        let resizedImage = resizeImage(image, to: targetSize)
        
        guard let resizedTiff = resizedImage.tiffRepresentation,
              let resizedBitmap = NSBitmapImageRep(data: resizedTiff),
              let jpegData = resizedBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        
        return jpegData.base64EncodedString()
    }
    
    private func resizeImage(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let sourceSize = image.size
        let widthRatio = targetSize.width / sourceSize.width
        let heightRatio = targetSize.height / sourceSize.height
        let scaleFactor = min(widthRatio, heightRatio)
        
        let scaledSize = CGSize(
            width: sourceSize.width * scaleFactor,
            height: sourceSize.height * scaleFactor
        )
        
        let resizedImage = NSImage(size: scaledSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaledSize),
                   from: NSRect(origin: .zero, size: sourceSize),
                   operation: .copy,
                   fraction: 1.0)
        resizedImage.unlockFocus()
        
        return resizedImage
    }
}
