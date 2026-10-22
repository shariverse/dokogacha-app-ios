//
//  CandidateRules.swift
//  Dokogacha
//
//  候補の判定（02 の F-10 の重複・05 の §3 の `colorIndex`・投稿の入力の検証）。
//  TypeScript 側の `backend/functions/src/domain/candidate.ts`・`candidates/input.ts` と同じ規則で、
//  `candidate.test.ts`・`input.test.ts` と同じケースを `CandidateRulesTests` で確かめる。片方を変えたら両方を変える。
//

import Foundation

/// 候補の重複・採番・入力の判定。
///
/// サーバー（`addCandidate`）が同じ規則で確かめるので、擬似のサーバーと投稿の画面（S-08 の「追加済み」・S-09 の入力）が使う。
nonisolated enum CandidateRules {
    /// 地球の半径（メートル。距離の計算に使う平均半径。backend の `EARTH_RADIUS_METERS`）。
    ///
    /// 100m の判定には、楕円体と球の差（0.5% 未満）は効かないので球で計算する
    static let earthRadiusMeters: Double = 6_371_000

    /// 候補を投稿・削除できるルームの状態（02 の §2.1・F-10「投稿できるのは open/unlocked のときだけ」。
    /// backend の `CANDIDATE_EDITABLE_STATUSES`）。
    ///
    /// いいね・準備OKを変えられる状態（`RoomCandidateRow.likeableStatuses`・`InMemoryServer.interactiveStatuses`）と今は同じ値だが、
    /// 決まりが別なので分けて持つ
    static let editableStatuses: Set<RoomStatus> = [.open, .unlocked]

    /// 参考 URL の先頭に許すスキーム（小文字で比べる）
    private static let urlSchemes = ["http://", "https://"]

    // MARK: 重複（F-10）

    /// 2 点の間の距離（メートル）を、球面の大円距離（ハーバーサインの式）で求める（backend の `distanceMeters`）
    static func distanceMeters(_ lhs: Place, _ rhs: Place) -> Double {
        func radians(_ degrees: Double) -> Double {
            degrees * .pi / 180
        }
        let deltaLatitude = radians(rhs.latitude - lhs.latitude)
        let deltaLongitude = radians(rhs.longitude - lhs.longitude)
        let haversine = pow(sin(deltaLatitude / 2), 2)
            + cos(radians(lhs.latitude)) * cos(radians(rhs.latitude)) * pow(sin(deltaLongitude / 2), 2)
        return 2 * earthRadiusMeters * asin(min(1, haversine.squareRoot()))
    }

    /// 重複とみなす距離の内か（02 の F-10「100m以内」。100m ちょうどは「以内」に入る。backend の `isWithinDuplicateDistance`）。
    ///
    /// 境目をテストで決めるため、距離の計算から分けている
    static func isWithinDuplicateDistance(_ meters: Double) -> Bool {
        meters <= DomainConstants.Limits.duplicateDistanceMeters
    }

    /// 同じ場所か（02 の F-10「MapKit の識別子が同じ、または場所名が同じで座標が100m以内」。backend の `isSamePlace`）。
    ///
    /// - 識別子はどちらにもあって等しいときだけ「同じ」とみなす（片方に無ければ、名前と距離で判定する）
    /// - 場所名は前後の空白を取り除いた文字列どうしの完全一致（UTF-16 の並びで比べる。Swift の `==` は正準等価で比べるので使わない）
    /// - 100m ちょうどは「以内」に入る
    static func isSamePlace(_ lhs: Place, _ rhs: Place) -> Bool {
        if let lhsID = lhs.mapItemId, let rhsID = rhs.mapItemId, lhsID.utf16.elementsEqual(rhsID.utf16) {
            return true
        }
        return lhs.name.utf16.elementsEqual(rhs.name.utf16)
            && isWithinDuplicateDistance(distanceMeters(lhs, rhs))
    }

    /// 同じ場所の既存の候補を探す（自分の投稿も対象。backend の `findDuplicateCandidate`）。
    ///
    /// 同じ場所が複数あるときは、いちばん古い投稿（同じ日時なら ID の順で先のもの）を返す
    /// - Returns: 重複した候補の ID（無ければ nil）
    static func duplicate(of place: Place, in candidates: [Identified<Candidate>]) -> String? {
        candidates
            .filter { isSamePlace(place, $0.place) }
            .min { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }?
            .id
    }

    // MARK: 採番

    /// 新しい候補の `colorIndex`（05 の §3「投稿順の通し番号」。backend の `nextColorIndex`）。
    ///
    /// 既存の候補の最大の番号 + 1（候補が無ければ 0）。候補を消しても残りの番号は詰めない（カプセルの色が変わらないように）
    static func nextColorIndex(_ existing: [Int]) -> Int {
        existing.reduce(0) { max($0, $1 + 1) }
    }

    // MARK: 入力の検証（backend の `candidates/input.ts`）

    /// 参考 URL の入力を確かめた結果
    enum URLInput: Equatable {
        /// 入力が無い・空白だけ（保存しない）
        case none
        /// 受け付ける URL（前後の空白を取り除いたもの）
        case valid(String)
        /// 受け付けない
        case invalid
    }

    /// 参考 URL として受け付ける形か（前後の空白を取り除いた後の文字列に使う。backend の `isAcceptableCandidateUrl`）。
    ///
    /// - `http://` か `https://` で始まる（大文字・小文字を区別しない）。その後に 1 文字以上ある
    /// - 途中に空白（`NameValidation.whitespaces`）・制御文字・行と段落の区切りを含まない
    ///
    /// `URL(string:)` は TypeScript の `URL` と受け付ける範囲が違うので使わない。
    /// 先頭はスカラー値の単位で比べる（`hasPrefix` は書記素の単位なので、`https://` の直後に結合文字があると一致しない）
    static func isAcceptableURL(_ trimmed: String) -> Bool {
        let scalars = Array(trimmed.unicodeScalars)
        let hasScheme = urlSchemes.contains { scheme in
            let prefix = Array(scheme.unicodeScalars)
            return scalars.count > prefix.count
                && zip(scalars, prefix).allSatisfy { Character($0).lowercased() == String($1) }
        }
        guard hasScheme, !NameValidation.containsForbiddenCharacter(trimmed) else {
            return false
        }
        return !scalars.contains { NameValidation.whitespaces.contains($0) }
    }

    /// 参考 URL（任意）を確かめる。無い・空白だけなら `.none`。2048 文字（UTF-16）以下の `http`・`https` の URL だけを受け付ける
    static func validatedURL(_ text: String?) -> URLInput {
        guard let text else {
            return .none
        }
        guard text.utf16.count <= DomainConstants.Limits.candidateURLMaxLength + NameValidation.maxSurroundingWhitespaceUTF16Units else {
            return .invalid
        }
        let trimmed = NameValidation.trimWhitespace(text)
        if trimmed.isEmpty {
            return .none
        }
        guard trimmed.utf16.count <= DomainConstants.Limits.candidateURLMaxLength, isAcceptableURL(trimmed) else {
            return .invalid
        }
        return .valid(trimmed)
    }

    /// 任意の文字列（0 文字から。エリア・ひとこと）を名前と同じ規則で確かめる。見えない文字と空白だけなら空の文字列にする。
    ///
    /// 受け付けなければ nil（サーバーなら `invalid-argument`）
    static func validatedOptionalText(_ text: String, length: ClosedRange<Int>) -> String? {
        guard let trimmed = NameValidation.validated(text, length: length) else {
            return nil
        }
        return NameValidation.isInvisibleOnly(trimmed) ? "" : trimmed
    }

    /// ひとこと（0〜40 文字）を確かめる。受け付けなければ nil
    static func validatedNote(_ note: String) -> String? {
        validatedOptionalText(note, length: DomainConstants.Limits.noteLength)
    }

    /// 場所を確かめる（名前 1〜100 文字・エリア 0〜50 文字・緯度 -90〜90・経度 -180〜180・識別子）。
    ///
    /// 名前とエリアは前後の空白を取り除いた値にして返す。受け付けなければ nil
    static func validatedPlace(_ place: Place) -> Place? {
        guard let name = NameValidation.validated(place.name, length: DomainConstants.Limits.placeNameLength),
              let area = validatedOptionalText(place.area, length: DomainConstants.Limits.placeAreaLength),
              place.latitude.isFinite, (-90...90).contains(place.latitude),
              place.longitude.isFinite, (-180...180).contains(place.longitude),
              place.mapItemId.map(isAcceptableMapItemID) ?? true else {
            return nil
        }
        return Place(name: name, area: area, latitude: place.latitude, longitude: place.longitude, mapItemId: place.mapItemId)
    }

    /// MapKit の識別子として受け付けるか（空でない・256 単位以下・前後に空白が無い・制御文字などを含まない）。
    ///
    /// 比べるのは完全一致なので、取り除かずに断る
    static func isAcceptableMapItemID(_ id: String) -> Bool {
        !id.isEmpty
            && id.utf16.count <= DomainConstants.Limits.mapItemIDMaxLength
            && NameValidation.trimWhitespace(id).utf16.elementsEqual(id.utf16)
            && !NameValidation.containsForbiddenCharacter(id)
    }
}
