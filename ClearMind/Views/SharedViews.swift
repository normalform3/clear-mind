import SwiftUI

struct PageContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: CMTheme.pageMaxWidth, alignment: .leading)
                .padding(.horizontal, CMTheme.pagePadding)
                .padding(.top, 42)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(CMTheme.canvas)
    }
}

struct PageHeader: View {
    let eyebrow: String?
    let title: String

    init(_ title: String, eyebrow: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(CMTheme.textTertiary)
            }

            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .default))
                .foregroundStyle(CMTheme.textPrimary)
        }
        .padding(.bottom, 8)
    }
}

struct SectionHeading: View {
    let title: String
    let trailingText: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, trailingText: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.trailingText = trailingText
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))

            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 12))
                    .foregroundStyle(CMTheme.textSecondary)
            }

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(CMTheme.textSecondary)
            }
        }
    }
}

struct IslandSection<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CMTheme.islandSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CMTheme.separator, lineWidth: 0.7)
            }
    }
}

struct QuietDivider: View {
    var body: some View {
        Rectangle()
            .fill(CMTheme.separator)
            .frame(height: 0.7)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(CMTheme.textSecondary)
                .lineSpacing(3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .foregroundStyle(CMTheme.textPrimary)
                    .padding(.top, 3)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TagPills: View {
    let tags: [Tag]

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags.prefix(4)) { tag in
                    Text(tag.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CMTheme.color(for: tag.colorKey))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(CMTheme.color(for: tag.colorKey).opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct GoalSummaryCard: View {
    let goal: Goal
    var showsDetails = false
    var showsStatus = false

    private var activeWorkstreams: [Workstream] {
        goal.workstreams
            .filter { $0.status == .inProgress }
            .sorted { $0.endDate < $1.endDate }
    }

    private var nextMilestone: Milestone? {
        goal.milestones
            .filter { !$0.isCompleted && $0.date >= Date.now.startOfDay }
            .min { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(goal.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CMTheme.textPrimary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    if showsStatus && goal.status != .active {
                        Text(goal.status.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CMTheme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(CMTheme.quietFill)
                            .clipShape(Capsule())
                    }
                }

                Text("\(goal.startDate.compactChineseDate) – \(goal.endDate.compactChineseDate)")
                    .font(.system(size: 11))
                    .foregroundStyle(CMTheme.textSecondary)

                if showsDetails && !goal.details.trimmed.isEmpty {
                    Text(goal.details)
                        .font(.system(size: 13))
                        .foregroundStyle(CMTheme.textSecondary)
                        .lineLimit(2)
                        .lineSpacing(3)
                }

                TagPills(tags: goal.tags)
            }

            QuietDivider()

            VStack(alignment: .leading, spacing: 7) {
                Text("当前推进")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CMTheme.textTertiary)

                if activeWorkstreams.isEmpty {
                    Text("暂时没有进行中的推进项")
                        .font(.system(size: 12))
                        .foregroundStyle(CMTheme.textTertiary)
                } else {
                    ForEach(activeWorkstreams.prefix(2)) { workstream in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CMTheme.statusColor(workstream.status))
                                .frame(width: 6, height: 6)
                            Text(workstream.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                }
            }

            if let nextMilestone {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(CMTheme.color(for: "ochre"))
                    Text(nextMilestone.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(nextMilestone.date.compactChineseDate)
                        .font(.system(size: 10))
                        .foregroundStyle(CMTheme.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(CMTheme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(CMTheme.separator, lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityIdentifier("goal-summary-card")
    }
}

struct WorkstreamStatusLabel: View {
    let status: WorkstreamStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CMTheme.statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CMTheme.textSecondary)
        }
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(CMTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SheetFooter: View {
    let canSave: Bool
    let saveTitle: String
    let cancel: () -> Void
    let save: () -> Void

    init(canSave: Bool, saveTitle: String = "保存", cancel: @escaping () -> Void, save: @escaping () -> Void) {
        self.canSave = canSave
        self.saveTitle = saveTitle
        self.cancel = cancel
        self.save = save
    }

    var body: some View {
        HStack {
            Spacer()
            Button("取消", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button(saveTitle, action: save)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.top, 8)
    }
}

struct MultilineEditor: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(CMTheme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(Color.clear)
        }
        .background(CMTheme.quietFill.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(CMTheme.separator, lineWidth: 0.7)
        }
    }
}

extension Date {
    var compactChineseDate: String {
        formatted(.dateTime.year().month(.abbreviated).day().locale(Locale(identifier: "zh_CN")))
    }
}
