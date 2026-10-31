import SwiftUI

struct PollMessageView: View {
    let message: Message
    let poll: Poll
    let colors: TgColors

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(colors.accent)
                Text(poll.anonymous ? "匿名投票" : "投票")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colors.accent)
                if poll.closed {
                    Text("已结束")
                        .font(.system(size: 10))
                        .foregroundColor(colors.textTertiary)
                }
            }

            Text(poll.question)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(poll.options, id: \.index) { option in
                optionRow(option)
            }

            HStack(spacing: 6) {
                Text("\(poll.totalVotes) 票")
                    .font(.system(size: 11))
                    .foregroundColor(colors.textTertiary)
                if poll.multiple {
                    Text("· 多选")
                        .font(.system(size: 11))
                        .foregroundColor(colors.textTertiary)
                }
                Spacer()
                Text(formatTime(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(colors.textTertiary)
            }
        }
        .padding(10)
        .frame(width: 270, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(colors.bubbleIn))
    }

    private func optionRow(_ option: PollOption) -> some View {
        let selected = poll.myVotes.contains(option.index)
        let fraction = poll.totalVotes > 0 ? Double(option.votes) / Double(poll.totalVotes) : 0

        return Button {
            guard !poll.closed else { return }
            Task { await app.votePoll(chatId: message.chatId, pollId: poll.id, optionIndex: option.index) }
        } label: {
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colors.accent.opacity(selected ? 0.22 : 0.10))
                        .frame(width: max(8, geometry.size.width * CGFloat(fraction)))
                }
                HStack(spacing: 6) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(selected ? colors.accent : colors.textTertiary)
                    Text(option.text)
                        .font(.system(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Text("\(option.votes)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }
}

struct PollCreateView: View {
    let chatId: String
    let topicId: String?

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var multiple = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section("问题") {
                    TextField("想问问大家什么？", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                        .listRowBackground(c.background)
                }

                Section("选项") {
                    ForEach(options.indices, id: \.self) { index in
                        HStack {
                            TextField("选项 \(index + 1)", text: $options[index])
                                .listRowBackground(c.background)
                            if options.count > 2 {
                                Button {
                                    options.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(c.danger)
                                }
                            }
                        }
                        .listRowBackground(c.background)
                    }
                    if options.count < 10 {
                        Button {
                            options.append("")
                        } label: {
                            Label("添加选项", systemImage: "plus.circle")
                                .foregroundColor(c.accent)
                        }
                        .listRowBackground(c.background)
                    }
                }

                Section {
                    Toggle("允许多选", isOn: $multiple)
                        .listRowBackground(c.background)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("创建投票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(!valid)
                }
            }
        }
    }

    private var valid: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty &&
            options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    private func create() {
        let cleaned = options
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        Task {
            await app.createPoll(
                chatId: chatId,
                question: question.trimmingCharacters(in: .whitespaces),
                options: cleaned,
                multiple: multiple,
                topicId: topicId
            )
        }
        dismiss()
    }
}
