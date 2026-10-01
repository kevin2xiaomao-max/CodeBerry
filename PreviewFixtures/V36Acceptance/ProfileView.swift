// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Profile/ProfileView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var performances: [Performance]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var monthlyGoal: Double {
        0
    }

    var body: some View {
        VStack {
            profileHero
        }
    }

    private var profileHero: some View {
        VStack {
            Text(profileGreeting)
                .foregroundStyle(V32.textPrimary)
            Text("\(monthlyGoal)")
                .foregroundStyle(V32.textSecondary)
        }
    }

    private var profileGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "早上好" }
        if hour < 18 { return "下午好" }
        return "晚上好"
    }
}
