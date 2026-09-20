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
            
            VStack(spacing: 40) {
                Spacer()
                
                // Huge Brutalist Title
                VStack(spacing: 8) {
                    Text("PRIMAL")
                        .font(.system(size: 56, weight: .heavy, design: .default))
                        .tracking(10)
                        .foregroundColor(.white)
                    
                    Text("RETURN TO NATURE")
                        .font(.system(size: 14, weight: .bold))
                        .tracking(4)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Glassmorphic Login Card
                VStack(spacing: 24) {
                    if let error = authManager.authError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            TextField("Email Address", text: $email)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            SecureField("Password", text: $password)
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        Task {
                            if isLoginMode {
                                await authManager.signIn(email: email, password: password)
                            } else {
                                await authManager.signUp(email: email, password: password)
                            }
                        }
                    }) {
                        Text(authManager.isLoading ? "LOADING..." : (isLoginMode ? "LOG IN" : "SIGN UP"))
                            .font(.system(size: 14, weight: .bold))
                            .tracking(2)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                    .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    .padding(.top, 8)
                    
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isLoginMode.toggle()
                        }
                    }) {
                        Text(isLoginMode ? "Don't have an account? Sign Up" : "Already have an account? Log In")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 4)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }
}
