enum LoginItemState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unknown

    var isEnabled: Bool { self == .enabled }

    var statusText: String {
        switch self {
        case .enabled:
            return "登录启动：已启用"
        case .notRegistered:
            return "登录启动：未启用"
        case .requiresApproval:
            return "登录启动：需要批准（尚未启用）。请在系统设置 → 通用 → 登录项中允许轻栏。"
        case .notFound:
            return "登录启动：未找到应用。请将轻栏放在固定的应用目录后再试。"
        case .unknown:
            return "登录启动：系统状态未知，请在系统设置 → 通用 → 登录项中检查。"
        }
    }
}
