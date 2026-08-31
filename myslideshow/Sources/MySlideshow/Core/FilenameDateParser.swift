import Foundation

/// ファイル名から撮影日らしき`YYYYMMDD`パターンを拾う。OneDriveの`lastModifiedDateTime`
/// (`MediaItem.modifiedDate`)はアップロード/同期日時であって撮影日ではないことが多いため、
/// `IMG_20230515_120033.jpg`/`VID-20230515-WA0001.mp4`/`2023-05-15 12.00.33.jpg`のような
/// カメラ・スマホの標準的な命名規則から、ファイル名だけで日付を推測する
/// (「ファイル名からいつからわかるはず」というユーザー要望への対応)。
enum FilenameDateParser {
    // 年(1900〜2099)+月(01〜12)+日(01〜31)を、区切り文字(-_.)有り無しどちらでも拾う。
    // 前後が数字だと8桁の時刻(120033)等を巻き込みかねないため、年の前・日の後は
    // 数字が続かないことを確認する(lookaround)。
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![0-9])(19[0-9]{2}|20[0-9]{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12][0-9]|3[01])(?![0-9])"#
    )

    static func date(from fileName: String) -> Date? {
        let range = NSRange(fileName.startIndex..., in: fileName)
        guard let match = regex.firstMatch(in: fileName, range: range),
            let yearRange = Range(match.range(at: 1), in: fileName),
            let monthRange = Range(match.range(at: 2), in: fileName),
            let dayRange = Range(match.range(at: 3), in: fileName),
            let year = Int(fileName[yearRange]),
            let month = Int(fileName[monthRange]),
            let day = Int(fileName[dayRange])
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar(identifier: .gregorian).date(from: components)
    }
}
