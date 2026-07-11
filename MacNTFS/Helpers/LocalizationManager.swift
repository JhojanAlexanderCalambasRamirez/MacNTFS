import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @AppStorage("appLanguage") var language: AppLanguage = .english

    func t(_ key: String) -> String {
        strings[language]?[key] ?? key
    }

    private let strings: [AppLanguage: [String: String]] = [
        .english: [
            "app.title": "MacNTFS",
            "drives": "Drives",
            "ntfs.drives": "NTFS Drives",
            "other.drives": "Other Drives",
            "no.drives": "No External Drives",
            "no.drives.subtitle": "Connect a USB drive to get started",
            "connect.ntfs": "Connect an external NTFS drive",
            "mount.rw": "Mount with Write Support",
            "mounting": "Mounting...",
            "unmount": "Unmount",
            "open.finder": "Open in Finder",
            "logs": "Logs",
            "clear": "Clear",
            "about": "About",
            "settings": "Settings",
            "dependencies": "Dependencies",
            "installed": "Installed",
            "uninstall": "Uninstall",
            "uninstall.title": "Uninstall MacNTFS",
            "uninstall.desc": "This will remove MacNTFS and optionally its dependencies from your system.",
            "uninstall.deps": "Also remove macFUSE and ntfs-3g",
            "uninstall.confirm": "Are you sure you want to uninstall MacNTFS?",
            "uninstall.complete": "Uninstall complete. You can close this window.",
            "uninstall.button": "Uninstall MacNTFS",
            "cancel": "Cancel",
            "rename": "Rename",
            "delete": "Delete",
            "copy": "Copy",
            "move": "Move",
            "items": "items",
            "welcome": "Welcome to MacNTFS",
            "welcome.subtitle": "A few components are needed to enable NTFS write support.\nThis only takes a minute.",
            "install.all": "Install All",
            "get.started": "Get Started",
            "skip": "Skip",
            "install": "Install",
            "appearance": "Appearance",
            "language": "Language",
            "dark.mode": "Dark Mode",
            "theme.system": "System",
            "theme.light": "Light",
            "theme.dark": "Dark",
            "developed.by": "Developed by Alexander Calambas",
            "eject.safe": "Safely Eject",
            "ejecting": "Ejecting...",
            "close": "Close",
            "new.name": "New name",
        ],
        .spanish: [
            "app.title": "MacNTFS",
            "drives": "Discos",
            "ntfs.drives": "Discos NTFS",
            "other.drives": "Otros Discos",
            "no.drives": "Sin Discos Externos",
            "no.drives.subtitle": "Conecta un disco USB para comenzar",
            "connect.ntfs": "Conecta un disco externo NTFS",
            "mount.rw": "Montar con Escritura",
            "mounting": "Montando...",
            "unmount": "Desmontar",
            "open.finder": "Abrir en Finder",
            "logs": "Registros",
            "clear": "Limpiar",
            "about": "Acerca de",
            "settings": "Ajustes",
            "dependencies": "Dependencias",
            "installed": "Instalado",
            "uninstall": "Desinstalar",
            "uninstall.title": "Desinstalar MacNTFS",
            "uninstall.desc": "Esto eliminará MacNTFS y opcionalmente sus dependencias del sistema.",
            "uninstall.deps": "También eliminar macFUSE y ntfs-3g",
            "uninstall.confirm": "¿Estás seguro de que quieres desinstalar MacNTFS?",
            "uninstall.complete": "Desinstalación completa. Puedes cerrar esta ventana.",
            "uninstall.button": "Desinstalar MacNTFS",
            "cancel": "Cancelar",
            "rename": "Renombrar",
            "delete": "Eliminar",
            "copy": "Copiar",
            "move": "Mover",
            "items": "elementos",
            "welcome": "Bienvenido a MacNTFS",
            "welcome.subtitle": "Se necesitan algunos componentes para habilitar escritura NTFS.\nSolo toma un minuto.",
            "install.all": "Instalar Todo",
            "get.started": "Comenzar",
            "skip": "Omitir",
            "install": "Instalar",
            "appearance": "Apariencia",
            "language": "Idioma",
            "dark.mode": "Modo Oscuro",
            "theme.system": "Sistema",
            "theme.light": "Claro",
            "theme.dark": "Oscuro",
            "developed.by": "Desarrollado por Alexander Calambas",
            "eject.safe": "Expulsar de forma segura",
            "ejecting": "Expulsando...",
            "close": "Cerrar",
            "new.name": "Nuevo nombre",
        ],
    ]
}
