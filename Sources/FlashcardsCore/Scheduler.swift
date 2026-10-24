import Foundation

/// Implement this seam to substitute a scheduling engine. Scheduling does not perform storage or I/O.
public protocol ReviewScheduler {
    func schedule(card: Card, rating: ReviewRating, at date: Date) -> Card
}

/// A deliberately approximate, local interval scheduler. This is NOT Anki's scheduler or FSRS.
/// Learning: Again 1 minute, Hard 6 minutes, Good 10 minutes; a second Good graduates at one day.
/// Easy graduates at four days. Mature intervals use an ease multiplier and bounded lapse reduction.
public struct ApproximateLocalScheduler: ReviewScheduler, Sendable {
    public init() {}
    public func schedule(card: Card, rating: ReviewRating, at date: Date) -> Card {
        var next = card
        next.reps += 1
        next.lastReviewedAt = date
        next.buriedUntil = nil
        let seconds: Double
        if card.state == .new || card.state == .learning || card.state == .relearning {
            switch rating {
            case .again:
                next.state = card.state == .relearning ? .relearning : .learning
                seconds = 60
            case .hard:
                next.state = card.state == .relearning ? .relearning : .learning
                seconds = 360
            case .good:
                if card.state == .new {
                    next.state = .learning; seconds = 600
                } else {
                    next.state = .review; seconds = max(1, card.intervalDays) * 86_400
                }
            case .easy:
                next.state = .review; seconds = max(4, card.intervalDays * 1.3) * 86_400
            }
        } else {
            switch rating {
            case .again:
                next.state = .relearning
                next.lapses += 1
                next.easeFactor = max(1.3, card.easeFactor - 0.2)
                seconds = 600
            case .hard:
                next.easeFactor = max(1.3, card.easeFactor - 0.15)
                seconds = max(card.intervalDays + 1, card.intervalDays * 1.2) * 86_400
            case .good:
                seconds = max(card.intervalDays + 1, card.intervalDays * card.easeFactor) * 86_400
            case .easy:
                next.easeFactor = min(3.5, card.easeFactor + 0.15)
                seconds = max(card.intervalDays + 1, card.intervalDays * card.easeFactor * 1.3) * 86_400
            }
        }
        if next.state == .review { next.intervalDays = seconds / 86_400 }
        else if card.state == .review && rating == .again { next.intervalDays = max(1, card.intervalDays * 0.5) }
        next.due = date.addingTimeInterval(seconds)
        return next
    }
}
