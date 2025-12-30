import SwiftUI

/// A view displaying diagnosis/suggestion with dismiss action
struct DiagnosisView: View {
    let text: String
    let onDismiss: () -> Void
    let onFixed: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            VStack(spacing: 4) {
                Button(action: onFixed) {
                    Text("Fixed")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    DiagnosisView(
        text: "It looks like you need to click the 'Sign In' button first before proceeding.",
        onDismiss: {},
        onFixed: {}
    )
    .frame(width: 300)
    .padding()
    .background(Color.black)
}
