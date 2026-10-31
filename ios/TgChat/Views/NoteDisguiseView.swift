import SwiftUI
import UIKit

/// 伪装成二次元风格便签 App 的锁屏。
/// 进入真实应用的方式：
///   1. 连续点击右上角月亮 5 次 → 输入密码
///   2. 在搜索框直接输入密码
struct NoteDisguiseView: View {
    @EnvironmentObject private var app: AppState

    @State private var notes: [FakeNote] = FakeNote.samples
    @State private var search = ""
    @State private var moonTaps = 0
    @State private var showLock = false
    @State private var pin = ""
    @State private var pinError = false
    @State private var shake: CGFloat = 0
    @State private var selected: FakeNote?
    @State private var showCompose = false
    @State private var draftTitle = ""
    @State private var draftBody = ""

    private let accent = Color(hex: "#FF7FAE")
    private let deep = Color(hex: "#5C4A56")
    private let soft = Color(hex: "#A6909E")

    private var filtered: [FakeNote] {
        guard !search.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
                $0.body.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#FFE6F1"), Color(hex: "#FFF7FB"), Color(hex: "#F3ECFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            decorativeBackground

            VStack(spacing: 0) {
                header
                searchBar
                notesList
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        draftTitle = ""
                        draftBody = ""
                        showCompose = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [accent, Color(hex: "#C6A8FF")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: accent.opacity(0.35), radius: 12, x: 0, y: 6)
                            )
                    }
                    .padding(.trailing, 22)
                    .padding(.bottom, 26)
                }
            }
        }
        .fullScreenCover(isPresented: $showLock) {
            LockPadView(
                pin: app.unlockPin,
                onSuccess: {
                    showLock = false
                    app.unlock()
                },
                onCancel: { showLock = false }
            )
        }
        .sheet(item: $selected) { note in
            NoteDetailView(note: note, accent: accent, deep: deep, soft: soft)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showCompose) {
            ComposeNoteView(
                title: $draftTitle,
                body: $draftBody,
                accent: accent,
                deep: deep
            ) {
                let title = draftTitle.trimmingCharacters(in: .whitespaces)
                let body = draftBody.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty || !body.isEmpty else { return }
                notes.insert(
                    FakeNote(
                        id: UUID().uuidString,
                        title: title.isEmpty ? "无标题" : title,
                        body: body,
                        time: "刚刚",
                        tint: ["#FF9FC4", "#C6A8FF", "#9ED8FF", "#FFC98F"].randomElement() ?? "#FF9FC4",
                        emoji: ["🌙", "🍰", "🌷", "✨", "🐰"].randomElement() ?? "🌙"
                    ),
                    at: 0
                )
                draftTitle = ""
                draftBody = ""
                showCompose = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.dateLine())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(soft)
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 18))
                        .foregroundColor(accent)
                    Text("月见便笺")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(deep)
                }
            }

            Spacer()

            Button {
                moonTaps += 1
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if moonTaps >= 5 {
                    moonTaps = 0
                    pin = ""
                    pinError = false
                    showLock = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if moonTaps > 0 { moonTaps = 0 }
                }
            } label: {
                Image(systemName: "moon.fill")
                    .font(.system(size: 17))
                    .foregroundColor(accent.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.75)))
                    .shadow(color: accent.opacity(0.15), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 14)
    }

    private var decorativeBackground: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color(hex: "#FFC7DE").opacity(0.45))
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
                    .offset(x: proxy.size.width * 0.35, y: -proxy.size.height * 0.28)
                Circle()
                    .fill(Color(hex: "#CDBCFF").opacity(0.4))
                    .frame(width: 200, height: 200)
                    .blur(radius: 46)
                    .offset(x: -proxy.size.width * 0.35, y: proxy.size.height * 0.32)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(soft)
            TextField("搜索便笺", text: $search)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(deep)
                .onChange(of: search) { value in
                    if !value.isEmpty, value == app.unlockPin {
                        search = ""
                        app.unlock()
                    }
                }
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(soft.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color(hex: "#FFB7D3").opacity(0.18), radius: 8, y: 3)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var notesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filtered) { note in
                    Button {
                        selected = note
                    } label: {
                        NoteCard(note: note, accent: accent, deep: deep, soft: soft)
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Text("🌙")
                            .font(.system(size: 34))
                        Text("没有找到便笺")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(soft)
                    }
                    .padding(.top, 60)
                }
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }

    static func dateLine() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }
}

struct FakeNote: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let time: String
    let tint: String
    let emoji: String

    static let samples: [FakeNote] = [
        FakeNote(
            id: "1",
            title: "周末计划",
            body: "去美术馆看新展，然后吃草莓蛋糕 🍰\n记得带上相机。",
            time: "今天 09:24",
            tint: "#FF9FC4",
            emoji: "🍰"
        ),
        FakeNote(
            id: "2",
            title: "想买的",
            body: "月见色的指甲油、兔子抱枕、新的手帐本 ✨",
            time: "昨天",
            tint: "#C6A8FF",
            emoji: "🐰"
        ),
        FakeNote(
            id: "3",
            title: "给未来的自己",
            body: "今天也有好好努力，辛苦啦 🌙\n明天也要记得吃早饭。",
            time: "10月28日",
            tint: "#9ED8FF",
            emoji: "🌙"
        ),
    ]
}

struct NoteCard: View {
    let note: FakeNote
    let accent: Color
    let deep: Color
    let soft: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(note.emoji)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: note.tint).opacity(0.22))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(deep)
                Text(note.body)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(soft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(note.time)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(soft.opacity(0.75))
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.92))
                .shadow(color: Color(hex: "#FFB7D3").opacity(0.16), radius: 10, y: 4)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: note.tint))
                .frame(width: 3, height: 34)
                .padding(.leading, 6)
        }
    }
}

struct NoteDetailView: View {
    let note: FakeNote
    let accent: Color
    let deep: Color
    let soft: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#FFF3F8"), Color(hex: "#F6F0FF")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(note.emoji).font(.system(size: 30))
                    Text(note.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(deep)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(soft)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                }
                Text(note.time)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(soft)
                Text(note.body)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(deep.opacity(0.9))
                    .lineSpacing(5)
                Spacer()
            }
            .padding(22)
        }
    }
}

struct ComposeNoteView: View {
    @Binding var title: String
    @Binding var body: String
    let accent: Color
    let deep: Color
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField("标题", text: $title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(deep)
                TextField("写点什么…", text: $body, axis: .vertical)
                    .font(.system(size: 15, design: .rounded))
                    .lineLimit(6...12)
                Spacer()
            }
            .padding(20)
            .background(Color(hex: "#FFF8FB").ignoresSafeArea())
            .navigationTitle("新建便笺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                    .tint(accent)
                }
            }
        }
    }
}

// MARK: - PIN pad

struct LockPadView: View {
    let pin: String
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @State private var error = false
    @State private var shake: CGFloat = 0

    private let accent = Color(hex: "#FF7FAE")
    private let deep = Color(hex: "#5C4A56")
    private let soft = Color(hex: "#A6909E")

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#FFE6F1"), Color(hex: "#F3ECFF")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                VStack(spacing: 8) {
                    Text("🌙").font(.system(size: 38))
                    Text("月见便笺")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(deep)
                    Text(error ? "密码不对，再试一次" : "输入密码")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(error ? Color(hex: "#E0645A") : soft)
                }

                HStack(spacing: 16) {
                    ForEach(0..<max(4, pin.count), id: \.self) { index in
                        Circle()
                            .fill(index < input.count ? accent : Color.white.opacity(0.9))
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().stroke(accent.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                .offset(x: shake)

                keypad

                Button("取消") { onCancel() }
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(soft)

                Spacer()
            }
            .padding(.bottom, 30)
        }
        .onAppear { input = "" }
    }

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 72, height: 72)
                        } else {
                            Button {
                                tap(key)
                            } label: {
                                Group {
                                    if key == "⌫" {
                                        Image(systemName: "delete.left")
                                            .font(.system(size: 20, weight: .medium))
                                    } else {
                                        Text(key)
                                            .font(.system(size: 26, weight: .medium, design: .rounded))
                                    }
                                }
                                .foregroundColor(deep)
                                .frame(width: 72, height: 72)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.92))
                                        .shadow(color: Color(hex: "#FFB7D3").opacity(0.18), radius: 6, y: 3)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func tap(_ key: String) {
        if key == "⌫" {
            if !input.isEmpty { input.removeLast() }
            error = false
            return
        }
        let length = max(4, pin.count)
        guard input.count < length else { return }
        input += key
        if input.count == length {
            if input == pin {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSuccess()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                error = true
                withAnimation(.spring(response: 0.2, dampingFraction: 0.35)) {
                    shake = 10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { shake = -8 }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                    withAnimation(.easeOut(duration: 0.15)) { shake = 0 }
                    input = ""
                }
            }
        }
    }
}
