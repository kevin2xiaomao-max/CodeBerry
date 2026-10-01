// V36Acceptance fixture — desensitized from XiaoZhangGui/Features/Customer/CustomerView.swift.
// Keeps identifiers + type structure; business logic removed.
import SwiftData
import SwiftUI

struct CustomerView: View {
    @Environment(\.modelContext) private var context
    @Query private var requests: [CustomerRequest]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [CustomerRequest] {
        requests
    }

    var body: some View {
        VStack {
            ForEach(shown, id: \.notificationID) { request in
                CustomerRow(request: request)
            }
        }
    }
}

private struct CustomerRow: View {
    let request: CustomerRequest

    private var icon: String {
        "person"
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(request.displayTitle)
                .foregroundStyle(V32.textPrimary)
        }
    }
}
