import SwiftUI

/// Native menu and stepper provide large, accessible targets; decorative stars never require tapping.
struct PersonalRatingControl: View {
    let current: () throws -> PersonalRating?
    let save: (PersonalRating?) throws -> Void
    @State private var errorMessage: String?
    @State private var saved = false

    private var selected: PersonalRating? { try? current() }
    private var invalidStoredValue: Bool { if case .failure = Result(catching: current) { true } else { false } }

    private var units: Binding<Int> {
        Binding(get: { (try? current())?.halfStarUnits ?? 0 }, set: { value in
            do {
                let rating: PersonalRating?
                if value == 0 { rating = nil } else { rating = try PersonalRating(halfStarUnits: value) }
                try save(rating)
                saved = true
            } catch {
                saved = false
                errorMessage = error.localizedDescription
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Spacing.small) {
            Text("Your personal rating").font(.headline).accessibilityAddTraits(.isHeader)
            if invalidStoredValue {
                Text("Stored personal rating unavailable. Choose a value to replace it, or clear it.")
                    .font(.subheadline).accessibilityIdentifier("rating.invalid")
            } else {
                RatingStars(rating: selected)
                Text(selected?.label ?? "Unrated").accessibilityIdentifier("rating.value")
            }
            Picker("Your rating", selection: units) {
                Text("Unrated").tag(0)
                ForEach(PersonalRating.allValues, id: \.halfStarUnits) { rating in
                    Text(rating.label).tag(rating.halfStarUnits)
                }
            }
            .pickerStyle(.menu)
            .accessibilityValue(invalidStoredValue ? "Stored rating unavailable" : selected?.label ?? "Unrated")
            .accessibilityIdentifier("rating.picker")
            Stepper("Adjust personal rating", value: units, in: 0...10)
                .accessibilityValue(invalidStoredValue ? "Stored rating unavailable" : selected?.label ?? "Unrated")
                .accessibilityIdentifier("rating.stepper")
            if selected != nil || invalidStoredValue {
                Button("Clear Personal Rating") { units.wrappedValue = 0 }
                    .accessibilityIdentifier("rating.clear")
            }
            if saved { Text("Saved").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("rating.saved") }
        }
        .alert("Rating could not be saved", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "Please try again.") }
    }
}

struct RatingStars: View {
    let rating: PersonalRating?
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                Image(systemName: symbol(index))
            }
        }
        .font(.body)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }

    private func symbol(_ index: Int) -> String {
        let units = rating?.halfStarUnits ?? 0
        if units >= index * 2 + 2 { return "star.fill" }
        if units == index * 2 + 1 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct PersonalRatingSummary: View {
    let entry: StoredLibraryEntry?
    var body: some View {
        Group {
            switch Result(catching: { try entry?.validatedRating() }) {
            case .success(let rating): Text(rating.map { "Your rating: \($0.label)" } ?? "Unrated")
            case .failure: Text("Personal rating unavailable")
            }
        }
        .font(.subheadline)
        .accessibilityIdentifier("rating.summary")
    }
}
