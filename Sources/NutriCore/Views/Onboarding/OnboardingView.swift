import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginMode = true
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Animated Monochrome Background
            LinearGradient(
                colors: [Color.black, Color(white: 0.15), Color.black],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: true)) {
                    animateGradient.toggle()
                }
            }
            
            // Subtle ambient glow
            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(y: -200)
            
            VStack {
                Spacer()
                
                // Glassmorphic Login Card matching the reference layout
                VStack(alignment: .leading, spacing: 20) {
                    
                    Text(isLoginMode ? "Welcome to PRIMAL" : "Join PRIMAL")
                        .font(.system(size: 28, weight: .heavy, design: .default))
                        .foregroundColor(.white)
                        .padding(.bottom, 8)
                    
                    if let error = authManager.authError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email *")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        
                        TextField("", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    // Password Field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password *")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        
                        SecureField("", text: $password)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    if isLoginMode {
                        Button(action: {}) {
                            Text("Forgot your password?")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .underline()
                        }
                        .padding(.top, -8)
                    }
                    
                    // Primary Action Button
                    Button(action: {
                        Task {
                            if isLoginMode {
                                await authManager.signIn(email: email, password: password)
                            } else {
                                await authManager.signUp(email: email, password: password)
                            }
                        }
                    }) {
                        Text(authManager.isLoading ? "LOADING..." : "Continue")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                    .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    .padding(.top, 8)
                    
                    // Divider
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                        Text("or")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    
                    // OAuth Buttons
                    VStack(spacing: 12) {
                        // Google Button
                        Button(action: {}) {
                            HStack {
                                // SF Symbols doesn't have Google, using generic circle or text
                                Text("G")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundColor(.white)
                                    .frame(width: 20)
                                
                                Spacer()
                                Text("Continue with Google")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                
                                // Spacer for balance
                                Color.clear.frame(width: 20)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        
                        // Apple Button
                        Button(action: {}) {
                            HStack {
                                Image(systemName: "applelogo")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .frame(width: 20)
                                
                                Spacer()
                                Text("Continue with Apple")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                
                                Color.clear.frame(width: 20)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    
                    // Toggle Mode
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isLoginMode.toggle()
                            }
                        }) {
                            Text(isLoginMode ? "Don't have an account? Sign Up" : "Already have an account? Log In")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.gray)
                                .underline()
                        }
                        Spacer()
                    }
                    .padding(.top, 16)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                
                Spacer()
                Spacer()
            }
        }
    }
}
