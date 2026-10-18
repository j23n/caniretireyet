import SwiftUI

/// Your age today, from a menu that starts unset, so none is made up. The
/// tour saves it as a birth date (``YouSettings/birthDate(forAge:today:)``).
struct OnboardingAgePicker: View {
    @Binding var age: Int?

    var body: some View {
        LabeledContent("Age") {
            Picker("Age", selection: $age) {
                Text("Choose").tag(Int?.none)
                ForEach(OnboardingScreen.currentAges, id: \.self) { age in
                    Text(age, format: .number).tag(Optional(age))
                }
            }
            .labelsHidden()
            .personalControl()
        }
    }
}
