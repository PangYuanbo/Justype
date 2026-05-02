import Foundation

enum Language: String, CaseIterable, Codable {
    case en
    case zh

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

/// Central translation table. Add a case here, fill both `en` and `zh`,
/// and reference it as `L10n.someKey.t` from views/menus. For strings that
/// take runtime arguments, use the static functions further down.
enum L10n: String {
    // Menu bar
    case menuEnableFuzzy
    case menuDisableFuzzy
    case menuTriggerKey
    case menuUseScreenContext
    case menuLLMSettings
    case menuHistory
    case menuHistoryEmpty
    case menuClearHistory
    case menuQuit
    case menuLanguage
    case menuCorrections
    case menuCorrectionsCount
    case menuClearCorrections

    // Trigger names
    case triggerFn
    case triggerRightOption
    case triggerCapsLock

    // Settings window
    case settingsTitle
    case settingsEndpointSection
    case settingsBaseURL
    case settingsAPIKey
    case settingsClearButton
    case settingsKeyHint
    case settingsModelSection
    case settingsLoading
    case settingsRefreshTooltip
    case settingsSearchPlaceholder
    case settingsVisionOnly
    case settingsCurrent
    case settingsNoneSelected
    case settingsSupportsImage
    case settingsTesting
    case settingsTestButton
    case settingsLanguage
    case settingsAppearance

    // HUD
    case hudWaiting
    case hudConverting
    case hudAcceptHint
    case hudSubmitHint
    case hudHelp
    case hudKeepTyping
    case hudReadyToSubmit
    case hudPasteFailedTitle
    case hudPasteFailedHint

    // Errors
    case errorMissingAPIKey
    case errorInvalidURL
    case errorDecoding
    case errorEmpty
    case errorParseModelList

    // Accessibility prompt
    case axAlertTitle
    case axAlertBody
    case axAlertOpen
    case axAlertLater

    // Main menu (app/edit/window)
    case mainAbout
    case mainHide
    case mainQuit
    case mainEdit
    case mainUndo
    case mainRedo
    case mainCut
    case mainCopy
    case mainPaste
    case mainSelectAll
    case mainWindow
    case mainClose

    // MARK: - Resolution

    var t: String {
        switch AppState.shared.language {
        case .en: return en
        case .zh: return zh
        }
    }

    private var en: String {
        switch self {
        case .menuEnableFuzzy:        return "Enable Fuzzy Input"
        case .menuDisableFuzzy:       return "Disable Fuzzy Input"
        case .menuTriggerKey:         return "Trigger Key"
        case .menuUseScreenContext:   return "Use Screenshot as Context"
        case .menuLLMSettings:        return "LLM Settings…"
        case .menuHistory:            return "History"
        case .menuHistoryEmpty:       return "(empty)"
        case .menuClearHistory:       return "Clear History"
        case .menuQuit:               return "Quit JustType"
        case .menuLanguage:           return "Language"
        case .menuCorrections:        return "Learned Corrections"
        case .menuCorrectionsCount:   return "Saved corrections"
        case .menuClearCorrections:   return "Clear Corrections"

        case .triggerFn:              return "Fn"
        case .triggerRightOption:     return "Right Option (⌥)"
        case .triggerCapsLock:        return "Caps Lock"

        case .settingsTitle:          return "JustType Settings"
        case .settingsEndpointSection:return "Endpoint"
        case .settingsBaseURL:        return "Base URL"
        case .settingsAPIKey:         return "API Key"
        case .settingsClearButton:    return "Clear"
        case .settingsKeyHint:        return "Get a free key at openrouter.ai/keys"
        case .settingsModelSection:   return "Model"
        case .settingsLoading:        return "Loading…"
        case .settingsRefreshTooltip: return "Refresh model list"
        case .settingsSearchPlaceholder: return "Search models…"
        case .settingsVisionOnly:     return "Vision-capable only"
        case .settingsCurrent:        return "Current"
        case .settingsNoneSelected:   return "(none selected)"
        case .settingsSupportsImage:  return "Supports image input"
        case .settingsTesting:        return "Testing…"
        case .settingsTestButton:     return "Test current config"
        case .settingsLanguage:       return "Language"
        case .settingsAppearance:     return "Appearance"

        case .hudWaiting:             return "Waiting for input…"
        case .hudConverting:          return "Converting…"
        case .hudAcceptHint:          return "↩ Accept"
        case .hudSubmitHint:          return "↩ Submit"
        case .hudHelp:                return "Type → pause → a candidate appears below. ↩ accepts it. ↩ again to submit, or tap the trigger key."
        case .hudKeepTyping:          return "Keep typing…"
        case .hudReadyToSubmit:       return "All converted — press ↩ to submit"
        case .hudPasteFailedTitle:    return "Couldn't paste"
        case .hudPasteFailedHint:     return "The text is on your clipboard — press ⌘V to insert it manually."

        case .errorMissingAPIKey:     return "API key not set"
        case .errorInvalidURL:        return "Invalid Base URL"
        case .errorDecoding:          return "Failed to parse response"
        case .errorEmpty:             return "Empty response"
        case .errorParseModelList:    return "Failed to parse model list"

        case .axAlertTitle:           return "Accessibility Permission Required"
        case .axAlertBody:
            return "JustType needs Accessibility permission to listen for the trigger key and capture keystrokes.\n\nOpen System Settings → Privacy & Security → Accessibility, add JustType, turn the switch on, then restart the app."
        case .axAlertOpen:            return "Open System Settings"
        case .axAlertLater:           return "Later"

        case .mainAbout:              return "About JustType"
        case .mainHide:               return "Hide JustType"
        case .mainQuit:               return "Quit JustType"
        case .mainEdit:               return "Edit"
        case .mainUndo:               return "Undo"
        case .mainRedo:               return "Redo"
        case .mainCut:                return "Cut"
        case .mainCopy:               return "Copy"
        case .mainPaste:              return "Paste"
        case .mainSelectAll:          return "Select All"
        case .mainWindow:             return "Window"
        case .mainClose:              return "Close"
        }
    }

    private var zh: String {
        switch self {
        case .menuEnableFuzzy:        return "启用模糊输入"
        case .menuDisableFuzzy:       return "停用模糊输入"
        case .menuTriggerKey:         return "触发键"
        case .menuUseScreenContext:   return "使用屏幕截图作为上下文"
        case .menuLLMSettings:        return "LLM 设置…"
        case .menuHistory:            return "历史记录"
        case .menuHistoryEmpty:       return "（暂无）"
        case .menuClearHistory:       return "清空历史"
        case .menuQuit:               return "退出 JustType"
        case .menuLanguage:           return "界面语言"
        case .menuCorrections:        return "已学习的纠正"
        case .menuCorrectionsCount:   return "已记录纠正条数"
        case .menuClearCorrections:   return "清空纠正记录"

        case .triggerFn:              return "Fn"
        case .triggerRightOption:     return "Right Option (⌥)"
        case .triggerCapsLock:        return "Caps Lock"

        case .settingsTitle:          return "JustType 设置"
        case .settingsEndpointSection:return "接入点"
        case .settingsBaseURL:        return "Base URL"
        case .settingsAPIKey:         return "API Key"
        case .settingsClearButton:    return "清空"
        case .settingsKeyHint:        return "免费注册 OpenRouter 拿 key：openrouter.ai/keys"
        case .settingsModelSection:   return "模型"
        case .settingsLoading:        return "加载中…"
        case .settingsRefreshTooltip: return "刷新模型列表"
        case .settingsSearchPlaceholder: return "搜索模型…"
        case .settingsVisionOnly:     return "仅看支持图片"
        case .settingsCurrent:        return "当前"
        case .settingsNoneSelected:   return "（未选择）"
        case .settingsSupportsImage:  return "支持图片输入"
        case .settingsTesting:        return "测试中…"
        case .settingsTestButton:     return "测试当前配置"
        case .settingsLanguage:       return "界面语言"
        case .settingsAppearance:     return "外观"

        case .hudWaiting:             return "等待输入…"
        case .hudConverting:          return "正在转换…"
        case .hudAcceptHint:          return "↩ 接受"
        case .hudSubmitHint:          return "↩ 提交"
        case .hudHelp:                return "打字 → 停顿 → 候选出现在下方。↩ 接受候选;↩ 再按一次提交,或按一次触发键。"
        case .hudKeepTyping:          return "继续输入…"
        case .hudReadyToSubmit:       return "已全部转换 — 按 ↩ 提交"
        case .hudPasteFailedTitle:    return "无法自动粘贴"
        case .hudPasteFailedHint:     return "内容已复制到剪贴板,在目标输入框按 ⌘V 即可粘贴。"

        case .errorMissingAPIKey:     return "API Key 未配置"
        case .errorInvalidURL:        return "Base URL 无效"
        case .errorDecoding:          return "返回解析失败"
        case .errorEmpty:             return "返回为空"
        case .errorParseModelList:    return "解析模型列表失败"

        case .axAlertTitle:           return "需要「辅助功能」权限"
        case .axAlertBody:
            return "JustType 需要「辅助功能 (Accessibility)」权限来监听触发键并捕获按键。\n\n请到 系统设置 → 隐私与安全性 → 辅助功能,把 JustType 加入并打开开关,然后重新启动 App。"
        case .axAlertOpen:            return "打开系统设置"
        case .axAlertLater:           return "稍后"

        case .mainAbout:              return "关于 JustType"
        case .mainHide:               return "隐藏 JustType"
        case .mainQuit:               return "退出 JustType"
        case .mainEdit:               return "编辑"
        case .mainUndo:               return "撤销"
        case .mainRedo:               return "重做"
        case .mainCut:                return "剪切"
        case .mainCopy:               return "拷贝"
        case .mainPaste:              return "粘贴"
        case .mainSelectAll:          return "全选"
        case .mainWindow:             return "窗口"
        case .mainClose:              return "关闭"
        }
    }

    // MARK: - Parameterized strings

    /// "Available: 318" / "可用：318"
    static func availableCount(_ count: Int) -> String {
        switch AppState.shared.language {
        case .en: return "Available: \(count)"
        case .zh: return "可用：\(count)"
        }
    }

    /// HTTP error: "HTTP 401: ..."
    static func httpError(_ code: Int, _ message: String) -> String {
        switch AppState.shared.language {
        case .en: return "HTTP \(code): \(message)"
        case .zh: return "HTTP \(code)：\(message)"
        }
    }
}
