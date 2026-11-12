import AppKit

extension NSOutlineView {
    func syncSingleColumnWidthToBounds() {
        guard let col = tableColumns.first else { return }
        let width = enclosingScrollView?.contentView.bounds.width ?? bounds.width
        if width > 0, abs(col.width - width) > 0.5 {
            col.width = width
        }
    }
}

// MARK: - Settings (UserDefaults)

enum GallerySettings {
    private static let slideshowPhotoDurationKey = "mygallery.slideshowPhotoDurationSeconds"
    private static let slideshowShuffleKey = "mygallery.slideshowShuffleEnabled"
    private static let slideshowTimeLimitKey = "mygallery.slideshowTimeLimitMinutes"
    private static let slideshowAutoFullscreenKey = "mygallery.slideshowAutoFullscreen"

    static var slideshowPhotoDurationSeconds: Double {
        get {
            let v = UserDefaults.standard.double(forKey: slideshowPhotoDurationKey)
            return v > 0 ? v : 6.0
        }
        set { UserDefaults.standard.set(newValue, forKey: slideshowPhotoDurationKey) }
    }

    static var slideshowShuffleEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: slideshowShuffleKey) }
        set { UserDefaults.standard.set(newValue, forKey: slideshowShuffleKey) }
    }

    /// 分単位、5分刻み。`nil`は無制限。
    static var slideshowTimeLimitMinutes: Int? {
        get {
            let v = UserDefaults.standard.integer(forKey: slideshowTimeLimitKey)
            return v > 0 ? v : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: slideshowTimeLimitKey) }
    }

    static var slideshowAutoFullscreen: Bool {
        get {
            UserDefaults.standard.object(forKey: slideshowAutoFullscreenKey) == nil
                ? true   // 既定はオン(MySlideshowの唯一の従来挙動を踏襲)
                : UserDefaults.standard.bool(forKey: slideshowAutoFullscreenKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: slideshowAutoFullscreenKey) }
    }
}
