import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var username = ""
    @State private var password = ""
    @State private var showServer = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)
        ZStack {
            c.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                        .frame(width: 104, height: 104)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#5FAEF7"), Color(hex: "#3390EC")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())

                    Text("Telegram")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(c.textPrimary)
                        .padding(.top, 20)

                    Text("登录以开始聊天")
                        .font(.system(size: 14))
                        .foregroundColor(c.textSecondary)
                        .padding(.top, 6)

                    if app.baseURL.contains("example.workers.dev") {
                        Button {
                            showServer = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                Text("服务器地址尚未配置，点此填写")
                                    .font(.system(size: 12.5))
                            }
                            .foregroundColor(Color(hex: "#8A5300"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#FFF4E5"))
                            )
                        }
                        .padding(.top, 18)
                    }

                    VStack(spacing: 12) {
                        TgTextField(placeholder: "用户名", text: $username, colors: c)
                        TgSecureField(placeholder: "密码", text: $password, colors: c)
                    }
                    .padding(.top, 32)

                    if let error = app.loginError {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(c.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    }

                    Button {
                        Task { await app.login(username: username, password: password) }
                    } label: {
                        Group {
                            if app.loginLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("登录").font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hex: "#3390EC").opacity(username.isEmpty || password.isEmpty ? 0.35 : 1))
                        )
                    }
                    .disabled(app.loginLoading || username.isEmpty || password.isEmpty)
                    .padding(.top, 20)

                    Text("账号由管理员创建，应用内不支持自助注册")
                        .font(.system(size: 12))
                        .foregroundColor(c.textTertiary)
                        .padding(.top, 18)

                    Button {
                        showServer = true
                    } label: {
                        Text("服务器 · \(app.baseURL)")
                            .font(.system(size: 12))
                            .foregroundColor(c.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 44)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 30)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showServer) {
            ServerURLSheet()
                .environmentObject(app)
        }
    }
}

struct TgTextField: View {
    let placeholder: String
    @Binding var text: String
    let colors: TgColors

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 15))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(colors.surfaceAlt))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.divider, lineWidth: 1))
    }
}

struct TgSecureField: View {
    let placeholder: String
    @Binding var text: String
    let colors: TgColors

    var body: some View {
        SecureField(placeholder, text: $text)
            .font(.system(size: 15))
            .foregroundColor(colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(colors.surfaceAlt))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.divider, lineWidth: 1))
    }
}

struct ServerURLSheet: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var value = ""

    var body: some View {
        let c = TgColors(dark: scheme == .dark)
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("填写部署好的 Cloudflare Worker 地址，例如 https://tgchat-api.你的账号.workers.dev")
                    .font(.system(size: 13))
                    .foregroundColor(c.textSecondary)
                TextField("https://", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(c.surfaceAlt))
                Spacer()
            }
            .padding(20)
            .background(c.background)
            .navigationTitle("服务器地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        app.setBaseURL(value)
                        dismiss()
                    }
                    .disabled(value.isEmpty)
                }
            }
            .onAppear { value = app.baseURL }
        }
    }
}
