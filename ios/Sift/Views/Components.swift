import SwiftUI

/// The per-type marker used in lists and month cells. Colour, glyph and a count
/// or label together, so the meaning survives without colour vision.
struct KindChip: View {
    let kind: ItemKind
    var count: Int?
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.glyph)
                .font(.system(size: compact ? 5 : 6))
            if let count {
                Text("\(count)")
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .monospacedDigit()
            } else if !compact {
                Text(kind.label)
                    .font(Theme.caption)
            }
        }
        .foregroundStyle(Theme.accent(for: kind))
    }
}

struct SectionHeading: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.inkFaint)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .padding(.bottom, 2)
    }
}

/// A dated event, in a day list.
struct OccurrenceRow: View {
    let occurrence: Occurrence

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(occurrence.start.formatted(date: .omitted, time: .shortened))
                    .font(Theme.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let end = occurrence.end {
                    Text(end.formatted(date: .omitted, time: .shortened))
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .frame(width: 62, alignment: .trailing)

            Rectangle()
                .fill(Theme.event)
                .frame(width: 2)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(occurrence.title)
                        .font(Theme.serif(17))
                        .foregroundStyle(Theme.ink)
                    if occurrence.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    if occurrence.needsReview {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.backlog)
                    }
                }
                if let details = occurrence.details {
                    Text(details)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }
}

/// A task, backlog item, or note in a day list.
struct ItemRow: View {
    let item: Item
    var showAge = false
    var onToggle: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.kind == .note {
                Image(systemName: ItemKind.note.glyph)
                    .font(.system(size: 6))
                    .foregroundStyle(Theme.note)
                    .padding(.top, 7)
            } else {
                Button {
                    onToggle?()
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(item.isDone ? Theme.inkFaint : Theme.accent(for: item.kind))
                }
                .buttonStyle(.plain)
                .disabled(onToggle == nil)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(item.kind == .note ? Theme.serif(16) : Theme.body)
                        .foregroundStyle(item.isDone ? Theme.inkFaint : Theme.ink)
                        .strikethrough(item.isDone, color: Theme.inkFaint)
                    if item.isSoftDate {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    if item.needsReview {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.backlog)
                    }
                }
                if let details = item.details {
                    Text(details)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            Spacer(minLength: 0)

            if showAge, item.ageInDays > 0 {
                Text("\(item.ageInDays)d")
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(item.ageInDays >= 7 ? Theme.backlog : Theme.inkFaint)
            }
        }
        .padding(.vertical, 6)
    }
}

struct QuietMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.serif(15))
            .italic()
            .foregroundStyle(Theme.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }
}
