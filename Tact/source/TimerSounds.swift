import AppKit
import SwiftUI

enum TimerSound: String, CaseIterable, Identifiable, Codable {
    case glass = "Glass"
    case ping = "Ping"
    case tink = "Tink"
    case pop = "Pop"
    case hero = "Hero"
    case purr = "Purr"
    case none = "None"

    var id: String { rawValue }

    func play() {
        guard self != .none else { return }
        NSSound(named: NSSound.Name(rawValue))?.play()
    }

    static var defaultSound: TimerSound {
        TimerSound(rawValue: UserDefaults.standard.string(forKey: "timerCompletionSound") ?? "") ?? .glass
    }
}

struct SoundSettings: View {
    @AppStorage("timerCompletionSound") private var selected = TimerSound.glass.rawValue

    var body: some View {
        HStack {
            Picker("Completion sound", selection: $selected) {
                ForEach(TimerSound.allCases) { sound in
                    Text(sound.rawValue).tag(sound.rawValue)
                }
            }
            Button("Preview") { (TimerSound(rawValue: selected) ?? .glass).play() }
                .disabled(selected == TimerSound.none.rawValue)
        }
        .onChange(of: selected) { _, value in TimerSound(rawValue: value)?.play() }
    }
}
