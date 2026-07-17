import SwiftUI

/// iPhone Calendar tab. Week strip at the top for jumping between
/// days, then a vertical day timeline showing schedule blocks.
struct IPhoneCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dayBlocks: [ScheduleBlock] {
        appState.scheduleBlocks
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.startHour < $1.startHour }
    }

    private var hours: [Int] { Array(6..<23) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekStrip

                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            hourRow(hour: hour)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(HubPalette.grouped)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(HubPalette.separator, lineWidth: 0.5)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(HubPalette.background)
            .navigationTitle(selectedDate.formatted(.dateTime.month(.wide).year()))
            #if os(iOS)

            .navigationBarTitleDisplayMode(.inline)

            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        selectedDate = Calendar.current.startOfDay(for: Date())
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                #endif
            }
            .refreshable { await appState.syncNow() }
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                Button { selectedDate = day } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .white : HubPalette.secondaryText)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .white : HubPalette.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? HubPalette.hubAccent : HubPalette.grouped)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? Color.clear : HubPalette.separator, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hour row

    @ViewBuilder
    private func hourRow(hour: Int) -> some View {
        let blocksAtHour = dayBlocks.filter { Int($0.startHour) == hour }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                Text(formatHour(hour))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(HubPalette.tertiaryText)
                    .frame(width: 48, alignment: .trailing)
                VStack(alignment: .leading, spacing: 4) {
                    if blocksAtHour.isEmpty {
                        Rectangle()
                            .fill(HubPalette.separator)
                            .frame(height: 0.5)
                            .padding(.top, 7)
                    } else {
                        ForEach(blocksAtHour) { block in
                            ScheduleBlockCard(block: block, compact: true)
                                .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour == 12 ? 12 : hour % 12
        return "\(display) \(suffix)"
    }
}
