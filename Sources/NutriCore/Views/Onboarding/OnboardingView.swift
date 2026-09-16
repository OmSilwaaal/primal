import SwiftUI

struct OnboardingView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginMode = true
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea() // Pure black background
            
            VStack(spacing: 50) {
                Spacer()
                
                Text("PRIMAL")
                    .font(.system(size: 48, weight: .bold, design: .default))
                    .tracking(8)
                    .foregroundColor(.white)
                
                Spacer()
                
                VStack(spacing: 24) {
                    if let error = authManager.authError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        
                        SecureField("Password", text: $password)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 40)
                    
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
                            .padding()
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                    
                    Button(action: {
                        withAnimation {
                            isLoginMode.toggle()
                        }
                    }) {
                        Text(isLoginMode ? "Don't have an account? Sign Up" : "Already have an account? Log In")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 16)
                }
                .padding(.bottom, 60)
            }
        }
    }
}
