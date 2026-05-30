import WebKit

struct Cookie {
    var name: String
    var value: String
}

// Стартовый URL — изолированная iOS-копия приложения (скрыта монетизация,
// только email-вход, аналитика отключена). См. ios-compat.js на /app/.
let rootUrl = URL(string: "https://vatma.ru/app/")!

// Домены, остающиеся внутри WebView. Должны совпадать с WKAppBoundDomains в Info.plist.
let allowedOrigins: [String] = ["vatma.ru"]

// Сторонний вход (Apple/Google) НЕ используется — массив пуст (Guideline 4.8 не применяется).
let authOrigins: [String] = []
// allowedOrigins + authOrigins <= 10

let platformCookie = Cookie(name: "app-platform", value: "iOS App Store")

// UI options
let displayMode = "standalone"   // standalone / fullscreen
let adaptiveUIStyle = true       // iOS 15+: тема приложения подстраивается под фон WebView
let overrideStatusBar = false
let statusBarTheme = "dark"
let pullToRefresh = true
