import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var showServer = false
    @State private var showLogout = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(
                            name: app.me?.title ?? "?",
                            colorHex: app.me?.avatarColor ?? "#3390EC",
                            size: 60
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.me?.title ?? "未登录")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(c.textPrimary)
                            Text("@\(app.me?.username ?? "")")
                                .font(.system(size: 14))
                                .foregroundColor(c.textSecondary)
                            Text(app.me?.role == "admin" ? "管理员账号" : "普通账号")
                                .font(.system(size: 12))
                                .foregroundColor(c.accent)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(c.background)
                }

                Section {
                    Picker("主题", selection: Binding(
                        get: { app.themeMode },
                        set: { app.setTheme($0) }
                    )) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(c.background)

                    Button {
                        showServer = true
                    } label: {
                        HStack {
                            Text("服务器地址").foregroundColor(c.textPrimary)
                            Spacer()
                            Text(app.baseURL.replacingOccurrences(of: "https://", with: ""))
                                .font(.system(size: 13))
                                .foregroundColor(c.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(c.background)
                } header: {
                    Text("外观与服务器")
                }

                if app.me?.role == "admin" {
                    Section {
                        NavigationLink {
                            AdminView()
                        } label: {
                            Text("用户管理").foregroundColor(c.textPrimary)
                        }
                        .listRowBackground(c.background)
                    } header: {
                        Text("管理员")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogout = true
                    } label: {
                        Text("退出登录")
                    }
                    .listRowBackground(c.background)
                }

                Section {
                    Text("Telegram Clone \(Config.appVersion) · Cloudflare Workers + D1")
                        .font(.system(size: 11))
                        .foregroundColor(c.textTertiary)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(c.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showServer) {
                ServerURLSheet().environmentObject(app)
            }
            .confirmationDialog("退出登录", isPresented: $showLogout, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task {
                        await app.logout()
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("退出后需要重新输入用户名和密码")
            }
        }
    }
}

struct AdminView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var showAdd = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        List {
            if app.adminUsers.isEmpty {
                Text("加载中…")
                    .foregroundColor(c.textTertiary)
                    .listRowBackground(c.background)
            } else {
                ForEach(app.adminUsers) { user in
                    HStack(spacing: 12) {
                        AvatarView(name: user.title, colorHex: user.avatarColor, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(c.textPrimary)
                            Text("@\(user.username)")
                                .font(.system(size: 12))
                                .foregroundColor(c.textSecondary)
                        }
                        Spacer()
                        Text(user.role == "admin" ? "管理员" : "普通用户")
                            .font(.system(size: 12))
                            .foregroundColor(user.role == "admin" ? c.accent : c.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(user.role == "admin" ? c.accent.opacity(0.12) : c.surfaceAlt))
                    }
                    .listRowBackground(c.background)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(c.background.ignoresSafeArea())
        .navigationTitle("用户管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await app.loadAdminUsers()
        }
        .sheet(isPresented: $showAdd) {
            AddUserView().environmentObject(app)
        }
    }
}

struct AddUserView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var isAdmin = false
    @State private var submitting = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            Form {
                Section {
                    TextField("用户名（字母、数字、下划线）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("显示名称（可选）", text: $displayName)
                    SecureField("初始密码（至少 6 位）", text: $password)
                }

                Section {
                    Toggle("管理员权限", isOn: $isAdmin)
                }

                if let error = app.adminError {
                    Section {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(c.danger)
                    }
                }
            }
            .navigationTitle("创建账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            submitting = true
                            let ok = await app.adminCreateUser(
                                username: username,
                                password: password,
                                displayName: displayName,
                                role: isAdmin ? "admin" : "user"
                            )
                            submitting = false
                            if ok { dismiss() }
                        }
                    } label: {
                        if submitting {
                            ProgressView()
                        } else {
                            Text("创建")
                        }
                    }
                    .disabled(username.count < 3 || password.count < 6 || submitting)
                }
            }
        }
    }
}
