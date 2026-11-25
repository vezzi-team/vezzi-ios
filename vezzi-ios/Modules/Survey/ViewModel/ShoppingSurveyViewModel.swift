import Combine
import Foundation

@MainActor
final class ShoppingSurveyViewModel: ObservableObject {
    @Published private(set) var index = 0
    @Published private(set) var answers: [SurveyQuestion: SurveyAnswer] = [:]
    @Published private(set) var result: ShoppingMode?

    var question: SurveyQuestion { SurveyQuestion.allCases[index] }
    var canAdvance: Bool { answers[question] != nil }

    // Early iOS 26 runtimes can crash when Swift releases a MainActor-isolated object.
    nonisolated deinit {}

    @discardableResult
    func select(_ answer: SurveyAnswer, for question: SurveyQuestion) -> Bool {
        guard result == nil, self.question == question, question.answers.contains(answer),
              answers[question] != answer else { return false }
        answers[question] = answer
        return true
    }

    func back() {
        guard result == nil, index > 0 else { return }
        index -= 1
    }

    func advance(skipping: Bool = false, preferences: ShoppingPreferences, accountID: UUID) {
        guard result == nil, preferences.accountID == accountID else { return }
        if skipping {
            guard question.isOptional else { return }
            answers.removeValue(forKey: question)
        } else if !canAdvance {
            return
        }
        if index + 1 < SurveyQuestion.allCases.count {
            index += 1
        } else {
            let mode = recommendation(fallback: preferences.mode)
            preferences.completeSurvey(with: mode, for: accountID)
            result = mode
        }
    }

    private func recommendation(fallback: ShoppingMode) -> ShoppingMode {
        // Explicit priorities win. Only use willingness to walk when the first answer is neutral.
        switch answers[.priority] {
        case .save: return .cheaper
        case .time: return .faster
        default: break
        }
        switch answers[.distance] {
        case .gladly, .worthwhile: return .cheaper
        case .onTheWay, .shortest: return .faster
        default: return fallback
        }
    }
}
