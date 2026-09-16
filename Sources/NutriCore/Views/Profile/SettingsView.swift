import SwiftUI

struct SettingsView: View {
    @AppStorage("isWhiteTheme") private var isWhiteTheme = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.ncBg.ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.ncPrimary)
                    }
                    .smoothButton()
                    
                    Spacer()
                    
                    Text("SETTINGS")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.ncSecondary)
                    
                    Spacer()
                    
                    // Invisible spacer for balance
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .regular))
                        .opacity(0)
                }
                .padding(.top, 20)
                
                // Settings List
                VStack(spacing: 16) {
                    // Theme Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2)) {
                            isWhiteTheme.toggle()
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("White Theme")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.ncPrimary)
                                Text(isWhiteTheme ? "Enabled" : "Disabled")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.ncSecondary)
                            }
                            Spacer()
                            
                            // Custom smooth toggle
                            ZStack {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isWhiteTheme ? Color.ncPrimary : Color.ncSurface2)
                                    .frame(width: 50, height: 30)
                                
                                Circle()
                                    .fill(isWhiteTheme ? Color.ncBg : Color.ncSecondary)
                                    .frame(width: 26, height: 26)
                                    .offset(x: isWhiteTheme ? 10 : -10)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                            .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2), value: isWhiteTheme)
                        }
                        .padding()
                        .background(Color.ncSurface)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationBarHidden(true)
    }
}
