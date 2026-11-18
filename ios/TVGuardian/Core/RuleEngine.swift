import Foundation

enum RuleEngine {
    static func isActive(_ schedule: RestrictionSchedule, at date: Date) -> Bool {
        guard schedule.enabled, let zone = TimeZone(identifier: schedule.timeZoneID),
              (0..<1440).contains(schedule.startMinute), (0..<1440).contains(schedule.endMinute) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let now = hour * 60 + minute
        let days = Set(schedule.weekdays.filter { (1...7).contains($0) })
        if schedule.startMinute == schedule.endMinute { return days.contains(weekday) }
        if schedule.startMinute < schedule.endMinute {
            return days.contains(weekday) && now >= schedule.startMinute && now < schedule.endMinute
        }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return (days.contains(weekday) && now >= schedule.startMinute)
            || (days.contains(previousDay) && now < schedule.endMinute)
    }

    static func evaluate(tvID: UUID, appID: String, state: GuardianState, at date: Date = Date()) -> LaunchDecision {
        if let rule = state.rules.first(where: { $0.tvID == tvID && $0.appID == appID }) {
            if rule.blocked { return LaunchDecision(allowed: false, reason: "Blocked in TV Guardian. The TV's physical remote is outside this rule.") }
            if let minimum = rule.minimumAge {
                guard let profile = state.profiles.first(where: { $0.id == state.activeProfileID }) else {
                    return LaunchDecision(allowed: false, reason: "Select a child profile to evaluate the parent-assigned age threshold.")
                }
                if profile.age < minimum { return LaunchDecision(allowed: false, reason: "Below the parent-assigned age threshold (\(minimum)+).") }
            }
        }
        if let schedule = state.schedules.first(where: {
            $0.tvID == tvID && ($0.appID == nil || $0.appID == appID) && isActive($0, at: date)
        }) { return LaunchDecision(allowed: false, reason: "\(schedule.name) is active in \(schedule.timeZoneID). Applies to TV Guardian launches only.") }
        return LaunchDecision(allowed: true, reason: "Allowed by this controller. Native TV lock state is unknown.")
    }
}
