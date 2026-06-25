import Foundation

/// The user's language choice, stored under the "language" key.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return Loc.t("System")
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

/// Tiny in-app localizer. English source text *is* the key; Spanish comes from the
/// table below. "System" follows the OS language. Reads UserDefaults live, so
/// SwiftUI re-renders and freshly-built AppKit views pick up changes.
enum Loc {
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system
    }

    private static var activeIsSpanish: Bool {
        switch current {
        case .spanish: return true
        case .english: return false
        case .system: return (Locale.preferredLanguages.first ?? "en").hasPrefix("es")
        }
    }

    static func t(_ en: String) -> String {
        guard activeIsSpanish else { return en }
        return spanish[en] ?? en
    }

    private static let spanish: [String: String] = [
        // Menu
        "Take a break now": "Tomar un descanso ahora",
        "Skip break": "Saltar descanso",
        "Postpone 5 min": "Posponer 5 min",
        "Pause": "Pausar",
        "Resume": "Reanudar",
        "Pause for": "Pausar por",
        "30 minutes": "30 minutos",
        "1 hour": "1 hora",
        "2 hours": "2 horas",
        "Until tomorrow": "Hasta mañana",
        "Meeting mode": "Modo reunión",
        "Settings…": "Ajustes…",
        "Quit SoftFocus": "Salir de SoftFocus",
        "Next break in": "Próximo descanso en",
        "On break": "En descanso",
        "Paused": "En pausa",
        "In a meeting": "En una reunión",
        "until": "hasta",
        "Don't pause for this meeting": "No pausar en esta reunión",
        "Meeting in %d min: %@": "Reunión en %d min: %@",
        // Overlay
        "Look away from your screen": "Aparta la vista de la pantalla",
        "Time to stand up and stretch": "Hora de pararte y estirar",
        "BREAK": "DESCANSO",
        "LONG BREAK": "DESCANSO LARGO",
        "Snooze 5 min": "Posponer 5 min",
        "Break coming up…": "Descanso en breve…",
        // Tips
        "Rest your eyes. Focus on something far away.": "Descansá los ojos. Mirá algo lejano.",
        "Look about 20 feet away for 20 seconds.": "Mirá a unos 6 metros por 20 segundos.",
        "Blink slowly a few times to refresh your eyes.": "Parpadeá lento unas veces para refrescar los ojos.",
        "Roll your shoulders back and let them drop.": "Rotá los hombros hacia atrás y soltalos.",
        "Unclench your jaw and relax your face.": "Aflojá la mandíbula y relajá la cara.",
        "Stand up and stretch your back.": "Parate y estirá la espalda.",
        "Look out a window if you have one.": "Mirá por una ventana si tenés.",
        "Breathe in slowly, out even slower.": "Inhalá lento, exhalá más lento todavía.",
        // Nudges
        "Blink 👀": "Parpadeá 👀",
        "Sit up straight 🧍": "Enderezate 🧍",
        "SoftFocus is on — look for 👁 in the menu bar": "SoftFocus está activo — buscá el 👁 en la barra de menú",
        // Settings
        "Settings": "Ajustes",
        "Take care of your eyes": "Cuidá tus ojos",
        "Breaks": "Descansos",
        "Nudges": "Recordatorios",
        "General": "General",
        "Work": "Trabajo",
        "Break": "Descanso",
        "Long break now and then": "Descanso largo de vez en cuando",
        "Every %d breaks": "Cada %d descansos",
        "Long break": "Descanso largo",
        "Warn me before a break": "Avisarme antes de un descanso",
        "Every": "Cada",
        "Blink reminders": "Recordatorios de parpadeo",
        "Posture reminders": "Recordatorios de postura",
        "Pause when camera is on (meetings)": "Pausar con la cámara prendida (reuniones)",
        "Launch at login": "Abrir al iniciar sesión",
        "Chime on break": "Sonido en el descanso",
        "Rotating eye-care tips": "Tips rotativos para los ojos",
        "Custom break message (optional)": "Mensaje propio del descanso (opcional)",
        "Language": "Idioma",
        "System": "Sistema",
        "min": "min",
        "sec": "seg",
        // Google Calendar
        "Connected": "Conectado",
        "Disconnect": "Desconectar",
        "Connect Google Calendar": "Conectar Google Calendar",
        "Connecting…": "Conectando…",
        "Pause breaks during calendar meetings.": "Pausa los descansos durante reuniones del calendario.",
        "Pause breaks during calendar meetings. Needs a Google Cloud “Desktop app” OAuth client.":
            "Pausa los descansos durante reuniones del calendario. Necesita un OAuth client “Desktop app” de Google Cloud.",
    ]
}
