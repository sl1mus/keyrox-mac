import Foundation
import SwiftUI

// MARK: - Key Definition
public struct KeyItem: Identifiable, Hashable {
    public let id: Int          // 0..86 index
    public let keyId: String    // from keyboardpos.xml (e.g. "001")
    public let vk: Int          // Windows VK code
    public let name: String     // original name
    public let shortName: String // display label on keycap
    public let x: CGFloat
    public let y: CGFloat
    public let w: CGFloat
    public let h: CGFloat
    
    public init(id: Int, keyId: String, vk: Int, name: String, shortName: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        self.id = id
        self.keyId = keyId
        self.vk = vk
        self.name = name
        self.shortName = shortName
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }
}

// MARK: - JSON Raw Model
private struct RawKeyItem: Codable {
    let idx: Int
    let id: String
    let val: Int
    let name: String
    let x: Int
    let y: Int
    let w: Int
    let h: Int
}

// MARK: - Layout Loader
public struct KeyroxLayout {
    public static let keys: [KeyItem] = loadKeys()
    
    private static func loadKeys() -> [KeyItem] {
        let paths = [
            Bundle.main.path(forResource: "keys", ofType: "json", inDirectory: "assets"),
            Bundle.main.path(forResource: "keys", ofType: "json"),
            "/Users/kistenev/Documents/keyrox-ctl/swift-gui/assets/keys.json"
        ]
        for p in paths {
            if let p = p, let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let rawList = try? JSONDecoder().decode([RawKeyItem].self, from: data) {
                return rawList.map { r in
                    KeyItem(
                        id: r.idx,
                        keyId: r.id,
                        vk: r.val,
                        name: r.name,
                        shortName: formatShort(r.name),
                        x: CGFloat(r.x),
                        y: CGFloat(r.y),
                        w: CGFloat(r.w),
                        h: CGFloat(r.h)
                    )
                }
            }
        }
        return []
    }
    
    private static func formatShort(_ name: String) -> String {
        switch name {
        case "LeftShift", "RightShift", "LeftShif": return "Shift"
        case "LeftCtrl", "RightCtrl": return "Ctrl"
        case "LeftWin": return "Win"
        case "LeftAlt", "RightAlt", "LeftAtl": return "Alt"
        case "Spacebar": return "␣"
        case "PrintScreen": return "PrtSc"
        case "ScrollLock": return "ScrLk"
        case "CapsLock": return "Caps"
        case "Backspace": return "⌫"
        case "Enter": return "↵"
        case "Insert": return "Ins"
        case "Home": return "Hm"
        case "PageUp": return "PgUp"
        case "PageDown": return "PgDn"
        case "ArrowUp": return "▲"
        case "ArrowDown": return "▼"
        case "ArrowLeft": return "◀"
        case "ArrowRight": return "▶"
        default: return name
        }
    }
}

// MARK: - 20 Lighting Modes
public enum LightingMode: Int, CaseIterable, Identifiable {
    case `const` = 0
    case wave = 1
    case cross = 2
    case point = 3
    case custom = 4
    case stars = 5
    case snow = 6
    case rain = 7
    case spectrum = 8
    case breathe = 9
    case lineDiffusion = 10
    case plumflower = 11
    case heartrate = 12
    case shoot = 13
    case rotate = 14
    case rectCone = 15
    case circleDiffusion = 16
    case off = 17
    case multilayer = 18
    case multizone = 19
    
    public var id: Int { rawValue }
    
    public var titleRu: String {
        switch self {
        case .const: return "Статичный (Const)"
        case .wave: return "Волна (Wave)"
        case .cross: return "Перекрестие (Cross)"
        case .point: return "Одиночный всплеск (Point)"
        case .custom: return "Пользовательский (Custom)"
        case .stars: return "Звезды (Stars)"
        case .snow: return "Снегопад (Snow)"
        case .rain: return "Дождь (Rain)"
        case .spectrum: return "Спектр (Spectrum)"
        case .breathe: return "Дыхание (Breathe)"
        case .lineDiffusion: return "Линейная диффузия"
        case .plumflower: return "Цветок (Plumflower)"
        case .heartrate: return "Пульс (Heartrate)"
        case .shoot: return "Выстрел (Shoot)"
        case .rotate: return "Вращение (Rotate)"
        case .rectCone: return "Конус (Rect Cone)"
        case .circleDiffusion: return "Круги на воде"
        case .off: return "Выключено (Off)"
        case .multilayer: return "Многослойный (MultiLayer)"
        case .multizone: return "Зональный (MultiZone)"
        }
    }
    
    public var supportsDirection: Bool {
        switch self {
        case .wave, .rotate, .rectCone, .lineDiffusion, .circleDiffusion:
            return true
        default:
            return false
        }
    }
    
    public var supportsTwoColors: Bool {
        switch self {
        case .breathe, .lineDiffusion, .multilayer, .multizone, .cross:
            return true
        default:
            return false
        }
    }
}

// MARK: - Effect Directions (6 directions)
public enum EffectDirection: Int, CaseIterable, Identifiable {
    case left = 0
    case right = 1
    case top = 2
    case bottom = 3
    case clockwise = 4
    case anticlockwise = 5
    
    public var id: Int { rawValue }
    
    public var titleRu: String {
        switch self {
        case .left: return "Влево ◀"
        case .right: return "Вправо ▶"
        case .top: return "Вверх ▲"
        case .bottom: return "Вниз ▼"
        case .clockwise: return "По часовой ↻"
        case .anticlockwise: return "Против часовой ↺"
        }
    }
}

// MARK: - Multimedia Keys (funkey)
public enum MediaKeyAction: Int, CaseIterable, Identifiable {
    case volumeDown = 233
    case volumeUp = 232
    case mute = 234
    case playPause = 236
    case nextTrack = 237
    case prevTrack = 238
    case cdStop = 235
    case webHome = 245
    case email = 246
    case calculator = 249
    case myPC = 248
    case wwwBack = 240
    case wwwForward = 239
    case wwwSearch = 241
    
    public var id: Int { rawValue }
    
    public var titleRu: String {
        switch self {
        case .volumeDown: return "Громкость -"
        case .volumeUp: return "Громкость +"
        case .mute: return "Отключить звук (Mute)"
        case .playPause: return "Воспроизведение / Пауза"
        case .nextTrack: return "Следующий трек"
        case .prevTrack: return "Предыдущий трек"
        case .cdStop: return "Остановить (Stop)"
        case .webHome: return "Браузер (Home)"
        case .email: return "Почтовый клиент"
        case .calculator: return "Калькулятор"
        case .myPC: return "Мой компьютер / Finder"
        case .wwwBack: return "Назад в браузере"
        case .wwwForward: return "Вперед в браузере"
        case .wwwSearch: return "Поиск в браузере"
        }
    }
}

// MARK: - Keyboard Shortcuts (combkey)
public enum ShortcutAction: String, CaseIterable, Identifiable {
    case selectAll = "Ctrl + A"
    case copy = "Ctrl + C"
    case cut = "Ctrl + X"
    case paste = "Ctrl + V"
    case undo = "Ctrl + Z"
    case save = "Ctrl + S"
    case lockScreen = "Win + L"
    case showDesktop = "Win + D"
    case switchWindow = "Alt + Tab"
    case closeWindow = "Ctrl + W"
    case closeApp = "Alt + F4"
    
    public var id: String { rawValue }
}
