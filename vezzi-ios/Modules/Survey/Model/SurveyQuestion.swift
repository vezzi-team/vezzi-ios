import Foundation

enum SurveyQuestion: String, CaseIterable {
    case priority, distance, basket, household, schedule, routine

    var answers: [SurveyAnswer] {
        switch self {
        case .priority: [.save, .time, .balance, .situation]
        case .distance: [.gladly, .worthwhile, .onTheWay, .shortest, .weather]
        case .basket: [.today, .days, .stock, .varies]
        case .household: [.myself, .pair, .family, .varies]
        case .schedule: [.weekdayDay, .weekdayEvening, .weekend, .freeTime, .week]
        case .routine: [.study, .work, .workStudy, .care, .notWorking, .retired, .other]
        }
    }

    var isOptional: Bool {
        switch self {
        case .priority, .distance, .basket: false
        case .household, .schedule, .routine: true
        }
    }
}

enum SurveyAnswer: String {
    case save, time, balance, situation
    case gladly, worthwhile, onTheWay, shortest, weather
    case today, days, stock, varies
    case myself, pair, family
    case weekdayDay, weekdayEvening, weekend, freeTime, week
    case study, work, workStudy, care, notWorking, retired, other
}
