import SwiftUI

/// A compact text input field styled for the HUD
struct CompactInputView: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 11))
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 12))
                .foregroundColor(.white)
                .focused($isFocused)
                .onSubmit {
                    onSubmit()
                }
            
            if !text.isEmpty {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CompactInputView(
            text: .constant(""),
            placeholder: "Enter your goal...",
            onSubmit: {},
            onCancel: {}
        )
        
        CompactInputView(
            text: .constant("Open Safari and go to github.com"),
            placeholder: "Enter your goal...",
            onSubmit: {},
            onCancel: {}
        )
    }
    .frame(width: 300)
    .padding()
    .background(Color.black)
}
