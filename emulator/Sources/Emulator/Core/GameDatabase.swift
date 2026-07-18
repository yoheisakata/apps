import Foundation

enum GameSystem: String, CaseIterable, Identifiable {
    case nes = "NES"
    case snes = "SNES"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: return "ファミコン"
        case .snes: return "スーパーファミコン"
        }
    }

    var thumbnailSystem: String {
        switch self {
        case .nes: return "Nintendo - Nintendo Entertainment System"
        case .snes: return "Nintendo - Super Nintendo Entertainment System"
        }
    }

    var romExtensions: [String] {
        switch self {
        case .nes: return ["nes"]
        case .snes: return ["sfc", "smc"]
        }
    }
}

struct GameTitle: Identifiable, Hashable {
    let id: String
    let name: String
    let japanName: String
    let system: GameSystem
    let year: Int
    let genre: String

    var thumbnailName: String { name }
}

struct GameDatabase {
    static let titles: [GameTitle] = nesGames + snesGames

    static func search(_ query: String, system: GameSystem? = nil) -> [GameTitle] {
        let filtered = system.map { sys in titles.filter { $0.system == sys } } ?? titles
        if query.isEmpty { return filtered }
        let q = query.lowercased()
        return filtered.filter {
            $0.name.lowercased().contains(q) ||
            $0.japanName.contains(q) ||
            $0.genre.lowercased().contains(q)
        }
    }

    // MARK: - NES

    static let nesGames: [GameTitle] = [
        g("Super Mario Bros.", "スーパーマリオブラザーズ", .nes, 1985, "アクション"),
        g("Super Mario Bros. 2", "スーパーマリオブラザーズ2", .nes, 1988, "アクション"),
        g("Super Mario Bros. 3", "スーパーマリオブラザーズ3", .nes, 1988, "アクション"),
        g("The Legend of Zelda", "ゼルダの伝説", .nes, 1986, "アクションRPG"),
        g("Zelda II - The Adventure of Link", "リンクの冒険", .nes, 1987, "アクションRPG"),
        g("Metroid", "メトロイド", .nes, 1986, "アクション"),
        g("Mega Man", "ロックマン", .nes, 1987, "アクション"),
        g("Mega Man 2", "ロックマン2", .nes, 1988, "アクション"),
        g("Mega Man 3", "ロックマン3", .nes, 1990, "アクション"),
        g("Mega Man 4", "ロックマン4", .nes, 1991, "アクション"),
        g("Mega Man 5", "ロックマン5", .nes, 1992, "アクション"),
        g("Mega Man 6", "ロックマン6", .nes, 1993, "アクション"),
        g("Castlevania", "悪魔城ドラキュラ", .nes, 1986, "アクション"),
        g("Castlevania II - Simon's Quest", "ドラキュラII 呪いの封印", .nes, 1987, "アクションRPG"),
        g("Castlevania III - Dracula's Curse", "悪魔城伝説", .nes, 1989, "アクション"),
        g("Contra", "魂斗羅", .nes, 1988, "アクション"),
        g("Super Contra", "スーパー魂斗羅", .nes, 1990, "アクション"),
        g("Double Dragon", "ダブルドラゴン", .nes, 1988, "アクション"),
        g("Double Dragon II - The Revenge", "ダブルドラゴンII", .nes, 1989, "アクション"),
        g("Ninja Gaiden", "忍者龍剣伝", .nes, 1988, "アクション"),
        g("Ninja Gaiden II - The Dark Sword of Chaos", "忍者龍剣伝II", .nes, 1990, "アクション"),
        g("Ninja Gaiden III - The Ancient Ship of Doom", "忍者龍剣伝III", .nes, 1991, "アクション"),
        g("Kirby's Adventure", "星のカービィ 夢の泉の物語", .nes, 1993, "アクション"),
        g("Kid Icarus", "光神話 パルテナの鏡", .nes, 1986, "アクション"),
        g("Punch-Out!!", "パンチアウト!!", .nes, 1987, "スポーツ"),
        g("Donkey Kong", "ドンキーコング", .nes, 1983, "アクション"),
        g("Donkey Kong Jr.", "ドンキーコングJr.", .nes, 1983, "アクション"),
        g("Mario Bros.", "マリオブラザーズ", .nes, 1983, "アクション"),
        g("Dr. Mario", "ドクターマリオ", .nes, 1990, "パズル"),
        g("Tetris", "テトリス", .nes, 1989, "パズル"),
        g("Ice Climber", "アイスクライマー", .nes, 1985, "アクション"),
        g("Excitebike", "エキサイトバイク", .nes, 1984, "レース"),
        g("Balloon Fight", "バルーンファイト", .nes, 1984, "アクション"),
        g("Duck Hunt", "ダックハント", .nes, 1984, "シューティング"),
        g("Gradius", "グラディウス", .nes, 1986, "シューティング"),
        g("Life Force", "沙羅曼蛇", .nes, 1988, "シューティング"),
        g("1942", "1942", .nes, 1985, "シューティング"),
        g("Ghosts'n Goblins", "魔界村", .nes, 1986, "アクション"),
        g("Bomberman", "ボンバーマン", .nes, 1985, "アクション"),
        g("Adventure Island", "高橋名人の冒険島", .nes, 1986, "アクション"),
        g("Tecmo Super Bowl", "テクモスーパーボウル", .nes, 1991, "スポーツ"),
        g("River City Ransom", "ダウンタウン熱血物語", .nes, 1989, "アクションRPG"),
        g("Battletoads", "バトルトード", .nes, 1991, "アクション"),
        g("Final Fantasy", "ファイナルファンタジー", .nes, 1987, "RPG"),
        g("Final Fantasy II", "ファイナルファンタジーII", .nes, 1988, "RPG"),
        g("Final Fantasy III", "ファイナルファンタジーIII", .nes, 1990, "RPG"),
        g("Dragon Quest", "ドラゴンクエスト", .nes, 1986, "RPG"),
        g("Dragon Quest II", "ドラゴンクエストII", .nes, 1987, "RPG"),
        g("Dragon Quest III", "ドラゴンクエストIII", .nes, 1988, "RPG"),
        g("Dragon Quest IV", "ドラゴンクエストIV", .nes, 1990, "RPG"),
        g("Mother", "MOTHER", .nes, 1989, "RPG"),
        g("Fire Emblem - Shadow Dragon and the Blade of Light", "ファイアーエムブレム 暗黒竜と光の剣", .nes, 1990, "シミュレーションRPG"),
        g("Tecmo Bowl", "テクモボウル", .nes, 1989, "スポーツ"),
        g("R.C. Pro-Am", "R.C.プロアム", .nes, 1987, "レース"),
        g("Blaster Master", "超惑星戦記メタファイト", .nes, 1988, "アクション"),
        g("Bionic Commando", "ヒットラーの復活 トップシークレット", .nes, 1988, "アクション"),
        g("DuckTales", "わんぱくダック夢冒険", .nes, 1989, "アクション"),
        g("Chip 'n Dale - Rescue Rangers", "チップとデールの大作戦", .nes, 1990, "アクション"),
        g("Teenage Mutant Ninja Turtles", "ティーンエイジ・ミュータント・ニンジャ・タートルズ", .nes, 1989, "アクション"),
        g("Batman - The Video Game", "バットマン", .nes, 1989, "アクション"),
        g("Pac-Man", "パックマン", .nes, 1984, "アクション"),
        g("Galaga", "ギャラガ", .nes, 1985, "シューティング"),
        g("Xevious", "ゼビウス", .nes, 1984, "シューティング"),
        g("Star Soldier", "スターソルジャー", .nes, 1986, "シューティング"),
        g("TwinBee", "ツインビー", .nes, 1986, "シューティング"),
        g("Kung Fu", "スパルタンX", .nes, 1985, "アクション"),
        g("Lode Runner", "ロードランナー", .nes, 1984, "パズル"),
        g("Solomon's Key", "ソロモンの鍵", .nes, 1986, "パズル"),
    ]

    // MARK: - SNES

    static let snesGames: [GameTitle] = [
        g("Super Mario World", "スーパーマリオワールド", .snes, 1990, "アクション"),
        g("Super Mario World 2 - Yoshi's Island", "スーパーマリオ ヨッシーアイランド", .snes, 1995, "アクション"),
        g("Super Mario All-Stars", "スーパーマリオコレクション", .snes, 1993, "アクション"),
        g("Super Mario Kart", "スーパーマリオカート", .snes, 1992, "レース"),
        g("Super Mario RPG - Legend of the Seven Stars", "スーパーマリオRPG", .snes, 1996, "RPG"),
        g("The Legend of Zelda - A Link to the Past", "ゼルダの伝説 神々のトライフォース", .snes, 1991, "アクションRPG"),
        g("Super Metroid", "スーパーメトロイド", .snes, 1994, "アクション"),
        g("Donkey Kong Country", "スーパードンキーコング", .snes, 1994, "アクション"),
        g("Donkey Kong Country 2 - Diddy's Kong Quest", "スーパードンキーコング2", .snes, 1995, "アクション"),
        g("Donkey Kong Country 3 - Dixie Kong's Double Trouble!", "スーパードンキーコング3", .snes, 1996, "アクション"),
        g("Star Fox", "スターフォックス", .snes, 1993, "シューティング"),
        g("F-Zero", "F-ZERO", .snes, 1990, "レース"),
        g("Kirby Super Star", "星のカービィ スーパーデラックス", .snes, 1996, "アクション"),
        g("Kirby's Dream Land 3", "星のカービィ3", .snes, 1997, "アクション"),
        g("EarthBound", "MOTHER2 ギーグの逆襲", .snes, 1994, "RPG"),
        g("Final Fantasy IV", "ファイナルファンタジーIV", .snes, 1991, "RPG"),
        g("Final Fantasy V", "ファイナルファンタジーV", .snes, 1992, "RPG"),
        g("Final Fantasy VI", "ファイナルファンタジーVI", .snes, 1994, "RPG"),
        g("Chrono Trigger", "クロノ・トリガー", .snes, 1995, "RPG"),
        g("Secret of Mana", "聖剣伝説2", .snes, 1993, "アクションRPG"),
        g("Seiken Densetsu 3", "聖剣伝説3", .snes, 1995, "アクションRPG"),
        g("Dragon Quest V", "ドラゴンクエストV", .snes, 1992, "RPG"),
        g("Dragon Quest VI", "ドラゴンクエストVI", .snes, 1995, "RPG"),
        g("Dragon Quest III (SNES)", "ドラゴンクエストIII (SFC)", .snes, 1996, "RPG"),
        g("Romancing SaGa", "ロマンシング サ・ガ", .snes, 1992, "RPG"),
        g("Romancing SaGa 2", "ロマンシング サ・ガ2", .snes, 1993, "RPG"),
        g("Romancing SaGa 3", "ロマンシング サ・ガ3", .snes, 1995, "RPG"),
        g("Breath of Fire", "ブレス オブ ファイア", .snes, 1993, "RPG"),
        g("Breath of Fire II", "ブレス オブ ファイアII", .snes, 1994, "RPG"),
        g("Super Castlevania IV", "悪魔城ドラキュラ", .snes, 1991, "アクション"),
        g("Castlevania - Dracula X", "悪魔城ドラキュラXX", .snes, 1995, "アクション"),
        g("Mega Man X", "ロックマンX", .snes, 1993, "アクション"),
        g("Mega Man X2", "ロックマンX2", .snes, 1994, "アクション"),
        g("Mega Man X3", "ロックマンX3", .snes, 1995, "アクション"),
        g("Contra III - The Alien Wars", "魂斗羅スピリッツ", .snes, 1992, "アクション"),
        g("Street Fighter II Turbo - Hyper Fighting", "ストリートファイターIIターボ", .snes, 1993, "格闘"),
        g("Super Street Fighter II - The New Challengers", "スーパーストリートファイターII", .snes, 1994, "格闘"),
        g("Mortal Kombat II", "モータルコンバットII", .snes, 1994, "格闘"),
        g("Killer Instinct", "キラーインスティンクト", .snes, 1995, "格闘"),
        g("Teenage Mutant Ninja Turtles IV - Turtles in Time", "タートルズ・イン・タイム", .snes, 1992, "アクション"),
        g("ActRaiser", "アクトレイザー", .snes, 1990, "アクション"),
        g("Super Ghouls'n Ghosts", "超魔界村", .snes, 1991, "アクション"),
        g("Gradius III", "グラディウスIII", .snes, 1990, "シューティング"),
        g("R-Type III - The Third Lightning", "R-TYPE III", .snes, 1993, "シューティング"),
        g("Axelay", "アクスレイ", .snes, 1992, "シューティング"),
        g("Pilotwings", "パイロットウイングス", .snes, 1990, "フライト"),
        g("SimCity", "シムシティ", .snes, 1991, "シミュレーション"),
        g("Harvest Moon", "牧場物語", .snes, 1996, "シミュレーション"),
        g("Fire Emblem - Mystery of the Emblem", "ファイアーエムブレム 紋章の謎", .snes, 1994, "シミュレーションRPG"),
        g("Fire Emblem - Genealogy of the Holy War", "ファイアーエムブレム 聖戦の系譜", .snes, 1996, "シミュレーションRPG"),
        g("Tactics Ogre - Let Us Cling Together", "タクティクスオウガ", .snes, 1995, "シミュレーションRPG"),
        g("Front Mission", "フロントミッション", .snes, 1995, "シミュレーションRPG"),
        g("Ogre Battle - The March of the Black Queen", "伝説のオウガバトル", .snes, 1993, "シミュレーションRPG"),
        g("Super Bomberman", "スーパーボンバーマン", .snes, 1993, "アクション"),
        g("Super Bomberman 2", "スーパーボンバーマン2", .snes, 1994, "アクション"),
        g("Tetris Attack", "パネルでポン", .snes, 1995, "パズル"),
        g("Super Puyo Puyo", "す〜ぱ〜ぷよぷよ", .snes, 1993, "パズル"),
        g("Lufia II - Rise of the Sinistrals", "エストポリス伝記II", .snes, 1995, "RPG"),
        g("Terranigma", "天地創造", .snes, 1995, "アクションRPG"),
        g("Illusion of Gaia", "ガイア幻想紀", .snes, 1993, "アクションRPG"),
        g("Soul Blazer", "ソウルブレイダー", .snes, 1992, "アクションRPG"),
        g("Star Ocean", "スターオーシャン", .snes, 1996, "RPG"),
        g("Tales of Phantasia", "テイルズ オブ ファンタジア", .snes, 1995, "RPG"),
        g("Bahamut Lagoon", "バハムートラグーン", .snes, 1996, "シミュレーションRPG"),
        g("Live A Live", "ライブ・ア・ライブ", .snes, 1994, "RPG"),
        g("Treasure Hunter G", "トレジャーハンターG", .snes, 1996, "RPG"),
        g("Gundam Wing - Endless Duel", "新機動戦記ガンダムW エンドレスデュエル", .snes, 1996, "格闘"),
        g("Dragon Ball Z - Hyper Dimension", "ドラゴンボールZ ハイパーディメンション", .snes, 1996, "格闘"),
        g("Yoshi's Cookie", "ヨッシーのクッキー", .snes, 1992, "パズル"),
        g("Super Tennis", "スーパーテニス", .snes, 1991, "スポーツ"),
        g("International Superstar Soccer Deluxe", "実況ワールドサッカー", .snes, 1995, "スポーツ"),
    ]

    private static func g(_ name: String, _ jpName: String, _ sys: GameSystem, _ year: Int, _ genre: String) -> GameTitle {
        GameTitle(id: "\(sys.rawValue)_\(name)", name: name, japanName: jpName, system: sys, year: year, genre: genre)
    }
}
