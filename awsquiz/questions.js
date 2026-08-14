/* AWS Certified Solutions Architect – Professional (SAP-C02) 対策データ
 *
 * 各問題: { id, dom, cat, q, choices, answer, note, fig? }
 *   dom    … SAP_DOMAINS の id (1〜4)
 *   cat    … SAP_CATEGORY_EMOJI のキー
 *   answer … 単一選択は数値、複数選択は数値の配列（配列の長さが「N つ選択」になる）
 *   fig    … SAP_FIGURES のキー（任意）。回答後の解説とフラッシュカードの裏面にだけ出る
 * id は進捗の保存キーなので、いちど公開した問題の id は変えないこと。
 */

window.SAP_DOMAINS = [
  { id: 1, emoji: "🏢", short: "組織の複雑さ", name: "組織の複雑さに対応する設計", pct: 26 },
  { id: 2, emoji: "🧭", short: "新規設計",     name: "新しいソリューションのための設計", pct: 29 },
  { id: 3, emoji: "🔧", short: "継続的改善",   name: "既存ソリューションの継続的な改善", pct: 25 },
  { id: 4, emoji: "🚚", short: "移行と近代化", name: "ワークロードの移行とモダナイゼーション", pct: 20 }
];

window.SAP_CATEGORY_EMOJI = {
  "アカウント/組織管理": "🏛️",
  "IAM/認証・認可": "🔑",
  "ネットワーク": "🌐",
  "ハイブリッド接続": "🔗",
  "コンピュート": "🖥️",
  "ストレージ": "🗄️",
  "データベース": "🗃️",
  "可用性/DR": "🛡️",
  "セキュリティ/コンプライアンス": "🔒",
  "コスト最適化": "💰",
  "監視/運用自動化": "📈",
  "移行": "🚚",
  "モダナイゼーション": "🧩",
  "データ分析": "📊",
  // 公式試験ガイドの「Emerging Topics（Design security and responsible AI controls）」に対応。
  // 現時点では採点対象外の pretest 問題として出題されうる、と AWS が明記している領域。
  "生成AI(新領域)": "🤖"
};

window.SAP_FIGURES = {
  scp:
    '<svg viewBox="0 0 420 220" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<rect x="120" y="8" width="180" height="34" rx="8" fill="#16283a" stroke="#ff9900"/>' +
    '<text x="210" y="30" fill="#eef4fa" font-size="13" text-anchor="middle">Root（SCP: FullAWSAccess）</text>' +
    '<line x1="210" y1="42" x2="110" y2="70" stroke="#93a7bd"/><line x1="210" y1="42" x2="310" y2="70" stroke="#93a7bd"/>' +
    '<rect x="20" y="70" width="180" height="34" rx="8" fill="#16283a" stroke="#4dabf7"/>' +
    '<text x="110" y="92" fill="#eef4fa" font-size="12" text-anchor="middle">OU: 本番（Deny 非承認リージョン）</text>' +
    '<rect x="220" y="70" width="180" height="34" rx="8" fill="#16283a" stroke="#4dabf7"/>' +
    '<text x="310" y="92" fill="#eef4fa" font-size="12" text-anchor="middle">OU: 開発（Deny 高額インスタンス）</text>' +
    '<line x1="110" y1="104" x2="110" y2="132" stroke="#93a7bd"/><line x1="310" y1="104" x2="310" y2="132" stroke="#93a7bd"/>' +
    '<rect x="30" y="132" width="160" height="32" rx="8" fill="#122032" stroke="#93a7bd"/>' +
    '<text x="110" y="153" fill="#93a7bd" font-size="12" text-anchor="middle">アカウント</text>' +
    '<rect x="230" y="132" width="160" height="32" rx="8" fill="#122032" stroke="#93a7bd"/>' +
    '<text x="310" y="153" fill="#93a7bd" font-size="12" text-anchor="middle">アカウント</text>' +
    '<text x="210" y="192" fill="#2ed573" font-size="12" text-anchor="middle">実効権限 = Root〜アカウントの全 SCP の積集合</text>' +
    '<text x="210" y="210" fill="#ff4757" font-size="11" text-anchor="middle">SCP は上限を決めるだけ。権限そのものは IAM で付与する</text></svg>',

  dr:
    '<svg viewBox="0 0 430 210" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<text x="10" y="16" fill="#93a7bd" font-size="11">← 安い / RTO・RPO 長い　　　　　高い / RTO・RPO 短い →</text>' +
    '<rect x="10" y="28" width="96" height="60" rx="8" fill="#16283a" stroke="#93a7bd"/>' +
    '<text x="58" y="50" fill="#eef4fa" font-size="12" text-anchor="middle">バックアップ</text>' +
    '<text x="58" y="66" fill="#eef4fa" font-size="12" text-anchor="middle">＆リストア</text>' +
    '<text x="58" y="82" fill="#93a7bd" font-size="10" text-anchor="middle">数時間</text>' +
    '<rect x="116" y="28" width="96" height="60" rx="8" fill="#16283a" stroke="#4dabf7"/>' +
    '<text x="164" y="55" fill="#eef4fa" font-size="12" text-anchor="middle">パイロットライト</text>' +
    '<text x="164" y="75" fill="#93a7bd" font-size="10" text-anchor="middle">数十分（DBのみ稼働）</text>' +
    '<rect x="222" y="28" width="96" height="60" rx="8" fill="#16283a" stroke="#ffc048"/>' +
    '<text x="270" y="55" fill="#eef4fa" font-size="12" text-anchor="middle">ウォーム</text>' +
    '<text x="270" y="70" fill="#eef4fa" font-size="12" text-anchor="middle">スタンバイ</text>' +
    '<text x="270" y="84" fill="#93a7bd" font-size="10" text-anchor="middle">数分（縮小構成が稼働）</text>' +
    '<rect x="328" y="28" width="96" height="60" rx="8" fill="#16283a" stroke="#2ed573"/>' +
    '<text x="376" y="55" fill="#eef4fa" font-size="12" text-anchor="middle">マルチサイト</text>' +
    '<text x="376" y="70" fill="#eef4fa" font-size="12" text-anchor="middle">アクティブ</text>' +
    '<text x="376" y="84" fill="#93a7bd" font-size="10" text-anchor="middle">ほぼゼロ</text>' +
    '<text x="10" y="120" fill="#ff9900" font-size="12">RTO = 復旧までに許される時間</text>' +
    '<text x="10" y="140" fill="#ff9900" font-size="12">RPO = 失ってよいデータの時間ぶん</text>' +
    '<text x="10" y="168" fill="#93a7bd" font-size="11">パイロットライト: データ複製は常時、アプリは停止（起動して復旧）</text>' +
    '<text x="10" y="186" fill="#93a7bd" font-size="11">ウォームスタンバイ: 縮小版が常時稼働（スケールアップして復旧）</text></svg>',

  tgw:
    '<svg viewBox="0 0 420 200" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<text x="105" y="16" fill="#ff4757" font-size="12" text-anchor="middle">VPC ピアリング（フルメッシュ）</text>' +
    '<circle cx="45" cy="55" r="16" fill="#16283a" stroke="#93a7bd"/><circle cx="165" cy="55" r="16" fill="#16283a" stroke="#93a7bd"/>' +
    '<circle cx="45" cy="130" r="16" fill="#16283a" stroke="#93a7bd"/><circle cx="165" cy="130" r="16" fill="#16283a" stroke="#93a7bd"/>' +
    '<line x1="45" y1="55" x2="165" y2="55" stroke="#ff4757"/><line x1="45" y1="130" x2="165" y2="130" stroke="#ff4757"/>' +
    '<line x1="45" y1="55" x2="45" y2="130" stroke="#ff4757"/><line x1="165" y1="55" x2="165" y2="130" stroke="#ff4757"/>' +
    '<line x1="45" y1="55" x2="165" y2="130" stroke="#ff4757"/><line x1="165" y1="55" x2="45" y2="130" stroke="#ff4757"/>' +
    '<text x="105" y="170" fill="#93a7bd" font-size="11" text-anchor="middle">n(n-1)/2 本・推移的ルーティング不可</text>' +
    '<line x1="210" y1="30" x2="210" y2="180" stroke="#93a7bd" stroke-dasharray="4 4"/>' +
    '<text x="320" y="16" fill="#2ed573" font-size="12" text-anchor="middle">Transit Gateway（ハブ＆スポーク）</text>' +
    '<rect x="292" y="80" width="56" height="26" rx="6" fill="#16283a" stroke="#ff9900"/>' +
    '<text x="320" y="98" fill="#ff9900" font-size="11" text-anchor="middle">TGW</text>' +
    '<circle cx="260" cy="45" r="15" fill="#16283a" stroke="#93a7bd"/><circle cx="380" cy="45" r="15" fill="#16283a" stroke="#93a7bd"/>' +
    '<circle cx="260" cy="145" r="15" fill="#16283a" stroke="#93a7bd"/><circle cx="380" cy="145" r="15" fill="#16283a" stroke="#93a7bd"/>' +
    '<line x1="260" y1="60" x2="300" y2="80" stroke="#2ed573"/><line x1="380" y1="60" x2="340" y2="80" stroke="#2ed573"/>' +
    '<line x1="260" y1="130" x2="300" y2="106" stroke="#2ed573"/><line x1="380" y1="130" x2="340" y2="106" stroke="#2ed573"/>' +
    '<text x="320" y="180" fill="#93a7bd" font-size="11" text-anchor="middle">n 本・RAM で他アカウントに共有可</text></svg>',

  hybriddns:
    '<svg viewBox="0 0 420 190" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<rect x="12" y="55" width="120" height="80" rx="10" fill="#122032" stroke="#93a7bd"/>' +
    '<text x="72" y="80" fill="#eef4fa" font-size="12" text-anchor="middle">オンプレミス</text>' +
    '<text x="72" y="100" fill="#93a7bd" font-size="11" text-anchor="middle">DNS サーバー</text>' +
    '<text x="72" y="118" fill="#93a7bd" font-size="11" text-anchor="middle">corp.example.com</text>' +
    '<rect x="240" y="30" width="170" height="130" rx="10" fill="#16283a" stroke="#ff9900"/>' +
    '<text x="325" y="52" fill="#ff9900" font-size="12" text-anchor="middle">VPC / Route 53 Resolver</text>' +
    '<rect x="256" y="64" width="138" height="30" rx="6" fill="#122032" stroke="#2ed573"/>' +
    '<text x="325" y="83" fill="#2ed573" font-size="11" text-anchor="middle">インバウンドEP</text>' +
    '<rect x="256" y="104" width="138" height="30" rx="6" fill="#122032" stroke="#4dabf7"/>' +
    '<text x="325" y="123" fill="#4dabf7" font-size="11" text-anchor="middle">アウトバウンドEP＋転送ルール</text>' +
    '<line x1="132" y1="80" x2="256" y2="80" stroke="#2ed573" marker-end="url(#a)"/>' +
    '<line x1="256" y1="119" x2="132" y2="119" stroke="#4dabf7" marker-end="url(#a)"/>' +
    '<defs><marker id="a" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">' +
    '<path d="M0,0 L8,4 L0,8 z" fill="#93a7bd"/></marker></defs>' +
    '<text x="10" y="180" fill="#93a7bd" font-size="11">インバウンド＝オンプレ→AWS の名前解決 / アウトバウンド＝AWS→オンプレ</text></svg>',

  s3class:
    '<svg viewBox="0 0 420 200" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<text x="10" y="18" fill="#ff9900" font-size="12">アクセス頻度 高 → 低（保管料は下がり、取り出し料と時間は増える）</text>' +
    '<rect x="10" y="30" width="400" height="26" rx="6" fill="#16283a" stroke="#2ed573"/>' +
    '<text x="18" y="48" fill="#eef4fa" font-size="12">S3 Standard — 即時・取り出し無料・最低保存期間なし</text>' +
    '<rect x="10" y="62" width="360" height="26" rx="6" fill="#16283a" stroke="#4dabf7"/>' +
    '<text x="18" y="80" fill="#eef4fa" font-size="12">Standard-IA / One Zone-IA — 最低30日・取り出し課金</text>' +
    '<rect x="10" y="94" width="320" height="26" rx="6" fill="#16283a" stroke="#ffc048"/>' +
    '<text x="18" y="112" fill="#eef4fa" font-size="12">Glacier Instant Retrieval — ミリ秒・最低90日</text>' +
    '<rect x="10" y="126" width="280" height="26" rx="6" fill="#16283a" stroke="#ff9900"/>' +
    '<text x="18" y="144" fill="#eef4fa" font-size="12">Glacier Flexible — 数分〜12時間・最低90日</text>' +
    '<rect x="10" y="158" width="240" height="26" rx="6" fill="#16283a" stroke="#ff4757"/>' +
    '<text x="18" y="176" fill="#eef4fa" font-size="12">Glacier Deep Archive — 12〜48時間・最低180日</text></svg>',

  assumerole:
    '<svg viewBox="0 0 420 180" xmlns="http://www.w3.org/2000/svg" font-family="sans-serif">' +
    '<rect x="10" y="40" width="150" height="100" rx="10" fill="#16283a" stroke="#4dabf7"/>' +
    '<text x="85" y="62" fill="#4dabf7" font-size="12" text-anchor="middle">アカウント A（利用側）</text>' +
    '<text x="85" y="88" fill="#eef4fa" font-size="11" text-anchor="middle">IAM ユーザー / ロール</text>' +
    '<text x="85" y="110" fill="#93a7bd" font-size="10" text-anchor="middle">許可: sts:AssumeRole</text>' +
    '<rect x="260" y="40" width="150" height="100" rx="10" fill="#16283a" stroke="#ff9900"/>' +
    '<text x="335" y="62" fill="#ff9900" font-size="12" text-anchor="middle">アカウント B（提供側）</text>' +
    '<text x="335" y="88" fill="#eef4fa" font-size="11" text-anchor="middle">IAM ロール</text>' +
    '<text x="335" y="110" fill="#93a7bd" font-size="10" text-anchor="middle">信頼ポリシーで A を許可</text>' +
    '<line x1="162" y1="80" x2="258" y2="80" stroke="#2ed573" marker-end="url(#b)"/>' +
    '<text x="210" y="74" fill="#2ed573" font-size="10" text-anchor="middle">AssumeRole</text>' +
    '<line x1="258" y1="112" x2="162" y2="112" stroke="#93a7bd" marker-end="url(#b)"/>' +
    '<text x="210" y="128" fill="#93a7bd" font-size="10" text-anchor="middle">一時認証情報</text>' +
    '<defs><marker id="b" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">' +
    '<path d="M0,0 L8,4 L0,8 z" fill="#93a7bd"/></marker></defs>' +
    '<text x="210" y="168" fill="#ff4757" font-size="11" text-anchor="middle">両側（許可ポリシー＋信頼ポリシー）の許可が必要</text></svg>'
};

window.SAP_QUESTIONS = [

/* =======================================================================
 * ドメイン1: 組織の複雑さに対応する設計（26%）
 * ===================================================================== */

{ id:"d1-01", dom:1, cat:"アカウント/組織管理",
  q:"AWS Organizations のサービスコントロールポリシー（SCP）について正しい説明は?",
  choices:[
    "アカウントで使える権限の上限を決めるだけで、権限そのものは付与しない",
    "SCP でアクションを Allow すれば、IAM ポリシーが無くてもそのアクションを実行できる",
    "管理アカウント（マネジメントアカウント）にも他のメンバーと同様に適用される",
    "IAM ロールには適用されず、IAM ユーザーにのみ適用される"],
  answer:0, fig:"scp",
  note:"SCP は「ガードレール」であり、実際の許可は IAM のアイデンティティベース/リソースベースのポリシーで与える。実効権限は SCP と IAM の積集合。\n管理アカウントは SCP の対象外なので、本番ワークロードを管理アカウントに置かないのがベストプラクティス。" },

{ id:"d1-02", dom:1, cat:"アカウント/組織管理",
  q:"Root に「FullAWSAccess」、親 OU に「us-east-1 と ap-northeast-1 以外を Deny」、子 OU に「S3 の Allow のみ」の SCP が付いています。子 OU のアカウントで実行できるのは?",
  choices:[
    "ap-northeast-1 での S3 操作（IAM で許可されていれば）",
    "全リージョンでの S3 操作",
    "ap-northeast-1 での全 AWS サービスの操作",
    "何も実行できない（SCP が競合するため）"],
  answer:0, fig:"scp",
  note:"SCP は階層のすべてのレベルで評価され、実効権限は積集合になる。1つでも許可されていなければ拒否。\n子 OU が S3 だけを Allow している時点で、その配下では S3 以外は使えない。さらにリージョン制限も重なる。" },

{ id:"d1-03", dom:1, cat:"アカウント/組織管理",
  q:"金融系の企業が、数十の事業部それぞれに AWS アカウントを払い出す予定です。監査ログの集約、ネットワークの標準化、必須ガードレールの適用を、最小限の自社開発で実現したい。最も適切なのは?",
  choices:[
    "AWS Control Tower でランディングゾーンを構築し、Account Factory でアカウントを払い出す",
    "各事業部が個別に AWS アカウントを新規契約し、後から Organizations に招待する",
    "1つのアカウント内に事業部ごとの VPC を作り、IAM ポリシーで分離する",
    "CloudFormation テンプレートを配布し、各事業部に手動で適用してもらう"],
  answer:0,
  note:"Control Tower は Organizations・IAM Identity Center・CloudTrail 組織証跡・Config・ログアーカイブ/監査アカウントをまとめて構成する「ランディングゾーン」を自動作成する。\nAccount Factory（Service Catalog ベース）で標準構成のアカウントを払い出せる。コントロール（旧ガードレール）は予防的＝SCP、検出的＝Config ルールとして実装される。" },

{ id:"d1-04", dom:1, cat:"アカウント/組織管理",
  q:"Control Tower の「予防的コントロール」と「検出的コントロール」は、それぞれ何で実装されていますか?",
  choices:[
    "予防的＝SCP、検出的＝AWS Config ルール",
    "予防的＝AWS Config ルール、検出的＝SCP",
    "どちらも IAM 権限境界",
    "どちらも AWS WAF ルール"],
  answer:0,
  note:"予防的コントロールは違反する API 呼び出しそのものを SCP でブロックする。検出的コントロールは Config ルールで違反状態を「検知」して報告する（止めはしない）。\nプロアクティブコントロールという3つ目の種類もあり、こちらは CloudFormation Hooks でデプロイ前に検査する。" },

{ id:"d1-05", dom:1, cat:"コスト最適化",
  q:"Organizations の一括請求（Consolidated Billing）について正しいものを2つ選んでください。",
  choices:[
    "組織全体の使用量が合算されるため、S3 などのボリューム割引が効きやすくなる",
    "購入したリザーブドインスタンスや Savings Plans の割引が組織内の他アカウントにも適用されうる",
    "メンバーアカウントごとに個別の請求書が発行され、支払いも個別になる",
    "割引の共有はいちど有効にすると無効化できない"],
  answer:[0,1],
  note:"一括請求では使用量が合算されるので階層型の従量割引に到達しやすい。RI/Savings Plans の割引も既定では組織内で共有される。\n請求は管理アカウントに一本化される。割引共有は管理アカウントの請求設定でアカウント単位にオン/オフでき、後から変更できる。" },

{ id:"d1-06", dom:1, cat:"コスト最適化",
  q:"事業部ごとに複数アカウントが混在する組織で、「事業部A」「事業部B」といった単位でコストを追跡・予算アラートしたい。最も適した機能は?",
  choices:[
    "AWS Cost Categories でアカウントやタグをルールでグループ化し、そのカテゴリに Budgets を設定する",
    "各アカウントで Cost Explorer を個別に開いて手作業で合算する",
    "アカウントごとに別々の AWS 契約に分ける",
    "CloudWatch のカスタムメトリクスに毎日コストを書き込む"],
  answer:0,
  note:"Cost Categories はアカウント・タグ・請求サービスなどの条件でコストを任意のディメンションにまとめ直す機能。Cost Explorer / Budgets / CUR から共通して使える。\nタグだけでは付け忘れやアカウントをまたぐ集計に弱いため、多アカウント環境では Cost Categories が定石。" },

{ id:"d1-07", dom:1, cat:"IAM/認証・認可",
  q:"サードパーティの SaaS ベンダーに、自社アカウントのリソースへの読み取りアクセスを許可します。IAM ロールの信頼ポリシーに「外部 ID（External ID）」を設定する目的は?",
  choices:[
    "混乱した代理人（confused deputy）問題を防ぎ、他社のアカウントが同じロールを引き受けられないようにする",
    "ロールのセッション時間を延長するため",
    "IAM ロールを別リージョンでも使えるようにするため",
    "MFA の代わりとしてパスワードを保存するため"],
  answer:0, fig:"assumerole",
  note:"SaaS ベンダーは多数の顧客のロールを引き受ける。External ID がないと、ベンダーが誤って（あるいは他顧客に誘導されて）別の顧客のロールを引き受けてしまう恐れがある。\n顧客ごとに一意な External ID を sts:ExternalId 条件で必須にすることでこれを防ぐ。External ID は秘密情報ではなく「取り違え防止」の識別子である点に注意。" },

{ id:"d1-08", dom:1, cat:"IAM/認証・認可",
  q:"アカウント A の EC2 から、アカウント B の S3 バケットにアクセスする構成で必要なものは?",
  choices:[
    "B 側でロールの信頼ポリシーに A を許可し、A 側のインスタンスプロファイルに sts:AssumeRole の許可を与える（またはバケットポリシーで A のプリンシパルを許可する）",
    "A 側の IAM ポリシーだけで足りる",
    "B 側のバケットポリシーだけで足り、A 側の許可は不要",
    "両アカウントを同じ VPC に入れる"],
  answer:0, fig:"assumerole",
  note:"クロスアカウントアクセスは「呼び出す側の許可」と「呼ばれる側の許可」の両方が必要。片方だけでは通らない。\nS3 の場合は AssumeRole 経由か、バケットポリシーで相手プリンシパルを直接許可する方式のどちらか。後者ではオブジェクト所有権を「バケット所有者強制」にしておかないと、書き込まれたオブジェクトを所有者が読めない問題が起きる。" },

{ id:"d1-09", dom:1, cat:"IAM/認証・認可",
  q:"従業員が既存の社内 IdP（Okta / Entra ID など）の認証情報で、複数の AWS アカウントに役割別にログインできるようにしたい。最も運用負荷が低い構成は?",
  choices:[
    "IAM Identity Center を組織で有効化し、外部 IdP と SAML/SCIM で連携して、権限セットを OU・アカウントに割り当てる",
    "アカウントごとに IAM ユーザーを作り、パスワードを配布する",
    "アカウントごとに SAML ID プロバイダーと IAM ロールを個別に作成・維持する",
    "Amazon Cognito ユーザープールを作り、従業員を登録する"],
  answer:0,
  note:"IAM Identity Center（旧 AWS SSO）は権限セットを定義し、それを「アカウント × グループ」に割り当てるだけで各アカウントに IAM ロールが自動生成・維持される。SCIM でユーザー/グループの同期も自動化できる。\n選択肢3も動くが、アカウント数だけ手作業が増える。Cognito は顧客向け（B2C）アプリの認証であり、従業員の AWS アクセスには使わない。" },

{ id:"d1-10", dom:1, cat:"IAM/認証・認可",
  q:"開発者に IAM ロールの作成を許可したいが、作ったロールが管理者権限を持てないようにしたい。使うべき仕組みは?",
  choices:[
    "アクセス許可境界（Permissions Boundary）を必須にする条件付きの IAM ポリシーを開発者に与える",
    "SCP で iam:CreateRole を Deny する",
    "開発者に IAM の読み取り権限だけ与える",
    "ロール作成のたびに管理者が手動レビューする"],
  answer:0,
  note:"アクセス許可境界は「そのプリンシパルが持てる権限の上限」を定めるマネージドポリシー。開発者側のポリシーに iam:PermissionsBoundary 条件を付けて、指定の境界ポリシーを付けたロールしか作れないようにするのが定番パターン（権限委譲）。\nSCP はアカウント全体の上限であって、個々のプリンシパルへの委譲制御には向かない。" },

{ id:"d1-11", dom:1, cat:"IAM/認証・認可",
  q:"プロジェクトが増えるたびに IAM ポリシーを増やしたくない。「同じ部署タグを持つリソースにだけアクセスできる」形で権限を管理する手法は?",
  choices:[
    "ABAC（属性ベースアクセス制御）: プリンシパルタグとリソースタグを条件で突き合わせる",
    "RBAC（ロールベースアクセス制御）でプロジェクトごとにロールを作る",
    "アカウントをプロジェクトごとに分ける",
    "リソース名のプレフィックスを ARN のワイルドカードで指定する"],
  answer:0,
  note:"ABAC は aws:PrincipalTag/xxx と aws:ResourceTag/xxx を比較する条件を1本書くだけで、プロジェクトが増えてもポリシーを増やさずに済む。\nタグ付けの規律が前提になるので、aws:RequestTag や aws:TagKeys 条件でタグ必須を強制するのとセットで設計する。" },

{ id:"d1-12", dom:1, cat:"ネットワーク",
  q:"20 個の VPC を相互接続する必要があります。VPC ピアリングではなく Transit Gateway を選ぶ主な理由を2つ選んでください。",
  choices:[
    "接続数が VPC の数に比例するだけで済み、フルメッシュの管理を避けられる",
    "AWS RAM で他アカウントに共有し、複数アカウントの VPC を1つのハブに集約できる",
    "VPC ピアリングと違ってデータ転送料金が一切かからない",
    "重複した CIDR を持つ VPC 同士でもそのまま通信できる"],
  answer:[0,1], fig:"tgw",
  note:"VPC ピアリングは推移的ルーティングができないためフルメッシュが必要で、20 VPC なら 190 本になる。TGW ならアタッチメント 20 本。\nTGW はアタッチメント時間課金＋データ処理料金がかかる（無料ではない）。CIDR 重複はどちらの方式でも解決できず、その場合は PrivateLink や NAT を使う。" },

{ id:"d1-13", dom:1, cat:"ネットワーク",
  q:"すべての VPC 間通信とインターネット向け通信を、サードパーティのファイアウォールアプライアンスで検査してから通したい。TGW を使った標準的な構成は?",
  choices:[
    "検査用 VPC を用意し、TGW のルートテーブルを分けて、スポーク VPC からのトラフィックをいったん検査 VPC に向ける（Gateway Load Balancer でアプライアンスを冗長化）",
    "各 VPC にアプライアンスを1台ずつ立て、ルートテーブルを個別に書き換える",
    "TGW にファイアウォールルールを直接設定する",
    "各 VPC のセキュリティグループでディープパケットインスペクションを行う"],
  answer:0,
  note:"TGW は複数のルートテーブルを持てるので、「スポーク用」と「検査用」を分けて、スポーク→検査 VPC→スポークというヘアピン経路を作れる（集約検査）。\nアプライアンスの冗長化とスケールは Gateway Load Balancer（GENEVE でトラフィックをアプライアンスに透過的に渡す）が担う。TGW 自体にはファイアウォール機能はない（AWS Network Firewall は別サービス）。" },

{ id:"d1-14", dom:1, cat:"ネットワーク",
  q:"AWS RAM（Resource Access Manager）で他アカウントと共有できるリソースの例として正しくないものは?",
  choices:[
    "IAM ロール",
    "VPC のサブネット",
    "Transit Gateway",
    "Route 53 Resolver ルール"],
  answer:0,
  note:"RAM で共有できる代表例はサブネット（VPC 共有）、Transit Gateway、Route 53 Resolver ルール、License Manager 設定、Aurora DB クラスターのスナップショット、Network Firewall のルールグループなど。\nIAM ロールは RAM の対象ではなく、信頼ポリシーで他アカウントに引き受けさせる形で共有する。" },

{ id:"d1-15", dom:1, cat:"ネットワーク",
  q:"VPC 共有（Shared VPC）で、ネットワークアカウントがサブネットを他のアカウントに共有しました。参加者アカウントができることは?",
  choices:[
    "共有されたサブネットにリソースを作成できるが、VPC やサブネット自体の変更・削除はできない",
    "共有された VPC のルートテーブルや NAT ゲートウェイを自由に変更できる",
    "共有されたサブネットを他のアカウントにさらに再共有できる",
    "VPC 全体を自アカウントに移管できる"],
  answer:0,
  note:"VPC 共有ではネットワーク（VPC・サブネット・ルートテーブル・IGW/NAT）の管理を1アカウントに集約し、参加者はそこに EC2/RDS/ELB などを配置するだけ。\nCIDR の消費を抑えつつネットワーク統制を効かせられるのが利点。参加者は自分が作ったリソースだけを見られる。" },

{ id:"d1-16", dom:1, cat:"ネットワーク",
  q:"社内向けの API を、CIDR が重複している複数の顧客アカウントの VPC に公開したい。最適なのは?",
  choices:[
    "NLB の前に VPC エンドポイントサービス（AWS PrivateLink）を構成し、各利用側がインターフェイスエンドポイントを作る",
    "VPC ピアリングを顧客ごとに張る",
    "Transit Gateway で全 VPC を接続する",
    "パブリックインターネット経由で公開し、セキュリティグループで IP を絞る"],
  answer:0,
  note:"PrivateLink は「サービス提供側 → 利用側」の一方向接続で、双方のルーティングを結合しないため CIDR が重複していても使える。公開単位もサービス単位に限定される。\nピアリングと TGW はどちらも IP ルーティングを統合するので CIDR 重複を許容できない。" },

{ id:"d1-17", dom:1, cat:"ハイブリッド接続",
  q:"オンプレの DNS サーバーが持つ corp.example.com を AWS 側の EC2 から解決し、同時にオンプレから AWS のプライベートホストゾーンを解決したい。必要な構成は?",
  choices:[
    "Route 53 Resolver のアウトバウンドエンドポイント＋転送ルール（AWS→オンプレ）と、インバウンドエンドポイント（オンプレ→AWS）を作る",
    "各 EC2 の /etc/resolv.conf にオンプレ DNS を直接書く",
    "パブリックホストゾーンに corp.example.com を登録する",
    "VPC の DHCP オプションセットでオンプレ DNS のみを指定する"],
  answer:0, fig:"hybriddns",
  note:"アウトバウンドエンドポイント＋転送ルールで「このドメインはオンプレ DNS へ転送」を定義する。逆方向はインバウンドエンドポイントの IP をオンプレ DNS の条件付きフォワーダに設定する。\n転送ルールは RAM で他アカウントに共有できるので、多アカウント環境ではネットワークアカウントで一元管理するのが定石。DHCP オプションでオンプレ DNS のみにすると、AWS のサービスエンドポイント解決が壊れる。" },

{ id:"d1-18", dom:1, cat:"ハイブリッド接続",
  q:"Direct Connect について正しい説明を2つ選んでください。",
  choices:[
    "既定では暗号化されないため、暗号化が要件なら DX の上に IPsec VPN を張るか MACsec を使う",
    "トランジット仮想インターフェイス（Transit VIF）で Direct Connect Gateway 経由の Transit Gateway に接続できる",
    "単一の Direct Connect 接続でも AWS の SLA が適用される",
    "パブリック VIF では S3 などのパブリックサービスにアクセスできない"],
  answer:[0,1],
  note:"DX は専用線であって暗号化された経路ではない。暗号化要件があれば VPN over DX か、専有接続での MACsec を使う。\nVIF は3種類: プライベート VIF（VPC の VGW）、トランジット VIF（DX Gateway→TGW）、パブリック VIF（S3 などパブリックエンドポイント）。高可用性の SLA は複数接続・複数ロケーション構成が前提。" },

{ id:"d1-19", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"組織内すべてのアカウント・リージョンの API 呼び出しを、メンバーアカウントの管理者が停止できない形で1か所に集約したい。最適なのは?",
  choices:[
    "管理アカウント（または委任管理者）で CloudTrail の組織証跡を作成し、専用のログアーカイブアカウントの S3 バケットに出力する",
    "各アカウントで個別に証跡を作成し、担当者に S3 へコピーしてもらう",
    "CloudWatch Logs のサブスクリプションフィルターだけで集約する",
    "AWS Config のアグリゲータでログを集約する"],
  answer:0,
  note:"組織証跡は全メンバーアカウントに自動適用され、メンバーアカウント側では無効化も変更もできない。新規アカウントにも自動で適用される。\n出力先のログアーカイブアカウントでは S3 Object Lock（コンプライアンスモード）とバケットポリシーで改ざん・削除を防ぐ。Config アグリゲータは構成情報の集約であって API 監査ログではない。" },

{ id:"d1-20", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"組織内の全アカウントについて「S3 バケットがパブリック公開されていないか」を継続的に評価し、違反を一覧したい。最も適した組み合わせは?",
  choices:[
    "AWS Config のコンフォーマンスパックを組織全体にデプロイし、Config アグリゲータで結果を1アカウントに集約する",
    "各アカウントで CloudTrail を有効にして Athena でクエリする",
    "Trusted Advisor のレポートを毎月手動で確認する",
    "GuardDuty の検出結果を確認する"],
  answer:0,
  note:"Config ルール／コンフォーマンスパックは「構成が望ましい状態か」を継続評価する仕組みで、Organizations 経由で全アカウント・全リージョンに一括デプロイできる。アグリゲータで結果を1か所に集約する。\n違反時の自動修復は SSM Automation を修復アクションに設定すればよい。GuardDuty は脅威検知であり構成コンプライアンスではない。" },

{ id:"d1-21", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"GuardDuty・Security Hub・Detective などを多アカウントで運用するとき、AWS が推奨する構成は?",
  choices:[
    "セキュリティ専用アカウントを委任管理者（delegated administrator）に指定し、そこから全メンバーを一元管理する",
    "管理アカウント（マネジメントアカウント）で直接すべてを運用する",
    "アカウントごとに担当者を決めて個別に運用する",
    "各アカウントの検出結果を毎日 CSV でエクスポートして集約する"],
  answer:0,
  note:"管理アカウントは請求と組織管理に専念させ、日常のセキュリティ運用は委任管理者アカウントに委譲するのがベストプラクティス（Control Tower の Audit アカウントがこれに当たる）。\n委任管理者は組織内の新規アカウントに対する自動有効化も設定できる。" },

{ id:"d1-22", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"AWS WAF の共通ルールセットと Shield Advanced の保護を、組織内のすべての ALB / CloudFront に強制的に適用し、新しく作られたリソースにも自動適用したい。使うサービスは?",
  choices:[
    "AWS Firewall Manager",
    "AWS Config のカスタムルール",
    "AWS Systems Manager State Manager",
    "SCP で ALB の作成を制限する"],
  answer:0,
  note:"Firewall Manager は Organizations と連携し、WAF の Web ACL、Shield Advanced 保護、セキュリティグループの監査/共通ルール、Network Firewall、Route 53 Resolver DNS Firewall のポリシーを組織横断で強制する。\n前提として Organizations 有効化、Config 有効化、Firewall Manager 管理者アカウントの指定が必要。" },

{ id:"d1-23", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"監査要件として、バックアップを「誰も（root でも）削除できない」形で7年間保持する必要があります。最適なのは?",
  choices:[
    "AWS Backup のバックアップボールトに Vault Lock をコンプライアンスモードで設定する",
    "S3 バケットのバージョニングと MFA Delete を有効にする",
    "IAM ポリシーで削除操作を Deny する",
    "スナップショットを別リージョンにコピーする"],
  answer:0,
  note:"AWS Backup Vault Lock のコンプライアンスモードは、クールオフ期間の経過後は AWS アカウントの root ユーザーでも解除・短縮できない WORM 保護になる（ガバナンスモードは特権ユーザーが解除可能）。\nIAM の Deny は権限を持つ者が変更できてしまうため、規制対応の証跡としては弱い。" },

{ id:"d1-24", dom:1, cat:"アカウント/組織管理",
  q:"全アカウントに共通の IAM ロールと VPC フローログ設定を配布し、新規アカウントにも自動で展開したい。最適なのは?",
  choices:[
    "CloudFormation StackSets をサービスマネージド型（Organizations 連携）で作成し、自動デプロイを有効にして OU をターゲットにする",
    "各アカウントの担当者に CloudFormation テンプレートをメールで配布する",
    "AWS Config のカスタムルールで作成する",
    "Systems Manager Run Command で全アカウントに一括実行する"],
  answer:0,
  note:"サービスマネージド型 StackSets は OU をターゲットにでき、「自動デプロイ」を有効にすると OU に追加された新規アカウントへ自動でスタックが展開され、OU から外れると削除される。\nセルフマネージド型は各アカウントに実行ロールを用意する必要があり、多アカウントでは運用が重い。" },

{ id:"d1-25", dom:1, cat:"アカウント/組織管理",
  q:"開発者が自由に使える標準構成（承認済み AMI・許可されたインスタンスタイプ・所定のタグ）を、IAM 権限を広く渡さずにセルフサービスで提供したい。適したサービスは?",
  choices:[
    "AWS Service Catalog",
    "AWS Marketplace",
    "AWS Systems Manager Automation",
    "AWS Proton のみ"],
  answer:0,
  note:"Service Catalog は管理者が CloudFormation テンプレートを「製品」として登録し、起動制約（Launch Constraint）で製品用のロールを使わせる。利用者は Service Catalog の権限だけで、裏側の EC2/RDS などを直接操作する権限は不要になる。\nControl Tower の Account Factory も Service Catalog の製品として実装されている。" },

{ id:"d1-26", dom:1, cat:"アカウント/組織管理",
  q:"組織のタグ付け規約を守らせたい。「タグポリシー」と「SCP によるタグ強制」の違いとして正しいものは?",
  choices:[
    "タグポリシーはタグのキー/値の表記ゆれを検出・是正するもので、タグの無いリソース作成をブロックするには SCP の aws:RequestTag 条件が必要",
    "タグポリシーはタグの無いリソース作成を自動的にブロックする",
    "SCP はタグの値の大文字小文字を統一できる",
    "どちらも同じ機能で、どちらを使ってもよい"],
  answer:0,
  note:"タグポリシーは「準拠しているか」の評価とレポートが中心で、リソース作成そのものは止めない（一部サービスで作成時の強制は可能だが対象は限定的）。\n確実にブロックしたい場合は SCP で aws:RequestTag/Project が存在しない CreateXxx を Deny する。両者は補完関係にある。" },

{ id:"d1-27", dom:1, cat:"IAM/認証・認可",
  q:"AWS Managed Microsoft AD を1つ立て、複数のアカウントの EC2（Windows）をドメイン参加させたい。最も適切なのは?",
  choices:[
    "ディレクトリ共有（Directory Sharing）で他アカウントにディレクトリを共有する",
    "アカウントごとに Managed Microsoft AD を作成し、双方向信頼を張る",
    "AD Connector を各アカウントに作成する",
    "各 EC2 にローカルアカウントを作成する"],
  answer:0,
  note:"AWS Managed Microsoft AD はディレクトリ共有に対応しており、1つのディレクトリを複数アカウント・複数 VPC から利用できる（VPC 間の接続は別途必要）。ディレクトリの重複作成を避けられコストも下がる。\nAD Connector は既存のオンプレ AD への「プロキシ」であり、ディレクトリ自体を持たない。" },

{ id:"d1-28", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"KMS のカスタマーマネージドキーを、別アカウントの EC2 から使わせる必要があります。正しい設定は?",
  choices:[
    "キーポリシーで相手アカウントを許可し、かつ相手アカウント側の IAM ポリシーでも当該キーの使用を許可する",
    "キーポリシーだけを設定すればよい",
    "相手アカウントの IAM ポリシーだけを設定すればよい",
    "KMS キーは他アカウントと共有できない"],
  answer:0,
  note:"KMS はリソースベースのキーポリシーが必須で、クロスアカウントの場合はキーポリシー（提供側）と IAM ポリシー（利用側）の両方の許可が要る。\nキーポリシーに何も書かないと IAM ポリシーだけでは一切使えない点が KMS 特有。細粒度の一時的な許可には Grant を使う。" },

{ id:"d1-29", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"組織外のアカウントやパブリックに意図せず公開されているリソース（S3 バケット、IAM ロール、KMS キーなど）を洗い出したい。使うべきものは?",
  choices:[
    "IAM Access Analyzer で、組織を信頼ゾーンにしたアナライザーを作成する",
    "IAM Credential Report を確認する",
    "Trusted Advisor のコスト最適化チェック",
    "CloudTrail Insights"],
  answer:0,
  note:"IAM Access Analyzer は信頼ゾーン（アカウントまたは組織）を設定し、その外部からアクセスできるリソースポリシーを論理的に解析して検出結果を出す。\nほかに、CloudTrail のログから最小権限ポリシーを生成する機能や、ポリシーの検証（Policy Validation）機能もある。" },

{ id:"d1-30", dom:1, cat:"IAM/認証・認可",
  q:"SCP で「自組織のプリンシパル以外からのアクセスを一律に拒否したい」ときに使う条件キーは?",
  choices:[
    "aws:PrincipalOrgID",
    "aws:SourceIp",
    "aws:userid",
    "aws:RequestedRegion"],
  answer:0,
  note:"aws:PrincipalOrgID は呼び出し元プリンシパルが所属する Organizations の ID と比較する条件キー。バケットポリシーなどのリソースポリシーで「組織内からのみ許可」を書くのに多用される。\n特定 OU に限定したい場合は aws:PrincipalOrgPaths を使う。" },

{ id:"d1-31", dom:1, cat:"アカウント/組織管理",
  q:"ワークロードを別々の AWS アカウントに分離する主な理由として適切でないものは?",
  choices:[
    "アカウントを分けると同じリソースでも単価が安くなるため",
    "サービスクォータ（上限）がアカウント単位のため、他ワークロードの影響を受けない",
    "セキュリティインシデント時の影響範囲（爆発半径）を限定できる",
    "請求とコスト配分が自然に分離される"],
  answer:0,
  note:"アカウント分離の狙いは、爆発半径の限定・クォータの分離・請求の分離・権限境界の明確化。単価はむしろ一括請求で合算したほうが有利になる。\n分離の代償はネットワークと ID の複雑化で、そこを Organizations・RAM・IAM Identity Center・TGW で埋めるのが SAP の頻出テーマ。" },

{ id:"d1-32", dom:1, cat:"ネットワーク",
  q:"数十の VPC からのインターネット向け通信（アウトバウンド）を集約して、コストと管理を減らしたい。標準的な構成は?",
  choices:[
    "エグレス専用 VPC に NAT ゲートウェイを置き、TGW 経由で全スポーク VPC の 0.0.0.0/0 をそこへ向ける",
    "各 VPC の各 AZ に NAT ゲートウェイを置く",
    "各 EC2 にパブリック IP を付与する",
    "各 VPC に Egress-Only インターネットゲートウェイを置く"],
  answer:0,
  note:"NAT ゲートウェイは時間課金＋データ処理課金なので、VPC × AZ の数だけ作ると急速に高くつく。集約エグレス VPC にまとめると台数を大幅に減らせる。\nただし TGW のデータ処理料金が別途かかるため、トラフィック量によっては分散のほうが安い場合もある。S3/DynamoDB 向けはゲートウェイ VPC エンドポイントで NAT を経由させないのが基本。" },

{ id:"d1-33", dom:1, cat:"監視/運用自動化",
  q:"組織内の全アカウントで発生した AWS 側のメンテナンスや障害イベントを、一元的に把握したい。適切なのは?",
  choices:[
    "AWS Health の組織ビュー（Organizational View）を有効にし、Health API / EventBridge で集約する",
    "各アカウントのマネジメントコンソールを毎朝確認する",
    "CloudWatch の標準メトリクスにアラームを設定する",
    "Personal Health Dashboard を各アカウントで個別に見る"],
  answer:0,
  note:"AWS Health の組織ビューを有効にすると、管理アカウントから全メンバーアカウントのイベントを横断的に参照でき、Health API でも取得できる。\nEventBridge の aws.health イベントをフックにして、Slack 通知や自動対応につなげるのが一般的。" },

{ id:"d1-34", dom:1, cat:"アカウント/組織管理",
  q:"組織内の全アカウントのバックアップ計画（頻度・保持期間・コピー先リージョン）を中央で定義・強制したい。適切なのは?",
  choices:[
    "AWS Organizations のバックアップポリシーで AWS Backup のバックアッププランを組織横断に適用する",
    "各アカウントで EventBridge スケジュールと Lambda を実装する",
    "SCP でスナップショット削除を Deny する",
    "Data Lifecycle Manager を各アカウントで手動設定する"],
  answer:0,
  note:"バックアップポリシーは SCP と同じく Root/OU/アカウントに付与し、継承・マージされる Organizations の管理ポリシー。AWS Backup のプランを中央で強制できる。\nタグポリシー、AI サービスのオプトアウトポリシー、チャットボットポリシーなども同じ「管理ポリシー」の仲間。" },

{ id:"d1-35", dom:1, cat:"IAM/認証・認可",
  q:"オンプレミスのサーバーから AWS API を呼び出す必要があります。長期のアクセスキーを配布せずに済む方法は?",
  choices:[
    "IAM Roles Anywhere を使い、信頼した認証局が発行した X.509 証明書で一時認証情報を取得する",
    "IAM ユーザーを作成しアクセスキーを配布する（90日ごとにローテーション）",
    "EC2 インスタンスプロファイルをオンプレサーバーに設定する",
    "Cognito ID プールを使う"],
  answer:0,
  note:"IAM Roles Anywhere は PKI（自社 CA または AWS Private CA）で発行した証明書を信頼アンカーとして、オンプレやほかのクラウドのワークロードに一時認証情報を渡す。\nEC2 ではインスタンスプロファイル、EKS では IRSA / Pod Identity、Lambda では実行ロールと、いずれも「長期キーを置かない」が原則。" },

{ id:"d1-36", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"S3 バケットに他アカウントがオブジェクトを書き込むと、バケット所有者がそのオブジェクトを読めないことがあります。これを恒久的に解決する設定は?",
  choices:[
    "オブジェクト所有権を「バケット所有者強制（Bucket owner enforced）」にして ACL を無効化する",
    "書き込み側に bucket-owner-full-control ACL を毎回指定してもらう",
    "バケットのバージョニングを有効にする",
    "バケットポリシーで s3:GetObject を全員に許可する"],
  answer:0,
  note:"従来は書き込み側が ACL を指定しないと所有権が移らなかった。オブジェクト所有権を「バケット所有者強制」にすると ACL 自体が無効化され、書き込まれたオブジェクトは常にバケット所有者のものになる（現在の新規バケットの既定）。\nアクセス制御はバケットポリシーと IAM に一本化される。" },

{ id:"d1-37", dom:1, cat:"ネットワーク",
  q:"複数アカウント・複数 VPC の環境で、プライベートホストゾーンを一元管理したい。正しい説明は?",
  choices:[
    "1つのプライベートホストゾーンに複数の VPC を関連付けられ、別アカウントの VPC も API/CLI で関連付けできる",
    "プライベートホストゾーンは作成時に指定した1つの VPC としか関連付けできない",
    "別アカウントの VPC はマネジメントコンソールから簡単に関連付けできる",
    "プライベートホストゾーンは Route 53 Resolver ルールで置き換える必要がある"],
  answer:0,
  note:"クロスアカウントの関連付けは、ホストゾーン側で create-vpc-association-authorization を実行し、VPC 側で associate-vpc-with-hosted-zone を実行する2段階。コンソールでは行えず CLI/API が必要。\n多数のアカウントがある場合は、Resolver ルールを RAM 共有して中央のホストゾーンに転送する構成もよく使われる。" },

{ id:"d1-38", dom:1, cat:"アカウント/組織管理",
  q:"すでに独立して運用されている既存の AWS アカウントを、自社の Organizations に取り込む方法は?",
  choices:[
    "管理アカウントから招待を送り、既存アカウント側で承諾する",
    "Organizations から新規アカウントを作成し、リソースを手動移行する以外に方法はない",
    "AWS サポートに依頼して強制的に統合してもらう",
    "既存アカウントの root ユーザーを管理アカウントに変更する"],
  answer:0,
  note:"アカウントの参加方法は「新規作成」と「招待」の2つ。招待の場合、支払い方法などのアカウント設定は既存のものが引き継がれ、請求だけが管理アカウントに統合される。\n招待で参加したアカウントは組織から離脱できるが、離脱には支払い情報など独立に必要な情報の登録が求められる。" },

{ id:"d1-39", dom:1, cat:"監視/運用自動化",
  q:"全アカウントの VPC フローログとアプリログを1つの分析基盤に集めたい。運用が最も軽い構成は?",
  choices:[
    "フローログを中央ログアカウントの S3 バケットへ直接出力し、Athena／OpenSearch で分析する",
    "各アカウントの CloudWatch Logs に出力し、担当者が必要に応じてダウンロードする",
    "各アカウントに OpenSearch クラスターを構築する",
    "EC2 に syslog サーバーを立てて全ログを転送する"],
  answer:0,
  note:"VPC フローログは S3 に直接（Parquet 形式も可）出力でき、クロスアカウントのバケットも指定できるため、中央集約が最も簡単で安い。\nリアルタイム性が要るログは CloudWatch Logs のサブスクリプションフィルター → Kinesis Data Firehose → 中央の S3/OpenSearch という経路を取る。" },

{ id:"d1-40", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"組織のすべてのアカウントで、承認された2リージョン以外での新規リソース作成を禁止したい。最も確実な方法は?",
  choices:[
    "SCP で aws:RequestedRegion 条件を使い、グローバルサービスを除外したうえで他リージョンのアクションを Deny する",
    "IAM ポリシーを全ユーザーに手動で適用する",
    "AWS Config ルールで違反リージョンのリソースを検出する",
    "各リージョンを AWS サポートに依頼して無効化してもらう"],
  answer:0,
  note:"SCP の Deny＋aws:RequestedRegion が定番。IAM・CloudFront・Route 53・Organizations などグローバルサービスは us-east-1 でエンドポイントを持つため、NotAction で除外しないと管理操作まで止まる。\nOrganizations にはリージョンのオプトイン制御もあり、未使用リージョンはそもそも無効のままにしておくのがよい。" },

{ id:"d1-41", dom:1, cat:"IAM/認証・認可",
  q:"IAM ポリシーの評価で、明示的な Deny・明示的な Allow・暗黙的な Deny の関係として正しいものは?",
  choices:[
    "明示的な Deny が最優先で、次に明示的な Allow、どこにも Allow が無ければ暗黙的に拒否される",
    "明示的な Allow が明示的な Deny より優先される",
    "SCP の Allow は IAM の Deny を上書きできる",
    "リソースベースポリシーの Allow はアイデンティティベースの Deny を上書きできる"],
  answer:0,
  note:"評価順は「明示的 Deny > 明示的 Allow > 暗黙的 Deny」。SCP・アクセス許可境界・セッションポリシー・リソースポリシーのいずれかで Deny されれば通らない。\n同一アカウント内なら、リソースベースポリシーの Allow だけでアクセスできる場合もあるが（S3 など）、クロスアカウントでは両側の Allow が必要。" },

{ id:"d1-42", dom:1, cat:"アカウント/組織管理",
  q:"ある企業が「本番」「開発」「サンドボックス」を明確に分けたうえで、サンドボックスでは高額なインスタンスタイプと一部リージョンを使わせたくないと考えています。最も適切な設計は?",
  choices:[
    "用途ごとに OU を分け、サンドボックス OU に条件付きの Deny SCP を適用する",
    "1つのアカウント内でタグによって用途を区別し、IAM ポリシーで制御する",
    "サンドボックス用の請求アラートだけを設定する",
    "各開発者に IAM ユーザーを作り、月末に使用状況をレビューする"],
  answer:0,
  note:"「OU は環境・用途で切り、SCP をその OU に当てる」が Organizations 設計の基本形。ec2:InstanceType 条件で高額タイプを Deny、aws:RequestedRegion で範囲を絞る。\nアカウント内タグ分離は権限のすり抜けとクォータ競合が起きやすく、SAP では基本的に不正解になる。" },

{ id:"d1-43", dom:1, cat:"IAM/認証・認可",
  q:"IAM Identity Center の「権限セット（Permission Set）」の実体は?",
  choices:[
    "割り当て先の各アカウントに自動作成・維持される IAM ロール",
    "各アカウントに作られる IAM ユーザーのグループ",
    "SCP の一種",
    "アクセス許可境界のテンプレート"],
  answer:0,
  note:"権限セットを「アカウント × グループ/ユーザー」に割り当てると、対象アカウントに対応する IAM ロールが自動でプロビジョニングされ、変更も同期される。\nこのロールを手で編集してはいけない（Identity Center が上書きする）。権限セットにはアクセス許可境界やカスタマー管理ポリシーの参照も設定できる。" },

{ id:"d1-44", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"中央のログアーカイブアカウントの S3 バケットについて、監査要件を満たす設定として適切なものを2つ選んでください。",
  choices:[
    "S3 Object Lock（コンプライアンスモード）で保持期間を設定する",
    "バケットポリシーで aws:PrincipalOrgID による書き込み許可と、削除操作の Deny を設定する",
    "バケットを毎日別リージョンへ手動コピーする",
    "バケットをパブリック読み取りにして監査人がいつでも参照できるようにする"],
  answer:[0,1],
  note:"改ざん・削除防止は Object Lock（WORM）、アクセス制御はバケットポリシーで組織内に限定するのが定石。バージョニングは Object Lock の前提条件。\nクロスリージョンの耐久性は S3 レプリケーションで自動化する。パブリック公開は論外で、Block Public Access をアカウントレベルで有効にしておく。" },

{ id:"d1-45", dom:1, cat:"ネットワーク",
  q:"複数アカウントで IP アドレスの重複や枯渇が問題になっています。CIDR の割り当てを組織で一元管理・監視したい。適切なサービスは?",
  choices:[
    "Amazon VPC IP Address Manager（IPAM）",
    "AWS Config",
    "Route 53 Resolver",
    "AWS Network Manager のみ"],
  answer:0,
  note:"IPAM は IP アドレスプールを階層的に定義し、OU/アカウント/リージョンへの割り当て、使用率のモニタリング、重複の検出、VPC 作成時の自動 CIDR 払い出しを提供する。RAM で組織に共有して使う。\nNetwork Manager は TGW を中心としたグローバルネットワークの可視化で、目的が異なる。" },

/* =======================================================================
 * ドメイン2: 新しいソリューションのための設計（29%）
 * ===================================================================== */

{ id:"d2-01", dom:2, cat:"可用性/DR",
  q:"DR 戦略のうち、コストが最も低く RTO/RPO が最も長いものは?",
  choices:[
    "バックアップ＆リストア",
    "パイロットライト",
    "ウォームスタンバイ",
    "マルチサイトアクティブ/アクティブ"],
  answer:0, fig:"dr",
  note:"4戦略はコストと RTO/RPO のトレードオフ。バックアップ＆リストア（数時間）→パイロットライト（数十分）→ウォームスタンバイ（数分）→マルチサイト（ほぼゼロ）。\n設問で提示された RTO/RPO と予算から戦略を選ばせる問題が頻出。「RPO 15分・RTO 4時間」ならパイロットライトで足りる、といった判断ができるようにしておく。" },

{ id:"d2-02", dom:2, cat:"可用性/DR",
  q:"パイロットライトとウォームスタンバイの違いとして正しいものは?",
  choices:[
    "パイロットライトはデータ複製のみ常時行いアプリ層は停止、ウォームスタンバイは縮小構成のアプリ層が常時稼働している",
    "パイロットライトのほうが RTO が短い",
    "ウォームスタンバイではデータを複製しない",
    "パイロットライトは単一リージョン内でのみ使える"],
  answer:0, fig:"dr",
  note:"パイロットライトは「種火」。DB のレプリカや AMI/データは用意しておくが、アプリのインスタンスは起動していないため復旧時に起動とスケールが必要。\nウォームスタンバイは常に小さく動いているので、トラフィックを向けてスケールアップするだけで済み RTO が短い。その分コストは高い。" },

{ id:"d2-03", dom:2, cat:"データベース",
  q:"Aurora のクロスリージョン DR で、RPO を1秒未満、RTO を1分程度にしたい。適した構成は?",
  choices:[
    "Aurora グローバルデータベースでセカンダリリージョンにレプリカを持つ",
    "毎時スナップショットを取得してクロスリージョンコピーする",
    "リードレプリカをクロスリージョンで作成する（従来型）",
    "DMS で継続的にレプリケーションする"],
  answer:0,
  note:"Aurora グローバルデータベースはストレージ層でレプリケーションするため、一般に RPO 1秒未満・（手動フェイルオーバーでの）RTO 1分程度をうたう。計画的なスイッチオーバーなら RPO 0。\nスナップショットコピーは RPO が取得間隔ぶん、DMS は運用が重い。ライターは常に1リージョンで、セカンダリは読み取り専用である点に注意。" },

{ id:"d2-04", dom:2, cat:"データベース",
  q:"DynamoDB グローバルテーブルについて正しい説明を2つ選んでください。",
  choices:[
    "複数リージョンで同時に読み書きできるマルチアクティブ構成になる",
    "同じ項目が複数リージョンでほぼ同時に更新された場合、最後の書き込みが勝つ（last writer wins）",
    "セカンダリリージョンは読み取り専用になる",
    "強い整合性のある読み取りがリージョン間で保証される"],
  answer:[0,1],
  note:"グローバルテーブルはマルチアクティブでリージョン間は非同期レプリケーション。競合は最終書き込み優先で解決されるため、厳密な整合性が必要な処理には向かない。\nリージョン間の整合性は結果整合。強整合の読み取りは同一リージョン内でのみ有効。" },

{ id:"d2-05", dom:2, cat:"ネットワーク",
  q:"UDP を使うオンラインゲームのグローバルサービスで、固定 IP と最寄りリージョンへの高速なルーティング、リージョン障害時の即時フェイルオーバーが必要です。適したサービスは?",
  choices:[
    "AWS Global Accelerator",
    "Amazon CloudFront",
    "Route 53 のレイテンシールーティング",
    "Application Load Balancer のクロスリージョン設定"],
  answer:0,
  note:"Global Accelerator は Anycast の静的 IP を2つ提供し、TCP/UDP を含む任意のプロトコルで AWS のバックボーンにエッジから乗せる。ヘルスチェック失敗時のフェイルオーバーは DNS のキャッシュに影響されず数秒。\nCloudFront は HTTP/HTTPS のコンテンツ配信、Route 53 のレイテンシールーティングは DNS TTL のぶん切り替えが遅い。" },

{ id:"d2-06", dom:2, cat:"ネットワーク",
  q:"ALB・NLB・GWLB の使い分けとして正しいものは?",
  choices:[
    "ALB は L7（HTTP/HTTPS のパス・ホストベースルーティング）、NLB は L4（TCP/UDP・静的 IP・超低レイテンシ）、GWLB は L3 でサードパーティのインライン検査アプライアンス向け",
    "ALB は L4、NLB は L7、GWLB は L2",
    "3つとも L7 で、スループットだけが違う",
    "GWLB は HTTP ヘッダーによるルーティングができる"],
  answer:0,
  note:"NLB は AZ ごとに静的 IP（Elastic IP も可）を持てて送信元 IP を保持する。ALB は認証連携・WAF 連携・Lambda ターゲットなど L7 機能が豊富。\nGWLB は GENEVE（ポート6081）でトラフィックをファイアウォール/IDS アプライアンスに透過的に流し、エンドポイントを経由させて挿入する。" },

{ id:"d2-07", dom:2, cat:"モダナイゼーション",
  q:"注文処理を非同期化します。「厳密な順序保証」と「重複排除」が必須の場合に選ぶべきキューは?",
  choices:[
    "SQS FIFO キュー",
    "SQS 標準キュー",
    "SNS 標準トピック",
    "Kinesis Data Streams"],
  answer:0,
  note:"標準キューは順序がベストエフォートで、少なくとも1回配信（重複あり）。FIFO キューはメッセージグループ単位の厳密な順序と、5分間の重複排除を提供する。\n代償としてスループット上限が低い（高スループットモードでない場合、バッチなしで 300 メッセージ/秒、バッチ利用で 3,000）。Kinesis もシャード内順序は保つが、用途はストリーム処理。" },

{ id:"d2-08", dom:2, cat:"モダナイゼーション",
  q:"SQS のコンシューマーが処理に失敗し続けるメッセージが、キューを詰まらせています。対処として適切なものを2つ選んでください。",
  choices:[
    "デッドレターキュー（DLQ）を設定し、maxReceiveCount を超えたメッセージを退避する",
    "可視性タイムアウトを処理時間より十分長く設定する",
    "メッセージ保持期間を最短の1分に設定する",
    "キューを FIFO に変更する"],
  answer:[0,1],
  note:"DLQ は「毒メッセージ」を隔離して本流を守る仕組み。あわせて、可視性タイムアウトが処理時間より短いと処理中に別のコンシューマーへ再配信され、二重処理と受信回数の増加を招く。\n保持期間は既定4日・最大14日で、短くしてもエラーの原因は解決しない。" },

{ id:"d2-09", dom:2, cat:"モダナイゼーション",
  q:"複数の AWS サービスやサードパーティ SaaS のイベントを、内容でフィルタして複数のターゲットへ配信したい。最も適したサービスは?",
  choices:[
    "Amazon EventBridge",
    "Amazon SNS",
    "Amazon SQS",
    "AWS Step Functions"],
  answer:0,
  note:"EventBridge はイベントの JSON 内容によるルールベースのフィルタリング、スキーマレジストリ、SaaS パートナーイベントバス、アーカイブ＆リプレイ、クロスアカウント/クロスリージョンのイベント配信を持つ。\nSNS はトピックへのファンアウトが主目的（メッセージ属性でのフィルタは可能）。両者の使い分けは頻出。" },

{ id:"d2-10", dom:2, cat:"モダナイゼーション",
  q:"Step Functions の Standard ワークフローと Express ワークフローの違いとして正しいものは?",
  choices:[
    "Standard は最長1年・実行履歴が残り「ちょうど1回」の実行、Express は最長5分・高スループットで「少なくとも1回」の実行",
    "Standard のほうが高スループットで安い",
    "Express は状態遷移ごとの課金、Standard は実行時間とメモリの課金",
    "Express は Lambda を呼び出せない"],
  answer:0,
  note:"Standard は状態遷移ごとの課金で長時間の業務ワークフロー向け、Express は実行回数と実行時間・メモリの課金で毎秒数十万件のイベント処理向け。\nExpress は履歴がコンソールに残らないため CloudWatch Logs での観測が前提。冪等性が必要な処理は Standard を選ぶ。" },

{ id:"d2-11", dom:2, cat:"コンピュート",
  q:"Lambda の「予約済み同時実行数（Reserved concurrency）」の説明として正しいものは?",
  choices:[
    "その関数のために同時実行数を確保しつつ、同時に上限としても機能する",
    "呼び出し時のコールドスタートを無くす",
    "アカウントの同時実行数の上限を引き上げる",
    "関数の実行時間の上限を延長する"],
  answer:0,
  note:"予約済み同時実行数は「確保」と「上限」を同時に意味する。下流の RDS を守るために意図的に絞る用途にも使われる。\nコールドスタートを無くすのはプロビジョニング済み同時実行数（Provisioned concurrency）。こちらは常時初期化済みの実行環境を維持するため課金が発生し、Application Auto Scaling でスケジュールできる。" },

{ id:"d2-12", dom:2, cat:"コンピュート",
  q:"VPC 内の RDS にアクセスする Lambda 関数から、インターネット上の外部 API も呼び出す必要があります。必要な構成は?",
  choices:[
    "Lambda をプライベートサブネットに配置し、そのサブネットのルートを NAT ゲートウェイ経由にする",
    "Lambda をパブリックサブネットに配置してパブリック IP を割り当てる",
    "Lambda に Elastic IP を関連付ける",
    "VPC 設定を外し、RDS をパブリックアクセス可能にする"],
  answer:0,
  note:"VPC に接続した Lambda はパブリック IP を持たないため、パブリックサブネットに置いてもインターネットには出られない。プライベートサブネット＋NAT ゲートウェイが必須。\nAWS サービス向けの通信は、NAT の代わりに VPC エンドポイント（S3/DynamoDB はゲートウェイ型、それ以外はインターフェイス型）を使うとコストと経路を最適化できる。" },

{ id:"d2-13", dom:2, cat:"モダナイゼーション",
  q:"API Gateway の REST API と HTTP API の選択で、HTTP API を選ぶ主な理由は?",
  choices:[
    "低コスト・低レイテンシで、JWT オーソライザーなどシンプルな要件に十分だから",
    "使用量プランと API キーによる細かな課金管理が必要だから",
    "AWS WAF との直接統合が必要だから",
    "プライベート API エンドポイント（VPC 内限定）が必要だから"],
  answer:0,
  note:"HTTP API は REST API より安く速いが、機能が絞られている。使用量プラン/API キー、WAF 統合、リクエスト/レスポンスの変換、プライベートエンドポイント、Canary デプロイなどは REST API 側の機能。\n双方向通信が必要なら WebSocket API を選ぶ。" },

{ id:"d2-14", dom:2, cat:"ストレージ",
  q:"ログを 30 日はときどき参照し、その後 90 日はほぼ参照せず、以降7年は法定保存のみで取り出しは年に1回あるかどうかです。取り出しに数時間かかっても構いません。最もコスト効率のよいライフサイクルは?",
  choices:[
    "S3 Standard →（30日）Standard-IA →（120日）Glacier Deep Archive",
    "S3 Standard →（30日）Glacier Instant Retrieval →（120日）Standard-IA",
    "すべて S3 Standard に置き、バージョニングで管理する",
    "すべて Glacier Instant Retrieval に置く"],
  answer:0, fig:"s3class",
  note:"「ときどき参照」は Standard-IA（最低30日）、「ほぼ参照しない＋取り出しに時間をかけてよい」は Deep Archive（最低180日・取り出し 12〜48時間）が最安。\nGlacier Instant Retrieval はミリ秒で取り出せるぶん保管料が Deep Archive より高いので、年1回のアーカイブには過剰。移行の順序が「高い→安い」になっているかを必ず確認する。" },

{ id:"d2-15", dom:2, cat:"ストレージ",
  q:"アクセスパターンが予測できないデータセットで、運用の手間なくコストを最適化したい。適した S3 ストレージクラスは?",
  choices:[
    "S3 Intelligent-Tiering",
    "S3 Standard-IA",
    "S3 One Zone-IA",
    "S3 Glacier Flexible Retrieval"],
  answer:0,
  note:"Intelligent-Tiering はアクセス状況を監視して自動で階層を移動し、取り出し料金がかからない。少額のモニタリング料金が object 単位でかかるため、極端に小さいオブジェクトが大量にある場合は割に合わないことがある。\n「アクセスパターンが不明・変動する」というキーワードが出たら第一候補。" },

{ id:"d2-16", dom:2, cat:"ストレージ",
  q:"S3 のクロスリージョンレプリケーション（CRR）で「15分以内に 99.99% のオブジェクトを複製」という SLA が必要です。有効にすべき機能は?",
  choices:[
    "S3 レプリケーションタイムコントロール（RTC）",
    "S3 Transfer Acceleration",
    "S3 バッチオペレーション",
    "S3 マルチリージョンアクセスポイント"],
  answer:0,
  note:"RTC は複製の SLA（15分以内に 99.99%）とレプリケーションメトリクス・イベント通知を提供する追加機能。追加料金がかかる。\nTransfer Acceleration はクライアントからのアップロード高速化、マルチリージョンアクセスポイントは複数バケットへの単一グローバルエンドポイント。目的が異なる。" },

{ id:"d2-17", dom:2, cat:"ストレージ",
  q:"Windows の SMB ファイル共有として使え、Active Directory と統合し、Windows ACL をサポートする AWS のマネージドファイルシステムは?",
  choices:[
    "Amazon FSx for Windows File Server",
    "Amazon EFS",
    "Amazon FSx for Lustre",
    "Amazon S3 File Gateway"],
  answer:0,
  note:"EFS は NFS（Linux）、FSx for Windows は SMB＋AD＋Windows ACL、FSx for Lustre は HPC/機械学習向けの高速並列ファイルシステム（S3 とのリンクが可能）、FSx for NetApp ONTAP は NFS/SMB/iSCSI のマルチプロトコル。\n「Windows・SMB・AD」というキーワードが出たら FSx for Windows。" },

{ id:"d2-18", dom:2, cat:"コンピュート",
  q:"HPC アプリケーションで、ノード間のネットワークレイテンシを最小化したい。使うべき配置グループは?",
  choices:[
    "クラスタープレイスメントグループ",
    "スプレッドプレイスメントグループ",
    "パーティションプレイスメントグループ",
    "配置グループは使わず複数 AZ に分散する"],
  answer:0,
  note:"クラスターは単一 AZ 内で物理的に近接配置し、低レイテンシ・高帯域（Elastic Fabric Adapter と組み合わせる）。ただし AZ 障害に弱い。\nスプレッドは異なるハードウェアに分散（1 AZ あたり最大7インスタンス）、パーティションは HDFS/Cassandra などラック認識が要るシステム向けに論理パーティションへ分散する。" },

{ id:"d2-19", dom:2, cat:"コスト最適化",
  q:"ステートレスなバッチ処理を大量に走らせます。中断は許容できますがジョブは完遂させたい。最もコスト効率が高い構成は?",
  choices:[
    "EC2 Auto Scaling のミックスインスタンスポリシーで、複数インスタンスタイプにわたるスポットを容量最適化戦略で確保し、中断通知でチェックポイントを取る",
    "オンデマンドインスタンスで実行する",
    "3年全額前払いのスタンダード RI を購入する",
    "スポットインスタンスを1つのインスタンスタイプだけで確保する"],
  answer:0,
  note:"スポットは最大で大幅に安いが中断される。インスタンスタイプと AZ を多様化し、割り当て戦略を capacity-optimized（または price-capacity-optimized）にすると中断率が下がる。\n中断は2分前に通知（EC2 スポットインスタンス中断通知/リバランス推奨）されるので、チェックポイントと再実行で完遂性を担保する。常時稼働が確実な基盤部分には Savings Plans を併用する。" },

{ id:"d2-20", dom:2, cat:"コスト最適化",
  q:"Compute Savings Plans と EC2 Instance Savings Plans の違いとして正しいものは?",
  choices:[
    "Compute はリージョン・インスタンスファミリー・OS を問わず EC2/Fargate/Lambda に適用でき柔軟、EC2 Instance は特定リージョンの特定ファミリーに限定される代わりに割引率が高い",
    "Compute のほうが割引率が高い",
    "EC2 Instance Savings Plans は Fargate にも適用される",
    "どちらも1年契約のみ"],
  answer:0,
  note:"柔軟性と割引率はトレードオフ。ワークロードが安定して同じファミリーを使い続けるなら EC2 Instance SP、構成変更やサーバーレス併用があるなら Compute SP。\nどちらも1年/3年、前払いなし/一部前払い/全額前払いを選べる。RI と違い「キャパシティ予約」の効果はない点にも注意（キャパシティ確保にはオンデマンドキャパシティ予約を使う）。" },

{ id:"d2-21", dom:2, cat:"コンピュート",
  q:"Auto Scaling グループで、新しいインスタンスが起動してからアプリの初期化が終わるまでに5分かかるため、スケールアウトが遅れています。適切な対策を2つ選んでください。",
  choices:[
    "ウォームプールを設定し、初期化済みで停止状態のインスタンスをあらかじめ用意しておく",
    "予測スケーリングを有効にして、需要増の前に先回りしてスケールする",
    "ヘルスチェックの猶予期間を0秒にする",
    "デタッチしたインスタンスを手動で追加する"],
  answer:[0,1],
  note:"ウォームプールは初期化済みインスタンスを Stopped/Hibernated で待機させ、スケールアウト時の起動時間を大幅に短縮する（停止中は EBS 料金のみ）。\n予測スケーリングは機械学習で日次・週次の需要パターンを学習し先回りする。ライフサイクルフックは初期化完了までインスタンスを InService にしない仕組みで、これも併用する。" },

{ id:"d2-22", dom:2, cat:"データベース",
  q:"Lambda から RDS への接続数が急増し、DB の接続上限に達しました。最も適した対策は?",
  choices:[
    "RDS Proxy を導入して接続をプールする",
    "Lambda のメモリを増やす",
    "RDS のインスタンスサイズを2倍にする",
    "Lambda を VPC の外に出す"],
  answer:0,
  note:"RDS Proxy は接続をプール・多重化して、Lambda のように短命かつ大量の実行環境から接続する構成に適する。フェイルオーバー時間の短縮や、Secrets Manager/IAM 認証との統合も利点。\nインスタンスを大きくすれば接続上限は上がるが、根本的な接続の使い捨て問題は解決しない。" },

{ id:"d2-23", dom:2, cat:"データベース",
  q:"DynamoDB のテーブルで、特定のパーティションにアクセスが集中してスロットリングが発生しています。根本的な対策は?",
  choices:[
    "パーティションキーの設計を見直し、カーディナリティを上げる（サフィックスの付与などで書き込みを分散する）",
    "プロビジョニングされたキャパシティを増やし続ける",
    "テーブルを別リージョンにコピーする",
    "LSI を追加する"],
  answer:0,
  note:"DynamoDB のスループットはパーティション間で分割されるため、ホットキーがあると全体のキャパシティに余裕があってもスロットリングする（アダプティブキャパシティで緩和はされる）。\n読み取りの偏りなら DAX や DynamoDB Accelerator によるキャッシュも有効。書き込みの偏りはキー設計で分散するしかない。" },

{ id:"d2-24", dom:2, cat:"データベース",
  q:"DynamoDB の GSI（グローバルセカンダリインデックス）と LSI（ローカルセカンダリインデックス）の違いとして正しいものを2つ選んでください。",
  choices:[
    "LSI はテーブル作成時にしか作れず、パーティションキーはベーステーブルと同じでなければならない",
    "GSI は後から追加・削除でき、独自のキャパシティを持つ",
    "GSI は強い整合性のある読み取りをサポートする",
    "LSI は独自のパーティションキーを指定できる"],
  answer:[0,1],
  note:"LSI は同じパーティションキー＋異なるソートキーで、強整合の読み取りが可能。ただし作成時のみ、かつパーティションキーあたり 10GB の制限がある。\nGSI は任意のキーを持てて後から追加できるが、読み取りは結果整合のみ。GSI のキャパシティ不足はベーステーブルの書き込みスロットリングにつながる点も要注意。" },

{ id:"d2-25", dom:2, cat:"データベース",
  q:"ElastiCache の Redis（OSS 互換）と Memcached の選択で、Redis を選ぶべき要件はどれですか?",
  choices:[
    "永続化・レプリケーション・自動フェイルオーバー・ソート済みセットなどのデータ構造が必要",
    "純粋なキー・バリューのキャッシュを、マルチスレッドで単純にスケールさせたい",
    "ノードを水平にシャーディングして単純に容量を増やしたいだけ",
    "キャッシュの内容を失っても一切問題がない"],
  answer:0,
  note:"Memcached はマルチスレッドでシンプルなキャッシュ用途に強いが、永続化もレプリケーションもない。Redis はレプリカ・自動フェイルオーバー・スナップショット・Pub/Sub・Sorted Set・Streams など機能が豊富。\nセッションストアやリーダーボード、レートリミットのような用途は Redis 一択。" },

{ id:"d2-26", dom:2, cat:"ネットワーク",
  q:"CloudFront から S3 オリジンへのアクセスを、CloudFront 経由に限定したい。現在推奨される方式は?",
  choices:[
    "オリジンアクセスコントロール（OAC）を設定し、バケットポリシーで該当ディストリビューションからのアクセスのみ許可する",
    "バケットをパブリック読み取りにして、CloudFront の IP をセキュリティグループで許可する",
    "署名付き URL を全オブジェクトに発行する",
    "S3 の静的ウェブサイトホスティングを有効にする"],
  answer:0,
  note:"OAC は旧 OAI の後継で、SSE-KMS の暗号化オブジェクトや POST/PUT にも対応する。バケットは Block Public Access を有効のまま、バケットポリシーで AWS:SourceArn にディストリビューション ARN を指定する。\n利用者ごとのアクセス制限が必要な場合は、これに加えて署名付き URL/Cookie を使う。" },

{ id:"d2-27", dom:2, cat:"ネットワーク",
  q:"CloudFront で、リクエストごとに軽量な URL 書き換えとヘッダー操作を最小のレイテンシ・コストで行いたい。適したものは?",
  choices:[
    "CloudFront Functions（ビューアリクエスト/レスポンス、JavaScript、サブミリ秒）",
    "Lambda@Edge（オリジンリクエスト）",
    "オリジン側の ALB でルールを設定する",
    "S3 のリダイレクトルール"],
  answer:0,
  note:"CloudFront Functions はエッジロケーションで動く軽量な JS ランタイム。実行時間1ミリ秒未満、ネットワークアクセスやボディ操作は不可だが、非常に安くスケールする。\nネットワークアクセス、外部 SDK、レスポンスボディの生成が必要なら Lambda@Edge（リージョナルエッジキャッシュで動作、実行時間は長め）を使う。" },

{ id:"d2-28", dom:2, cat:"セキュリティ/コンプライアンス",
  q:"KMS のエンベロープ暗号化について正しい説明は?",
  choices:[
    "データはローカルで生成したデータキーで暗号化し、そのデータキー自体を KMS キーで暗号化して一緒に保存する",
    "大きなデータをそのまま KMS に送って暗号化してもらう",
    "KMS キーを二重に暗号化して保管する",
    "S3 のオブジェクトを2回暗号化する"],
  answer:0,
  note:"KMS で直接暗号化できるのは 4KB までなので、GenerateDataKey で平文と暗号文のデータキーを受け取り、平文キーでデータを暗号化してすぐ破棄、暗号化済みキーをデータと一緒に保存する。\n復号時は暗号化済みキーを KMS に送って平文キーを得る。S3 の SSE-KMS もこの仕組み。同一オブジェクトの大量アクセスには S3 バケットキーで KMS 呼び出しを削減できる。" },

{ id:"d2-29", dom:2, cat:"セキュリティ/コンプライアンス",
  q:"AWS Secrets Manager と Systems Manager Parameter Store（SecureString）の使い分けとして正しいものは?",
  choices:[
    "自動ローテーションと RDS などとの統合が必要なら Secrets Manager、単純な設定値・機密値の保管でコストを抑えたいなら Parameter Store",
    "Parameter Store は暗号化に対応していない",
    "Secrets Manager は無料で Parameter Store は有料",
    "Secrets Manager はクロスリージョンレプリケーションに対応していない"],
  answer:0,
  note:"Secrets Manager はシークレット単位の月額課金だが、Lambda によるローテーション、RDS/Redshift/DocumentDB とのネイティブ統合、クロスリージョンレプリケーションを持つ。\nParameter Store は標準パラメータが無料枠内で使え、KMS で SecureString を暗号化できる。ローテーションが不要な設定値はこちらで十分。" },

{ id:"d2-30", dom:2, cat:"データ分析",
  q:"数百のセンサーから毎秒大量のイベントが届きます。複数の異なるアプリが同じストリームを独立に読み、24時間以内なら再処理もしたい。適したサービスは?",
  choices:[
    "Amazon Kinesis Data Streams",
    "Amazon Kinesis Data Firehose",
    "Amazon SQS 標準キュー",
    "Amazon SNS"],
  answer:0,
  note:"Kinesis Data Streams はデータを保持（既定24時間、最大365日）し、複数のコンシューマーが同じレコードを独立したチェックポイントで読める。シャード単位で順序も保たれる。\nFirehose は S3/Redshift/OpenSearch へ届けるだけの完全マネージド配信で、再処理や複数独立コンシューマーには向かない。SQS はメッセージを読むと消えるため再処理に不向き。" },

{ id:"d2-31", dom:2, cat:"データ分析",
  q:"S3 のデータレイクに対して、サーバーを持たずに標準 SQL でアドホック分析を行いたい。適したサービスは?",
  choices:[
    "Amazon Athena（Glue データカタログでスキーマを管理）",
    "Amazon Redshift のプロビジョニングクラスター",
    "Amazon EMR の常時稼働クラスター",
    "Amazon RDS for PostgreSQL"],
  answer:0,
  note:"Athena はスキャンしたデータ量で課金されるサーバーレスクエリ。Parquet/ORC への列指向変換とパーティション分割でスキャン量＝コストを大幅に削減できる。\n継続的な大規模 BI で高い同時実行性能が要るなら Redshift、Spark/Hive の分散処理なら EMR。細かなアクセス制御には Lake Formation を重ねる。" },

{ id:"d2-32", dom:2, cat:"モダナイゼーション",
  q:"コンテナ化されたマイクロサービスを、サーバー管理なしで動かしたい。Kubernetes の API・エコシステムを使う必要は特にありません。最も運用が軽い選択は?",
  choices:[
    "Amazon ECS on AWS Fargate",
    "Amazon EKS on EC2 マネージドノードグループ",
    "EC2 上に自前で Kubernetes を構築する",
    "AWS Lambda にすべて移す"],
  answer:0,
  note:"Kubernetes の要件がないなら ECS + Fargate が最も運用が軽い（ノードのパッチもスケーリングも不要）。Kubernetes の資産・エコシステムが必要なら EKS、その場合も Fargate プロファイルでノード管理を減らせる。\nLambda は 15 分の実行時間上限やパッケージサイズの制約があり、常駐サービスの移行先としては前提条件を確認する必要がある。" },

{ id:"d2-33", dom:2, cat:"モダナイゼーション",
  q:"マルチテナント SaaS で、テナントごとの厳格なデータ分離とノイジーネイバー回避が最優先の金融顧客がいます。適したテナント分離モデルは?",
  choices:[
    "サイロモデル（テナントごとにリソースやアカウントを分離する）",
    "プールモデル（全テナントで同じリソースを共有する）",
    "ブリッジモデルのみを採用する",
    "テナント ID をアプリのコードでチェックするだけにする"],
  answer:0,
  note:"サイロは分離性が最も高いがコストと運用負荷も高い。プールは効率がよいがテナント間の影響とデータ漏えいリスクの管理が難しい。実際にはハイブリッド（層ごとに使い分ける）が多い。\nプールで運用する場合は、DynamoDB のリーディングキーへのテナント ID 埋め込みと、セッションポリシー/ABAC による動的なスコープ制限が定番。" },

{ id:"d2-34", dom:2, cat:"可用性/DR",
  q:"「RPO 5分・RTO 30分」という要件を、コストを抑えつつクロスリージョンで満たしたい。RDS for PostgreSQL を使っています。適した構成は?",
  choices:[
    "クロスリージョンのリードレプリカを維持し、災害時に昇格させる（Route 53 で切り替え）",
    "毎日1回の自動バックアップをクロスリージョンコピーする",
    "Multi-AZ 配置だけを有効にする",
    "マルチサイトアクティブ/アクティブ構成にする"],
  answer:0,
  note:"クロスリージョンリードレプリカは非同期レプリケーションで通常は数秒〜数分の遅延に収まり、昇格は数分。RPO 5分・RTO 30分の要件に合致し、マルチサイトより安い。\nMulti-AZ は同一リージョン内の可用性であってリージョン障害の DR にはならない。日次バックアップでは RPO 24時間になってしまう。" },

{ id:"d2-35", dom:2, cat:"可用性/DR",
  q:"アプリを「静的安定性（static stability）」の考え方で設計するとはどういうことですか?",
  choices:[
    "障害時にコントロールプレーンの操作（新規リソース作成など）に依存せず、あらかじめ確保した容量だけで動き続けられるようにする",
    "オートスケーリングを無効にして常に固定台数で運用する",
    "すべてのリソースを1つの AZ に集約する",
    "デプロイを月1回に制限する"],
  answer:0,
  note:"AZ 障害時に「残った AZ でスケールアウトする」設計は、そのとき API が混雑して起動できないリスクがある。3 AZ で必要台数の 150%（各 AZ 50%）を常時確保しておけば、1 AZ を失っても新規起動なしで耐えられる。\nMulti-AZ RDS のスタンバイや、事前プロビジョニング済みのウォームプールも同じ思想。" },

{ id:"d2-36", dom:2, cat:"ネットワーク",
  q:"Route 53 のルーティングポリシーで、「主系リージョンが健全なときだけそちらへ、ダウンしたら副系へ」を実現するものは?",
  choices:[
    "フェイルオーバールーティング（ヘルスチェックと組み合わせる）",
    "加重ルーティング",
    "レイテンシーベースルーティング",
    "地理的近接性ルーティング"],
  answer:0,
  note:"フェイルオーバーはプライマリ/セカンダリを定義し、ヘルスチェック失敗時にセカンダリへ切り替える。TTL を短くしておかないと切り替えが遅れる点に注意。\n加重はカナリアリリースやトラフィック分割、レイテンシーベースは最速リージョンへ、地理的近接性はバイアス付きで地理的に配分する。多値回答は簡易的な負荷分散＋ヘルスチェック。" },

{ id:"d2-38", dom:2, cat:"ストレージ",
  q:"EBS のボリュームタイプについて正しい説明を2つ選んでください。",
  choices:[
    "gp3 は容量とは独立に IOPS とスループットを設定でき、gp2 よりコスト効率がよいことが多い",
    "io2 Block Express は単一ボリュームで極めて高い IOPS と低レイテンシを提供し、ミッションクリティカルな DB 向け",
    "st1（スループット最適化 HDD）はランダム小 I/O のデータベース向けである",
    "インスタンスストアはインスタンスを停止しても内容が保持される"],
  answer:[0,1],
  note:"gp3 のベースラインは 3,000 IOPS・125 MB/s で、追加分を個別に購入できる。gp2 は容量に比例して IOPS が決まるため、小容量で高 IOPS が要る場合に無駄が出る。\nst1/sc1 はシーケンシャルな大容量スループット向け（ログ処理・ビッグデータ）でブートボリュームには使えない。インスタンスストアは揮発性で、停止・終了で内容が失われる。" },

{ id:"d2-39", dom:2, cat:"コンピュート",
  q:"ある企業が、既存の x86 ベースの Linux アプリのコストを 20% 以上削減したいと考えています。アプリはオープンソースのランタイム（Java, Python, Node.js）で動いています。最初に検討すべきは?",
  choices:[
    "AWS Graviton ベースのインスタンスへ移行し、価格性能比の改善を得る",
    "すべてのインスタンスを最小サイズにダウンサイジングする",
    "リージョンを最安のリージョンへ変更する",
    "オンデマンドからスポットへ全面移行する"],
  answer:0,
  note:"Graviton（Arm）は同等のオンデマンド価格に対して高い価格性能比を提供する。マネージドランタイムやコンテナで動くアプリなら移行コストは小さく、Lambda/Fargate/RDS/ElastiCache/OpenSearch でも選択できる。\nネイティブバイナリや商用ソフトの対応状況は事前確認が必要。まずはテスト環境でのビルドとベンチマークを行う。" },

{ id:"d2-40", dom:2, cat:"監視/運用自動化",
  q:"マイクロサービス構成でリクエストが複数サービスをまたぐようになり、レイテンシのボトルネックが分からなくなりました。適したサービスは?",
  choices:[
    "AWS X-Ray による分散トレーシング（サービスマップとトレースセグメント）",
    "CloudWatch Logs Insights でログを検索する",
    "VPC フローログを分析する",
    "CloudTrail のイベント履歴を確認する"],
  answer:0,
  note:"X-Ray はリクエストに一意のトレース ID を付与し、各サービスのセグメント/サブセグメントを収集してサービスマップとして可視化する。Lambda・API Gateway・ECS・SDK 計装で導入できる。\nCloudWatch との統合ビューが ServiceLens。ログ検索やフローログでは、サービスをまたぐ因果関係の追跡はできない。" },

{ id:"d2-41", dom:2, cat:"モダナイゼーション",
  q:"ファイルが S3 にアップロードされたら画像を変換し、失敗したら再試行してから通知する処理を、サーバーレスかつ疎結合に組みたい。適した構成は?",
  choices:[
    "S3 イベント通知 → EventBridge / SQS → Lambda（DLQ 付き）→ 失敗時 SNS 通知",
    "EC2 上の cron ジョブでバケットを5分おきにポーリングする",
    "S3 イベント通知から直接 SNS を呼び、SNS から SES でメールを送る",
    "Step Functions で S3 を1秒おきにポーリングする"],
  answer:0,
  note:"S3 イベントを直接 Lambda に渡す構成でも動くが、間に SQS を挟むとバースト吸収・リトライ・DLQ が使えて堅牢になる。EventBridge を使うとフィルタリングと多宛先配信ができる。\nポーリングはコストとレイテンシの両方で劣る。ポーリング構成が選択肢にある場合、SAP ではほぼ不正解と考えてよい。" },

{ id:"d2-42", dom:2, cat:"データベース",
  q:"開発環境のデータベースは平日の日中しか使わず、負荷も読めません。運用の手間なくコストを抑えたい。適した選択は?",
  choices:[
    "Aurora Serverless v2 で最小 ACU を小さく設定し、需要に応じて自動スケールさせる",
    "最大サイズの Aurora プロビジョンドインスタンスを常時稼働させる",
    "3年 RI を購入した RDS インスタンスを使う",
    "DynamoDB オンデマンドに移行する"],
  answer:0,
  note:"Aurora Serverless v2 は ACU 単位で秒単位に細かくスケールし、負荷が読めないワークロードや断続的な利用に向く。v1 と違い、スケーリング中に接続が切れない。\n開発環境ならインスタンスの自動停止（RDS の一時停止は最大7日）や、EventBridge Scheduler での夜間停止も選択肢になる。" },

{ id:"d2-43", dom:2, cat:"ネットワーク",
  q:"VPC 内の EC2 から S3 へ大量にデータを転送しています。NAT ゲートウェイのデータ処理料金が高額です。最も効果的な対策は?",
  choices:[
    "S3 用のゲートウェイ VPC エンドポイントを作成し、ルートテーブルに追加する",
    "NAT ゲートウェイを NAT インスタンスに置き換える",
    "S3 バケットを別リージョンに移す",
    "インターフェイス VPC エンドポイント（PrivateLink）を S3 用に作成する"],
  answer:0,
  note:"S3 と DynamoDB はゲートウェイ型 VPC エンドポイントに対応しており、こちらは利用料が無料。ルートテーブルにプレフィックスリスト経由の経路が追加され、NAT を通らなくなる。\nインターフェイス型（S3 にも存在する）は時間課金＋データ処理料金がかかるので、オンプレからのアクセスなど専用の要件がなければゲートウェイ型を選ぶ。" },

{ id:"d2-44", dom:2, cat:"可用性/DR",
  q:"ある社内システムが「AZ 全体の障害でも無停止」を要件としています。設計として不十分なものは?",
  choices:[
    "単一 AZ の Auto Scaling グループで、障害時に別 AZ へ手動で切り替える",
    "複数 AZ にまたがる Auto Scaling グループと ALB",
    "Multi-AZ 配置の RDS",
    "3 AZ に分散し、2 AZ 分の容量を常時確保する"],
  answer:0,
  note:"AZ 障害を「手動で切り替える」設計は無停止要件を満たさない。SAP では「自動でフェイルオーバーするか」「必要な容量が事前に確保されているか」の2点で判断する。\nステートを持つ層（RDS・ElastiCache・EFS）も個別に AZ 冗長化されているかを確認する。" },

{ id:"d2-45", dom:2, cat:"セキュリティ/コンプライアンス",
  q:"複数リージョンで同じ暗号化データを復号できるようにしたい（S3 の CRR で暗号化オブジェクトを複製する場合など）。適した KMS の機能は?",
  choices:[
    "マルチリージョンキー（同じキーマテリアルを複数リージョンにレプリケートする）",
    "各リージョンで別々のキーを作り、データを都度復号・再暗号化する",
    "KMS キーのエイリアスを共通にする",
    "CloudHSM クラスターをリージョン間で共有する"],
  answer:0,
  note:"マルチリージョンキーはプライマリキーとレプリカキーが同じキー ID・キーマテリアルを共有するため、あるリージョンで暗号化したデータを別リージョンでそのまま復号できる。\nただし各レプリカは独立したキーポリシーとグラントを持つ。マルチリージョンキーは「必要なときだけ」使うのが原則で、既定は単一リージョンキー。" },

{ id:"d2-46", dom:2, cat:"監視/運用自動化",
  q:"複数のメトリクスがすべて異常なときだけアラートを出し、単発のスパイクでは通知したくありません。適した機能は?",
  choices:[
    "CloudWatch の複合アラーム（Composite Alarm）",
    "CloudWatch の異常検出（Anomaly Detection）のみ",
    "CloudWatch Logs のメトリクスフィルター",
    "EventBridge のスケジュールルール"],
  answer:0,
  note:"複合アラームは複数のアラームを AND/OR/NOT で組み合わせ、アラートノイズを減らす。子アラームの通知を抑制する設定もできる。\n異常検出はメトリクスの通常範囲を学習してバンドを作る機能で、静的しきい値が決めにくい指標に有効。両者は併用できる。" },

{ id:"d2-47", dom:2, cat:"コスト最適化",
  q:"CloudFront を使ったウェブサイトで、S3 からのデータ転送コストを削減したい。最も効果が大きいのは?",
  choices:[
    "キャッシュヒット率を上げる（TTL を適切に設定し、キャッシュキーから不要なクエリ文字列・ヘッダー・Cookie を除く）",
    "S3 のストレージクラスを One Zone-IA にする",
    "CloudFront のディストリビューションを複数作る",
    "オリジンを別リージョンに移す"],
  answer:0,
  note:"CloudFront からオリジンへの転送（オリジンフェッチ）はキャッシュミス時に発生する。キャッシュキーを絞ればヒット率が上がり、オリジンへのリクエストとデータ転送が減る。\nさらに Origin Shield を有効にすると、複数のエッジからのオリジンフェッチが集約されて削減できる。S3→CloudFront のデータ転送自体は無料である点も押さえておく。" },

{ id:"d2-48", dom:2, cat:"ストレージ",
  q:"オンプレのバックアップソフトが仮想テープライブラリ（VTL）を前提としています。テープをクラウドに置き換えたい。適したものは?",
  choices:[
    "AWS Storage Gateway のテープゲートウェイ",
    "AWS Storage Gateway のファイルゲートウェイ",
    "AWS DataSync",
    "AWS Transfer Family"],
  answer:0,
  note:"テープゲートウェイは iSCSI VTL インターフェイスを提供し、仮想テープを S3 に保存、アーカイブすると Glacier Flexible/Deep Archive に移る。既存のバックアップソフトをそのまま使えるのが利点。\nファイルゲートウェイは NFS/SMB を S3 にマッピング、ボリュームゲートウェイは iSCSI ブロック、DataSync は一括・定期のデータ転送。" },

{ id:"d2-49", dom:2, cat:"モダナイゼーション",
  q:"GraphQL API をサーバーレスで提供し、複数のデータソース（DynamoDB・Lambda・RDS）を1つのスキーマに束ねたい。適したサービスは?",
  choices:[
    "AWS AppSync",
    "Amazon API Gateway REST API",
    "AWS Amplify Hosting",
    "Application Load Balancer"],
  answer:0,
  note:"AppSync はマネージド GraphQL サービスで、リゾルバーで複数データソースを束ね、WebSocket ベースのサブスクリプション（リアルタイム更新）も提供する。Cognito/IAM/API キー/Lambda オーソライザーで認可できる。\nREST でよいなら API Gateway、リアルタイム双方向通信だけなら API Gateway WebSocket API も選択肢。" },

{ id:"d2-50", dom:2, cat:"可用性/DR",
  q:"ある EC サイトが、セール時にトラフィックが平常時の 50 倍になります。DB の読み取りがボトルネックです。最小の変更で対応できる組み合わせを2つ選んでください。",
  choices:[
    "Aurora のリードレプリカを追加し、リーダーエンドポイントに読み取りを寄せる",
    "ElastiCache を導入して読み取りをキャッシュする",
    "テーブルを手動でシャーディングする",
    "RDS インスタンスのストレージを増やす"],
  answer:[0,1],
  note:"読み取り負荷はレプリカ追加とキャッシュで解く、が定石。Aurora は最大15のリードレプリカを持て、リーダーエンドポイントが自動で負荷分散する。Aurora Auto Scaling でレプリカ数を自動調整もできる。\nシャーディングはアプリ改修が大きく「最小の変更」に反しない。ストレージ容量は読み取りスループットのボトルネックではない。" },

/* =======================================================================
 * ドメイン3: 既存ソリューションの継続的な改善（25%）
 * ===================================================================== */

{ id:"d3-01", dom:3, cat:"コスト最適化",
  q:"数百台の EC2 が過剰スペックの疑いがあります。実際のメトリクスに基づいてサイズ変更の候補を提示してくれるサービスは?",
  choices:[
    "AWS Compute Optimizer",
    "AWS Config",
    "AWS Systems Manager Inventory",
    "Amazon CloudWatch の標準ダッシュボード"],
  answer:0,
  note:"Compute Optimizer は CloudWatch のメトリクス（および CloudWatch エージェントを入れればメモリも）を機械学習で分析し、EC2・Auto Scaling グループ・EBS・Lambda・ECS on Fargate・RDS の推奨サイズと想定削減額を出す。\nCost Explorer にもライトサイジングの推奨があり、こちらはコスト面からの提示。Trusted Advisor は使用率の低いインスタンスなど広く浅いチェック。" },

{ id:"d3-02", dom:3, cat:"監視/運用自動化",
  q:"EC2 のメモリ使用率とディスク使用率を CloudWatch で監視したい。必要な作業は?",
  choices:[
    "CloudWatch エージェントをインストール・設定してカスタムメトリクスとして送信する",
    "詳細モニタリングを有効にする",
    "EC2 の標準メトリクスにすでに含まれているので設定は不要",
    "VPC フローログを有効にする"],
  answer:0,
  note:"ハイパーバイザーから見える CPU・ネットワーク・ディスク I/O は標準メトリクスだが、OS 内部のメモリとファイルシステム使用率はゲスト OS にエージェントを入れないと取得できない。\n詳細モニタリングは標準メトリクスの粒度を5分から1分に上げるだけで、項目は増えない。SSM のディストリビューターとステートマネージャーでエージェントを一括配布・維持するのが定石。" },

{ id:"d3-03", dom:3, cat:"監視/運用自動化",
  q:"数百のアプリの CloudWatch Logs を、リアルタイムに近い形で中央の分析基盤（OpenSearch）へ送りたい。適した構成は?",
  choices:[
    "ロググループにサブスクリプションフィルターを設定し、Kinesis Data Firehose 経由で OpenSearch に配信する",
    "毎晩 CreateExportTask で S3 にエクスポートして取り込む",
    "Lambda で1分おきに FilterLogEvents を呼び出す",
    "CloudWatch ダッシュボードを共有する"],
  answer:0,
  note:"サブスクリプションフィルターはログイベントをほぼリアルタイムで Kinesis Data Streams / Firehose / Lambda に流せる。アカウントをまたぐ配信も可能（クロスアカウントのサブスクリプション）。\nエクスポートタスクはバッチ処理でリアルタイム性がなく、ポーリングはコストとレイテンシで劣る。" },

{ id:"d3-04", dom:3, cat:"監視/運用自動化",
  q:"「特定の顧客 ID だけレイテンシが悪化している」といった高カーディナリティの分析を、CloudWatch のログから行いたい。適したものは?",
  choices:[
    "CloudWatch Logs Insights のクエリと Contributor Insights のルール",
    "CloudWatch の標準メトリクスにディメンションとして顧客 ID を追加する",
    "CloudTrail のイベント履歴を検索する",
    "X-Ray のサービスマップを見る"],
  answer:0,
  note:"メトリクスのディメンションに高カーディナリティの値（顧客 ID など）を入れるとメトリクス数が爆発してコストが跳ね上がる。ログに構造化して出し、Logs Insights でクエリするか、Contributor Insights で上位寄与者をランキングするのが正しい。\n構造化ログからメトリクスも同時に出したい場合は埋め込みメトリクスフォーマット（EMF）を使う。" },

{ id:"d3-05", dom:3, cat:"監視/運用自動化",
  q:"数千台の EC2 に対して、OS パッチを定期的に適用し、コンプライアンス状況をレポートしたい。適したサービスは?",
  choices:[
    "AWS Systems Manager Patch Manager（パッチベースライン＋メンテナンスウィンドウ）",
    "AWS Inspector",
    "AWS Config",
    "EC2 Image Builder のみ"],
  answer:0,
  note:"Patch Manager はパッチベースラインで承認ルールを定義し、メンテナンスウィンドウやパッチポリシーで定期適用、Compliance でレポートする。\nInspector は脆弱性の検出（何を直すべきかの提示）で、適用そのものは行わない。Image Builder は「不変（イミュータブル）」なゴールデン AMI を作るアプローチで、Auto Scaling と組み合わせるならこちらが望ましい場合もある。" },

{ id:"d3-06", dom:3, cat:"監視/運用自動化",
  q:"監査上、EC2 への SSH 用踏み台サーバーと 22 番ポートの開放を廃止したい。運用を維持しつつ実現する方法は?",
  choices:[
    "Systems Manager Session Manager を使い、インバウンドポートを開けずにシェルアクセスを提供する（ログは CloudTrail / S3 / CloudWatch Logs に記録）",
    "EC2 Instance Connect で 22 番ポートを一時的に開放する",
    "VPN を導入して 22 番ポートを社内のみに制限する",
    "SSH 鍵をローテーションする"],
  answer:0,
  note:"Session Manager は SSM エージェントからのアウトバウンド接続で成立するため、インバウンドポートも踏み台も公開 IP も不要。プライベートサブネットからは VPC エンドポイント（ssm / ssmmessages / ec2messages）で完結できる。\nセッションログの記録とポリシーによる制御（誰がどのインスタンスに入れるか）も IAM で行える。" },

{ id:"d3-07", dom:3, cat:"監視/運用自動化",
  q:"AWS Config で「S3 バケットの暗号化が無効」を検出したときに、自動で暗号化を有効化したい。適した構成は?",
  choices:[
    "Config ルールに修復アクションとして SSM Automation ドキュメントを関連付ける",
    "Config のルール自体に修復のスクリプトを書く",
    "CloudTrail のイベントに Lambda を直接紐づける",
    "SCP でバケット作成を禁止する"],
  answer:0,
  note:"Config ルールは「修復アクション」に SSM Automation ドキュメント（AWS 管理のものかカスタム）を指定でき、自動修復または手動承認付き修復ができる。\nより柔軟な処理が必要なら、Config/Security Hub の検出結果を EventBridge で受けて Lambda を起動する構成にする。" },

{ id:"d3-08", dom:3, cat:"監視/運用自動化",
  q:"CloudFormation で管理しているスタックが、コンソールからの手動変更でテンプレートと食い違っていないか確認したい。使う機能は?",
  choices:[
    "ドリフト検出（Drift Detection）",
    "変更セット（Change Set）",
    "スタックポリシー",
    "スタックセット（StackSets）"],
  answer:0,
  note:"ドリフト検出は実リソースの現状とテンプレートの差分を報告する。手動変更を防ぎたいならスタックポリシーや IAM の Deny を併用する。\n変更セットは「デプロイ前に何が変わるか」を確認する機能で、目的が異なる。" },

{ id:"d3-09", dom:3, cat:"モダナイゼーション",
  q:"新バージョンを一部のユーザーにだけ流し、問題があれば即座に戻したい。ECS/Lambda で使える方式として適切なものを2つ選んでください。",
  choices:[
    "Lambda のエイリアスに加重（重み付け）を設定し、トラフィックを段階的に新バージョンへ移す",
    "CodeDeploy の Blue/Green デプロイで ALB のターゲットグループを切り替える",
    "Auto Scaling グループのインスタンスを一度に全台入れ替える",
    "DNS の TTL を1週間に設定して切り替える"],
  answer:[0,1],
  note:"Lambda はエイリアスの加重ルーティングでカナリアを実現でき、CodeDeploy と組み合わせれば CloudWatch アラームによる自動ロールバックも設定できる。\nECS/EC2 は CodeDeploy の Blue/Green でターゲットグループを切り替え、テストリスナーで検証してから本番リスナーを切り替える。DNS 切り替えは TTL のぶん切り戻しが遅く、カナリア制御に向かない。" },

{ id:"d3-10", dom:3, cat:"データベース",
  q:"本番の Aurora MySQL のエンジンをメジャーバージョンアップしたいが、ダウンタイムをほぼゼロにしたい。適した方法は?",
  choices:[
    "Amazon RDS/Aurora の Blue/Green デプロイを使い、同期された緑環境を用意してから切り替える",
    "メンテナンスウィンドウでインプレースアップグレードする",
    "スナップショットから新クラスターを復元して手動でデータを同期する",
    "リードレプリカを作成して昇格させる"],
  answer:0,
  note:"RDS/Aurora の Blue/Green デプロイは、本番（Blue）と論理レプリケーションで同期された Green 環境を作り、テスト後に通常1分程度で切り替える。切り替え時に書き込みは短時間停止するがエンドポイントは維持される。\nインプレースアップグレードは数分〜数十分のダウンタイムが発生する。" },

{ id:"d3-11", dom:3, cat:"データベース",
  q:"RDS の性能劣化の原因を、待機イベントや上位 SQL のレベルで特定したい。適した機能は?",
  choices:[
    "RDS Performance Insights",
    "CloudWatch の CPUUtilization メトリクス",
    "Enhanced Monitoring のみ",
    "AWS X-Ray"],
  answer:0,
  note:"Performance Insights は DB ロード（平均アクティブセッション）を待機イベント・SQL・ユーザー・ホスト別に分解して可視化する。ボトルネックが CPU なのか I/O なのかロック待ちなのかが一目で分かる。\nEnhanced Monitoring は OS レベルのプロセス/リソース情報で、SQL レベルの分析はできない。" },

{ id:"d3-12", dom:3, cat:"コスト最適化",
  q:"DynamoDB のテーブルが肥大化し、ストレージコストが増え続けています。古い項目は90日で不要になります。最も運用が軽い対策は?",
  choices:[
    "TTL 属性を設定し、期限切れ項目を自動削除する（必要ならストリーム経由で S3 にアーカイブする）",
    "Lambda を毎日実行して古い項目をスキャン・削除する",
    "テーブルを毎月作り直す",
    "オンデマンドキャパシティに切り替える"],
  answer:0,
  note:"TTL による削除は追加の書き込みキャパシティを消費せず無料。削除は DynamoDB Streams に DELETE として流れるので、Lambda でアーカイブしてから消すパターンが定番。\nスキャンによる削除は読み取り・書き込みキャパシティを大量に消費してコストが増える。" },

{ id:"d3-13", dom:3, cat:"コスト最適化",
  q:"S3 の請求が予想より高く、原因を特定したい。バケット横断で使用状況・ストレージクラス分布・不完全なマルチパートアップロードを可視化するのは?",
  choices:[
    "S3 Storage Lens",
    "S3 サーバーアクセスログ",
    "S3 インベントリのみ",
    "CloudWatch の BucketSizeBytes メトリクス"],
  answer:0,
  note:"Storage Lens は組織・アカウント・リージョン・バケット・プレフィックス単位でストレージの傾向とコスト最適化の推奨（未完了マルチパート、非現行バージョン、IA 候補など）をダッシュボード表示する。\n未完了のマルチパートアップロードは目に見えないまま課金され続けるので、ライフサイクルルールで自動中止・削除を設定するのが定石。" },

{ id:"d3-14", dom:3, cat:"コスト最適化",
  q:"開発・検証環境の EC2 と RDS を、平日の 20 時から翌 8 時まで自動停止してコストを下げたい。運用が軽い方法は?",
  choices:[
    "EventBridge Scheduler から SSM Automation または Lambda を呼び、タグの付いたリソースを一括で停止/起動する",
    "各インスタンスに cron を仕込んで自分自身を停止する",
    "リザーブドインスタンスを購入する",
    "毎日担当者が手動で停止する"],
  answer:0,
  note:"タグ（例: Schedule=dev）でスケジュール対象を選び、EventBridge Scheduler の cron 式で AWS-StopEC2Instance などの Automation を呼ぶのが定番。AWS の Instance Scheduler ソリューションもこの構成。\n停止中は EC2 のインスタンス時間課金と RDS のインスタンス課金が止まる（EBS/ストレージは課金継続）。RDS の停止は最大7日で自動再開する点に注意。" },

{ id:"d3-15", dom:3, cat:"コスト最適化",
  q:"Savings Plans と RI の「カバレッジ」と「使用率（Utilization）」の違いとして正しいものは?",
  choices:[
    "カバレッジは全使用量のうち割引が適用された割合、使用率は購入したコミットメントのうち実際に使われた割合",
    "カバレッジは購入額のうち使った割合、使用率は割引率のこと",
    "どちらも同じ指標の別名",
    "カバレッジは請求額、使用率は時間数を表す"],
  answer:0,
  note:"カバレッジが低い＝まだオンデマンドで払っている部分がある（買い増しの余地）。使用率が低い＝買いすぎて余らせている（無駄）。この2つを Cost Explorer のレポートで見ながら調整する。\nまず使用率 100% を保てる量までコミットし、そのうえでカバレッジを上げていくのが安全な進め方。" },

{ id:"d3-16", dom:3, cat:"ネットワーク",
  q:"EC2 から RDS に接続できません。セキュリティグループ・NACL・ルートテーブルのどこで止まっているかを、実際にパケットを流さずに特定したい。適したツールは?",
  choices:[
    "VPC Reachability Analyzer",
    "VPC フローログ",
    "AWS Network Manager",
    "Amazon Inspector"],
  answer:0,
  note:"Reachability Analyzer は送信元と宛先を指定すると、設定を静的に解析して到達可否と「どのコンポーネントでブロックされたか」を返す。実トラフィックは不要。\nフローログは実際に流れた（あるいは拒否された）トラフィックの記録で、事後分析向き。組織全体の意図しない到達性を検査したいなら Network Access Analyzer。" },

{ id:"d3-17", dom:3, cat:"可用性/DR",
  q:"本番システムが「AZ 障害に耐えられる」と設計上は言えますが、実際に確認したことがありません。安全に検証する方法は?",
  choices:[
    "AWS Fault Injection Service（FIS）で AZ 障害などの実験を、停止条件（ストップコンディション）付きで実行する",
    "本番の AZ のインスタンスを手動で全部停止してみる",
    "設計レビューだけで十分と判断する",
    "CloudWatch のアラームを増やす"],
  answer:0,
  note:"FIS はインスタンス停止・API エラー注入・ネットワーク断・AZ 障害シナリオなどをマネージドに実行でき、CloudWatch アラームを停止条件にして被害を限定できる。カオスエンジニアリングの実践手段。\nAWS Resilience Hub はアプリの RTO/RPO 目標に対する回復力を評価し、改善推奨と FIS 実験の提案までしてくれる。" },

{ id:"d3-18", dom:3, cat:"セキュリティ/コンプライアンス",
  q:"GuardDuty が「EC2 が既知の暗号通貨マイニングドメインと通信している」を検出したときに、自動で当該インスタンスを隔離したい。適した構成は?",
  choices:[
    "GuardDuty の検出結果を EventBridge で受け、Lambda / SSM Automation で隔離用セキュリティグループに付け替えてスナップショットを取得する",
    "GuardDuty の設定でインスタンスを自動終了させる",
    "CloudTrail のログを毎時ポーリングして判定する",
    "AWS Config ルールで検出する"],
  answer:0,
  note:"GuardDuty 自体に修復機能はなく、EventBridge を介した自動化が定石。隔離（すべてのトラフィックを拒否する SG に差し替え）→証跡保全（EBS スナップショット、メモリダンプ）→通知、の順で行う。\nいきなり終了させるとフォレンジックの証拠が消えるため、隔離が先。" },

{ id:"d3-19", dom:3, cat:"セキュリティ/コンプライアンス",
  q:"S3 に個人情報（PII）が意図せず保存されていないかを継続的に検査したい。適したサービスは?",
  choices:[
    "Amazon Macie",
    "Amazon Inspector",
    "AWS Config",
    "Amazon GuardDuty"],
  answer:0,
  note:"Macie は機械学習とパターンマッチで S3 内の機密データ（氏名・住所・クレジットカード番号・認証情報など）を検出し、バケットの公開状態や暗号化状況も評価する。\nInspector は EC2/ECR/Lambda の脆弱性、GuardDuty は脅威検知、Config は構成評価と、それぞれ守備範囲が違う。" },

{ id:"d3-20", dom:3, cat:"セキュリティ/コンプライアンス",
  q:"EC2 と コンテナイメージの CVE（既知の脆弱性）を継続的にスキャンしたい。適したサービスは?",
  choices:[
    "Amazon Inspector（EC2・ECR イメージ・Lambda を自動でスキャン）",
    "Amazon Macie",
    "AWS Trusted Advisor",
    "AWS Security Hub のみ"],
  answer:0,
  note:"Inspector は SSM エージェント経由で EC2 のパッケージを、ECR にプッシュされたイメージを、Lambda 関数とそのレイヤーを継続スキャンし、ネットワーク到達性も加味してリスクスコアを出す。\nSecurity Hub は Inspector・GuardDuty・Macie・Config などの検出結果を集約して標準（CIS/AWS 基礎セキュリティ）に照らすハブであり、スキャン自体は行わない。" },

{ id:"d3-21", dom:3, cat:"IAM/認証・認可",
  q:"長年運用してきたアカウントで、過剰な権限を持つ IAM ロールを整理したい。実際の使用状況に基づいて絞り込む方法は?",
  choices:[
    "IAM の「最終アクセス情報（Access Advisor）」と、CloudTrail から最小権限ポリシーを生成する IAM Access Analyzer のポリシー生成を使う",
    "全ロールをいったん削除して作り直す",
    "すべてのロールに ReadOnlyAccess を付け直す",
    "アクセス許可境界を全ロールに付ける"],
  answer:0,
  note:"Access Advisor は「そのプリンシパルが最後にどのサービスを使ったか」を示し、まったく使われていないサービスの許可を落とす根拠になる。Access Analyzer のポリシー生成は CloudTrail の履歴から実際に使われた API だけのポリシー案を作る。\n未使用のアクセスキーやロールの検出は、IAM Access Analyzer の未使用アクセス分析でも行える。" },

{ id:"d3-22", dom:3, cat:"ネットワーク",
  q:"CloudFront のオリジンが高負荷になっています。複数のエッジからのオリジンフェッチを集約してオリジン負荷を減らす機能は?",
  choices:[
    "Origin Shield",
    "Origin Access Control",
    "オリジンフェイルオーバー",
    "リアルタイムログ"],
  answer:0,
  note:"Origin Shield は指定リージョンに中央キャッシュ層を追加し、世界中のエッジからのミスをそこで束ねてオリジンへのリクエストを削減する。キャッシュヒット率が上がりオリジンのデータ転送も減る。\nオリジンフェイルオーバーはプライマリ障害時に別オリジンへ切り替える可用性の機能で、目的が違う。" },

{ id:"d3-23", dom:3, cat:"コンピュート",
  q:"Auto Scaling グループがスケールインの際に、処理中のジョブを持つインスタンスを終了させてしまいます。対策は?",
  choices:[
    "ライフサイクルフック（Terminating）を設定し、処理完了まで終了を待たせる（または処理をキューベースにして冪等にする）",
    "スケールインを完全に無効化する",
    "ヘルスチェックの猶予期間を延ばす",
    "終了ポリシーを OldestInstance にする"],
  answer:0,
  note:"ライフサイクルフックは Terminating:Wait 状態でインスタンスを保留し、その間にドレイン処理（ジョブの完了、ログの退避、接続の切断）を行える。既定のハートビートタイムアウトは1時間まで延長できる。\nそもそも SQS ベースのワーカーにして可視性タイムアウトで再配信されるようにすれば、途中終了しても安全になる。" },

{ id:"d3-24", dom:3, cat:"コンピュート",
  q:"ECS のローリング更新で不具合のあるタスク定義をデプロイし、サービスが全滅しかけました。再発防止に有効な設定は?",
  choices:[
    "デプロイサーキットブレーカーを有効にし、失敗を検知したら自動で前のバージョンにロールバックする",
    "希望タスク数を増やす",
    "デプロイの最小ヘルス率を 0% にする",
    "ヘルスチェックを無効にする"],
  answer:0,
  note:"ECS のデプロイサーキットブレーカーは、新しいタスクが安定して起動できない状態を検知してデプロイを停止し、ロールバックを有効にしていれば直前の安定したデプロイに戻す。\nより慎重にやるなら CodeDeploy の Blue/Green とアラームベースの自動ロールバックを組み合わせる。" },

{ id:"d3-25", dom:3, cat:"監視/運用自動化",
  q:"アラート疲れが起きています。夜間に鳴る通知の多くは自動復旧しており、対応不要でした。改善策として適切なものを2つ選んでください。",
  choices:[
    "アラームの評価期間とデータポイント数を調整し、一時的なスパイクで発報しないようにする",
    "複合アラームで「複数の症状が同時に出たとき」だけ発報するようにする",
    "しきい値を極端に高くしてアラームがほぼ鳴らないようにする",
    "すべてのアラームの通知先をメールからチャットに変える"],
  answer:[0,1],
  note:"「M 個中 N 個のデータポイントが違反したら」という評価設定と、複合アラームによる相関条件が、誤検知を減らす王道。あわせて、顧客影響を表す指標（SLI）でアラートし、原因系メトリクスはダッシュボードで見るという整理も有効。\nしきい値を上げるだけでは本当の障害も見逃す。通知先を変えても件数は減らない。" },

{ id:"d3-26", dom:3, cat:"可用性/DR",
  q:"既存の単一 AZ の RDS を、ダウンタイムを最小にして Multi-AZ に変更したい。正しい説明は?",
  choices:[
    "Multi-AZ への変更はオンラインで実行でき、スタンバイ作成中も稼働し続ける（短時間の性能低下は起こりうる）",
    "いったんスナップショットから新規に復元する以外に方法はない",
    "Multi-AZ にはデータ移行のため数時間の停止が必要",
    "Multi-AZ 化にはエンジンのバージョンアップが必須"],
  answer:0,
  note:"RDS の Multi-AZ 配置への変更は変更（modify）操作でオンラインに実施でき、内部でスナップショットを取ってスタンバイを作り同期する。その間 I/O 性能が一時的に落ちることがあるため、業務時間外に行うのが無難。\nMulti-AZ は同期レプリケーションによる可用性の仕組みで、読み取り負荷分散にはリードレプリカを使う。" },

{ id:"d3-27", dom:3, cat:"データベース",
  q:"レポート用の重いクエリが本番 DB の性能を圧迫しています。アプリ改修を最小限にする対策は?",
  choices:[
    "リードレプリカを作り、レポート用の接続先だけをレプリカのエンドポイントに向ける",
    "本番インスタンスのサイズを2倍にする",
    "レポートの実行を月1回に制限する",
    "本番テーブルにインデックスを大量に追加する"],
  answer:0,
  note:"読み取り専用ワークロードのオフロードはリードレプリカの典型的な用途。Aurora ならリーダーエンドポイントやカスタムエンドポイントでレポート専用のレプリカ群を切り出せる。\n分析クエリが本格的なら、S3 へのエクスポート＋Athena や Redshift へのゼロ ETL 統合も選択肢になる。" },

{ id:"d3-28", dom:3, cat:"ストレージ",
  q:"すでに数億オブジェクトある S3 バケットで、既存オブジェクトすべてに暗号化やタグ付け、別バケットへのコピーを一括適用したい。適した機能は?",
  choices:[
    "S3 バッチオペレーション（S3 インベントリのマニフェストを入力にする）",
    "S3 のライフサイクルルール",
    "Lambda で ListObjectsV2 を繰り返す自作スクリプト",
    "S3 レプリケーション"],
  answer:0,
  note:"S3 バッチオペレーションはインベントリレポートや CSV のマニフェストを入力に、コピー・タグ付け・ACL 変更・Object Lock 適用・Lambda 呼び出しなどを数十億オブジェクト規模で実行し、進捗と完了レポートを出す。\nレプリケーションは既定では新規オブジェクトのみ対象で、既存分には「既存オブジェクトのレプリケーション」を別途申請/設定する必要がある。" },

{ id:"d3-29", dom:3, cat:"コスト最適化",
  q:"リージョン間・AZ 間のデータ転送料金が膨らんでいます。まず確認すべきこととして適切なものを2つ選んでください。",
  choices:[
    "同一 AZ 内で完結できる通信が、AZ をまたいでいないか（クロスゾーン負荷分散やレプリカ配置を見直す）",
    "S3・DynamoDB 向け通信が NAT ゲートウェイを経由していないか（ゲートウェイ VPC エンドポイントに寄せる）",
    "EC2 のインスタンスタイプが最新世代かどうか",
    "S3 のバケット名が命名規則に沿っているか"],
  answer:[0,1],
  note:"データ転送コストの三大要因は、AZ 間通信、NAT ゲートウェイのデータ処理、インターネットへの下り。Cost Explorer で「使用タイプ」を DataTransfer で絞ると内訳が見える。\nVPC フローログを Athena で集計すると、どのリソース間の通信が多いかを特定できる。" },

{ id:"d3-30", dom:3, cat:"モダナイゼーション",
  q:"モノリシックなアプリの一部機能だけを段階的に切り出して新サービスへ置き換えたい。適したパターンは?",
  choices:[
    "ストラングラーフィグパターン（プロキシで新旧を振り分け、機能単位で徐々に移す）",
    "ビッグバン移行（一度にすべてを置き換える）",
    "データベースを先に分割してからアプリを分割する",
    "すべての機能を同時に Lambda 化する"],
  answer:0,
  note:"ストラングラーフィグは、既存システムの前段にファサード（ALB のルール、API Gateway、AWS Migration Hub Refactor Spaces など）を置き、移行済みの機能から順にルーティングを切り替える。リスクを小さく刻める。\nビッグバンは切り戻しが難しく、SAP では基本的に不正解の選択肢。" },

{ id:"d3-31", dom:3, cat:"監視/運用自動化",
  q:"複数アカウント・複数リージョンの CloudWatch メトリクスとダッシュボードを1か所で見たい。適した機能は?",
  choices:[
    "CloudWatch のクロスアカウント・クロスリージョンオブザーバビリティ（モニタリングアカウントとソースアカウントを設定する）",
    "各アカウントのダッシュボードのスクリーンショットを共有する",
    "メトリクスを Lambda で1つのアカウントに転送する",
    "CloudWatch Logs のエクスポートを使う"],
  answer:0,
  note:"CloudWatch のクロスアカウントオブザーバビリティは、モニタリングアカウントからソースアカウントのメトリクス・ログ・トレースを直接検索・可視化できる。Organizations と連携して一括リンクも可能。\n自前でメトリクスを転送する構成は、遅延・欠損・コストの問題を抱えやすい。" },

{ id:"d3-32", dom:3, cat:"可用性/DR",
  q:"DR 手順書はあるものの、実際に切り替えたことがなく RTO を満たせるか不安です。継続的改善として最も有効なのは?",
  choices:[
    "定期的な DR 訓練（ゲームデー）を計画し、実際のフェイルオーバーを実施して RTO/RPO を実測・記録する",
    "手順書のレビュー会を毎月開く",
    "DR 環境のインスタンスサイズを大きくする",
    "バックアップの保持期間を延ばす"],
  answer:0,
  note:"「テストされていない DR 手順は動かない」が前提。定期訓練で手順の陳腐化・権限の欠落・依存関係の見落としが表面化する。実測値を残して RTO/RPO の妥当性を継続的に検証する。\nRoute 53 ARC（Application Recovery Controller）のルーティングコントロールを使うと、フェイルオーバーの手動制御と準備状況チェックを仕組み化できる。" },

{ id:"d3-33", dom:3, cat:"コンピュート",
  q:"Lambda 関数のコールドスタートが、ユーザー体験に影響するレベルで発生しています。効果が期待できる対策を2つ選んでください。",
  choices:[
    "プロビジョニング済み同時実行数を設定し、必要な時間帯だけ Application Auto Scaling でスケジュールする",
    "デプロイパッケージを小さくし、初期化処理（SDK クライアント生成など）をハンドラー外に移す",
    "関数のタイムアウトを長くする",
    "関数を VPC に接続する"],
  answer:[0,1],
  note:"コールドスタートの主因はパッケージのロードとランタイム初期化。依存関係の削減、レイヤーの整理、初期化コードのハンドラー外移動（実行環境の再利用）で短縮できる。恒久的にゼロにしたいならプロビジョニング済み同時実行数。\nタイムアウト延長は無関係。VPC 接続は Hyperplane ENI により以前ほどの遅延はないが、短くはならない。" },

{ id:"d3-34", dom:3, cat:"データ分析",
  q:"Athena のクエリ料金が高騰しています。最も効果の大きい改善は?",
  choices:[
    "データを Parquet などの列指向形式に変換し、よく絞り込む列（日付など）でパーティション分割する",
    "クエリの同時実行数を減らす",
    "S3 バケットを別リージョンに移す",
    "Athena のワークグループを増やす"],
  answer:0,
  note:"Athena はスキャンしたバイト数で課金されるため、列指向フォーマット（必要な列だけ読む）＋パーティション（必要な範囲だけ読む）＋圧縮が三本柱。10分の1以下になることも珍しくない。\nワークグループはクエリごとのスキャン量上限やコスト配分に使えるが、それ自体が安くする仕組みではない。" },

{ id:"d3-35", dom:3, cat:"セキュリティ/コンプライアンス",
  q:"アプリのソースコードに DB パスワードがハードコードされていました。改善策として最も適切なのは?",
  choices:[
    "Secrets Manager に移し、実行ロール経由で取得して自動ローテーションを設定する（IAM データベース認証が使えるならそちらも検討）",
    "環境変数に平文で設定する",
    "パスワードを Base64 でエンコードしてコードに残す",
    "設定ファイルを .gitignore に追加する"],
  answer:0,
  note:"シークレットは「コードにもイメージにも平文の環境変数にも置かない」が原則。Secrets Manager なら KMS 暗号化・IAM による取得制御・自動ローテーション・CloudTrail 監査が揃う。\nRDS/Aurora なら IAM データベース認証にして、そもそもパスワードを持たない設計にできる場合もある。Base64 は暗号化ではない。" },

{ id:"d3-36", dom:3, cat:"ネットワーク",
  q:"ALB の背後の Web サーバーに、クライアントの本来の IP アドレスが届きません。確認すべきことは?",
  choices:[
    "X-Forwarded-For ヘッダーをアプリ/ログ形式で読み取っているか（ALB は L7 プロキシなので送信元 IP は ALB のものになる）",
    "NLB に変更しないと絶対に取得できない",
    "セキュリティグループの設定を見直す",
    "VPC フローログを有効にする"],
  answer:0,
  note:"ALB は接続を終端する L7 ロードバランサーなので、バックエンドから見た送信元は ALB の IP。クライアント IP は X-Forwarded-For ヘッダーで渡される。\nNLB は既定でクライアント IP を保持する（ターゲットタイプが instance/ip かでも挙動が異なる）。WAF のレート制限や地理的制限を使う場合も、この違いを理解しておく。" },

{ id:"d3-37", dom:3, cat:"コスト最適化",
  q:"CloudWatch のカスタムメトリクスとログの費用が急増しました。原因として確認すべきことを2つ選んでください。",
  choices:[
    "高カーディナリティのディメンション（リクエスト ID など）でメトリクスが大量に生成されていないか",
    "ロググループの保持期間が「無期限」のまま放置されていないか",
    "CloudWatch ダッシュボードの数が多すぎないか",
    "リージョンが us-east-1 でないこと"],
  answer:[0,1],
  note:"カスタムメトリクスはメトリクス数（ディメンションの組み合わせ）で課金されるため、一意性の高い値をディメンションにすると爆発する。ログは取り込み量と保管量の両方で課金され、保持期間が無期限だと保管料が積み上がる。\n改善策は、ログ保持期間の設定、不要なデバッグログの抑制、古いログの S3 へのエクスポート、EMF によるメトリクス設計の見直し。" },

{ id:"d3-38", dom:3, cat:"監視/運用自動化",
  q:"インフラを Terraform / CloudFormation で管理していますが、手動変更が後を絶ちません。ガバナンスを効かせる改善として適切なものを2つ選んでください。",
  choices:[
    "本番アカウントの人間による書き込み権限を絞り、変更はパイプライン（CI/CD）のロール経由に限定する",
    "CloudFormation のドリフト検出と Config ルールを定期実行し、逸脱を検知したら通知・修復する",
    "手動変更を見つけたら都度メールで注意する",
    "本番アカウントの管理者を1人に減らす"],
  answer:[0,1],
  note:"技術的に「手動変更ができない」状態を作るのが本筋。読み取りと緊急時のブレークグラス用ロール（使用時にアラート）だけを残し、通常変更はパイプラインに寄せる。\nそのうえで検知（ドリフト検出・Config）を重ねる。運用ルールの周知だけでは再発する。" },

{ id:"d3-39", dom:3, cat:"可用性/DR",
  q:"アプリのバックエンド API が、依存する外部サービスの遅延によって連鎖的に全体停止を起こしました。回復力を高めるパターンとして適切なものを2つ選んでください。",
  choices:[
    "タイムアウトを短く設定し、指数バックオフ＋ジッターでリトライする",
    "サーキットブレーカーを入れ、失敗が続く依存先への呼び出しを一時的に遮断してフォールバックを返す",
    "リトライ回数を無制限にする",
    "依存先の応答を待つスレッド数を無制限にする"],
  answer:[0,1],
  note:"適切なタイムアウト・バックオフ・ジッター・サーキットブレーカー・バルクヘッド（リソース隔離）が、連鎖障害を止める基本セット。AWS SDK にはバックオフ付きリトライが組み込まれている。\nリトライの無制限化やスレッドの無制限化は、むしろ障害を増幅させる（リトライストーム）。" },

{ id:"d3-40", dom:3, cat:"ストレージ",
  q:"EFS のコストが増えています。アクセス頻度の低いファイルが大半です。適した対策は?",
  choices:[
    "EFS のライフサイクル管理を有効にし、一定期間アクセスのないファイルを低頻度アクセス（IA）／アーカイブストレージクラスへ自動移行する",
    "EFS を EBS に置き換える",
    "スループットモードをプロビジョンドに変更する",
    "ファイルシステムを複数に分割する"],
  answer:0,
  note:"EFS のライフサイクル管理は、指定日数アクセスのないファイルを自動で IA / Archive クラスへ移す（アクセスされると Standard に戻す設定も可能）。保管料を大きく下げられるが、取り出し料金がかかる。\nスループットモードは性能の設定であり、ワークロード次第では Elastic モードのほうが安くなることもある。" },

{ id:"d3-41", dom:3, cat:"セキュリティ/コンプライアンス",
  q:"Security Hub の検出結果が数万件あり、優先順位が付けられません。改善策として適切なものを2つ選んでください。",
  choices:[
    "自動抑制ルール（オートメーションルール）で、既知の許容事項や重要度の低い検出結果を抑制・重要度変更する",
    "適用するセキュリティ標準を組織のポリシーに合わせて取捨選択し、不要なコントロールを無効化する",
    "Security Hub を無効化する",
    "すべての検出結果を手作業で1件ずつクローズする"],
  answer:[0,1],
  note:"Security Hub は AWS 基礎セキュリティのベストプラクティス、CIS、PCI DSS などの標準を選んで有効化でき、コントロール単位で無効化もできる。組織として許容する事項はオートメーションルールで抑制し、残ったものに集中する。\n運用として、重大度クリティカル/高だけを EventBridge で通知し、それ以外はダッシュボードで定期レビューという二段構えが現実的。" },

{ id:"d3-42", dom:3, cat:"コンピュート",
  q:"EKS クラスターで、ノードの空きが多いのにコストが下がりません。改善策として適切なものを2つ選んでください。",
  choices:[
    "Karpenter などのノードオートスケーラーで、Pod の要求に合ったサイズのノードを動的に起動・集約する",
    "Pod の resources.requests を実測値に基づいて適正化する（過大な requests は無駄な空き容量を生む）",
    "ノードのインスタンスタイプを一律で最大サイズにする",
    "Cluster Autoscaler を無効にする"],
  answer:[0,1],
  note:"Kubernetes のスケジューリングは requests に基づくため、requests が過大だとノードは空いて見えても新しい Pod を置けず、台数が増える。Vertical Pod Autoscaler の推奨や Compute Optimizer（ECS/EKS 向け）で実測に合わせる。\nKarpenter は Pod の要求から最適なインスタンスタイプを選んで起動し、断片化したノードを統合（consolidation）してコストを下げる。" },

{ id:"d3-43", dom:3, cat:"監視/運用自動化",
  q:"本番の障害対応で、毎回同じ調査手順を人が手で実行しています。改善として最も効果的なのは?",
  choices:[
    "Systems Manager Automation のランブックとして手順をコード化し、EventBridge やインシデント発生時に自動実行する",
    "手順書を Wiki に詳しく書く",
    "オンコール担当を増やす",
    "アラートのしきい値を下げて早く気づけるようにする"],
  answer:0,
  note:"「調査・復旧のコード化」は運用上の優秀性（Operational Excellence）の核心。SSM Automation ランブックは承認ステップや条件分岐も書け、AWS Systems Manager Incident Manager と組み合わせるとインシデント発生時に自動起動できる。\nドキュメント化だけでは実行の速さとばらつきの問題が残る。" },

/* =======================================================================
 * ドメイン4: ワークロードの移行とモダナイゼーション（20%）
 * ===================================================================== */

{ id:"d4-01", dom:4, cat:"移行",
  q:"移行の「7 つの R」のうち、OS やアプリを変更せずにそのままクラウドへ移す戦略はどれですか?",
  choices:[
    "リホスト（Rehost / lift and shift）",
    "リプラットフォーム（Replatform）",
    "リファクタリング（Refactor）",
    "リパーチェス（Repurchase）"],
  answer:0,
  note:"7 R は Rehost（そのまま移す）・Replatform（少し最適化。例: 自前 MySQL を RDS へ）・Repurchase（SaaS に置き換え）・Refactor/Rearchitect（作り直し）・Retire（廃止）・Retain（残す）・Relocate（ハイパーバイザー単位で移す）。\n大規模移行では「まずリホストで期限内に出し、あとで最適化する」判断がよく問われる。" },

{ id:"d4-02", dom:4, cat:"移行",
  q:"数千台のオンプレサーバーの構成・依存関係・使用状況を把握し、移行計画を立てたい。適したサービスは?",
  choices:[
    "AWS Application Discovery Service（エージェント／エージェントレスコレクター）と AWS Migration Hub",
    "AWS Config",
    "Amazon Inspector",
    "AWS Systems Manager Inventory"],
  answer:0,
  note:"Application Discovery Service は VMware 環境向けのエージェントレスコレクターと、OS 上で動くエージェントの2方式でサーバー情報・プロセス・ネットワーク接続を収集する。Migration Hub でアプリケーション単位にグルーピングして進捗を追跡する。\nコストの試算まで含めた評価には Migration Evaluator を使う。" },

{ id:"d4-03", dom:4, cat:"移行",
  q:"数百台の物理・仮想サーバーを、最小のダウンタイムで EC2 にリホストしたい。適したサービスは?",
  choices:[
    "AWS Application Migration Service（MGN）でブロックレベルの継続レプリケーションを行い、カットオーバー時にテスト済みのインスタンスへ切り替える",
    "各サーバーの AMI を手動で作成してコピーする",
    "AWS DataSync でファイルをコピーする",
    "AWS Snowball でディスクイメージを送る"],
  answer:0,
  note:"MGN はエージェントでブロックレベルの継続レプリケーションを行い、非破壊のテスト起動を何度でも実施でき、カットオーバーは分単位。旧 Server Migration Service（SMS）の後継で、AWS が推奨するリホストの標準ツール。\nDataSync はファイル転送、Snowball はネットワーク帯域が足りないときの物理搬送。" },

{ id:"d4-04", dom:4, cat:"移行",
  q:"Oracle データベースを Amazon Aurora PostgreSQL へ、ダウンタイムを最小にして移行したい。適した組み合わせは?",
  choices:[
    "AWS SCT（スキーマ変換）でスキーマとコードを変換し、AWS DMS のフルロード＋CDC で継続的にデータを同期してから切り替える",
    "AWS DMS のフルロードだけを実行して切り替える",
    "mysqldump でエクスポート・インポートする",
    "Snowball でデータを送る"],
  answer:0,
  note:"異種間（heterogeneous）移行は「スキーマ/ストアドプロシージャの変換は SCT、データの移送は DMS」が定石。DMS の CDC（変更データキャプチャ）でフルロード後の差分を追いかけ、遅延がゼロに近づいたところでアプリを切り替えるとダウンタイムが数分に収まる。\nDMS のデータ検証（validation）機能で移行後の整合性も確認する。" },

{ id:"d4-05", dom:4, cat:"移行",
  q:"500 TB のデータを、帯域 100 Mbps の回線しか持たない拠点から AWS へ移したい。適した方法は?",
  choices:[
    "AWS Snowball Edge を複数台使ってオフラインで搬送する",
    "AWS DataSync でインターネット経由で転送する",
    "S3 Transfer Acceleration でアップロードする",
    "Direct Connect を新規敷設してから転送する"],
  answer:0,
  note:"100 Mbps で 500 TB は理論値でも 460 日以上かかる。おおまかな目安として「1週間以上かかるならオフライン搬送を検討」と覚えておく。\nSnowball Edge Storage Optimized は 1 台あたり約 80 TB 使えるので、複数台を並行して使う。継続的に発生する差分は、初回搬送後に DataSync でオンライン同期するハイブリッドがよく使われる。" },

{ id:"d4-06", dom:4, cat:"移行",
  q:"オンプレの NFS 共有から Amazon EFS へ、定期的に増分同期しながら移行したい。適したサービスは?",
  choices:[
    "AWS DataSync",
    "AWS Storage Gateway（ファイルゲートウェイ）",
    "AWS Transfer Family",
    "rsync を cron で実行する"],
  answer:0,
  note:"DataSync は NFS/SMB/HDFS/S3/EFS/FSx 間の転送を高速・並列に行い、増分検出・整合性チェック・帯域制限・スケジュールをマネージドで提供する。専用エージェントを1台立てるだけで済む。\nファイルゲートウェイは「オンプレから S3 を共有として使い続ける」ハイブリッド運用、Transfer Family は外部パートナー向けの SFTP/FTPS エンドポイント。" },

{ id:"d4-07", dom:4, cat:"移行",
  q:"取引先が SFTP でファイルを送ってきます。オンプレの SFTP サーバーを廃止し、受信データを S3 に直接置きたい。適したサービスは?",
  choices:[
    "AWS Transfer Family（SFTP/FTPS/FTP、AS2）",
    "AWS DataSync",
    "Amazon AppFlow",
    "AWS Storage Gateway"],
  answer:0,
  note:"Transfer Family は SFTP/FTPS/FTP と AS2 のマネージドエンドポイントを提供し、バックエンドは S3 または EFS。ユーザー認証はサービス管理・AD・カスタム（Lambda/API Gateway）から選べる。\n取引先側のクライアント設定を変えずにサーバーをクラウド化できるのが利点。到着後の処理は S3 イベント→Lambda/Step Functions で自動化する。" },

{ id:"d4-08", dom:4, cat:"モダナイゼーション",
  q:"Java の古い .war アプリを、ソースを大きく書き換えずにコンテナ化したい。支援するツールは?",
  choices:[
    "AWS App2Container",
    "AWS Copilot",
    "AWS Proton",
    "AWS CodeBuild"],
  answer:0,
  note:"App2Container は稼働中の Java/.NET アプリを解析して Dockerfile・コンテナイメージ・ECS/EKS のデプロイ成果物（CloudFormation）を生成する。リプラットフォームの入口として使える。\nCopilot は ECS 向けの開発者体験を整える CLI、Proton はプラットフォームチームがテンプレートを提供する仕組み。" },

{ id:"d4-09", dom:4, cat:"モダナイゼーション",
  q:"Microsoft SQL Server のアプリを Aurora PostgreSQL に移したいが、アプリの T-SQL を書き換える工数を抑えたい。役立つ機能は?",
  choices:[
    "Babelfish for Aurora PostgreSQL（TDS プロトコルと T-SQL を理解するエンドポイント）",
    "RDS Custom for SQL Server",
    "Amazon RDS Proxy",
    "AWS Schema Conversion Tool だけを使う"],
  answer:0,
  note:"Babelfish は Aurora PostgreSQL に SQL Server 互換のエンドポイント（TDS）を追加し、既存の T-SQL とドライバーをおおむねそのまま使える。ライセンス費用の削減と改修工数の削減を同時に狙える。\n互換性は 100% ではないため、Babelfish Compass で事前に非互換箇所を評価する。データ移送は引き続き DMS を使う。" },

{ id:"d4-10", dom:4, cat:"移行",
  q:"オンプレの VMware / Hyper-V 上の仮想マシンを、災害復旧用に AWS へレプリケートしておきたい（普段は AWS 側で稼働させない）。適したサービスは?",
  choices:[
    "AWS Elastic Disaster Recovery（AWS DRS）",
    "AWS Application Migration Service（MGN）",
    "AWS Backup",
    "Amazon S3 のクロスリージョンレプリケーション"],
  answer:0,
  note:"DRS は MGN と同じ継続ブロックレプリケーション基盤を DR 用途に特化させたもので、低コストのステージング領域に複製し続け、災害時に EC2 として起動する（RPO は秒単位、RTO は分単位）。ドリル（訓練）起動も非破壊で行える。\nステージング領域は小さなインスタンスと安価なストレージで構成されるため、パイロットライトに近い費用で秒単位の RPO を得られるのが強み。常時同一構成を待機させるマルチサイトより大幅に安い。\nMGN は1回限りの移行、DRS は継続的な DR という使い分け。" },

{ id:"d4-11", dom:4, cat:"移行",
  q:"移行プロジェクトで、アプリごとの移行進捗を可視化し、複数の移行ツール（MGN・DMS など）の状況をまとめて追跡したい。適したサービスは?",
  choices:[
    "AWS Migration Hub",
    "AWS Systems Manager",
    "AWS Control Tower",
    "AWS Service Catalog"],
  answer:0,
  note:"Migration Hub は Application Discovery Service で収集した情報をアプリケーション単位にグルーピングし、MGN・DMS などの進捗を1画面で追跡する。ホームリージョンを1つ決めて使う。\nMigration Hub Refactor Spaces は、既存アプリの前段にルーティング基盤を作ってストラングラーパターンを実装しやすくするサービス。" },

{ id:"d4-12", dom:4, cat:"データベース",
  q:"自前運用の Apache Kafka クラスターを、運用負荷を下げつつ既存のプロデューサー/コンシューマーを変更せずに移したい。適した移行先は?",
  choices:[
    "Amazon MSK（マネージド Kafka。MirrorMaker2 で移行できる）",
    "Amazon Kinesis Data Streams",
    "Amazon SQS",
    "Amazon EventBridge"],
  answer:0,
  note:"MSK は Apache Kafka そのものを運用してくれるため、クライアントコードの変更が不要。移行は MirrorMaker2 でトピックを複製してから切り替えるのが定番。\nKinesis へ移すと API が異なるためアプリ改修が必要になる。新規開発でエコシステム依存がないなら Kinesis のほうが運用は軽い。" },

{ id:"d4-13", dom:4, cat:"データベース",
  q:"自前の Redis を移行します。キャッシュではなくプライマリデータストアとして使っており、データ損失が許されません。適した移行先は?",
  choices:[
    "Amazon MemoryDB（Multi-AZ トランザクションログにより耐久性がある）",
    "Amazon ElastiCache（Redis OSS 互換）",
    "Amazon DynamoDB",
    "Amazon DocumentDB"],
  answer:0,
  note:"ElastiCache はキャッシュ用途（スナップショットはあるが耐久性の保証は MemoryDB ほどではない）。MemoryDB は書き込みを Multi-AZ の分散トランザクションログに永続化するため、インメモリの速度を保ちつつ耐久性のあるプライマリ DB として使える。\n「Redis 互換 × データ損失不可」がキーワード。" },

{ id:"d4-14", dom:4, cat:"移行",
  q:"移行にあたり、Windows Server と SQL Server の既存ライセンスを持ち込みたい（BYOL）。専有ハードウェアが必要な場合に使うのは?",
  choices:[
    "EC2 Dedicated Hosts（物理ソケット/コア単位のライセンス条件に対応でき、AWS License Manager で追跡できる）",
    "EC2 Dedicated Instances",
    "オンデマンドインスタンス（ライセンス込み）",
    "Savings Plans"],
  answer:0,
  note:"Dedicated Hosts は物理サーバーそのものを占有し、ソケット数・物理コア数が見えるため、それらに紐づくライセンス条件（多くの Microsoft ライセンス）を満たせる。License Manager でライセンス数の上限管理と違反防止ができる。\nDedicated Instances は「他テナントと物理サーバーを共有しない」だけで、物理ソケット/コアの可視性は提供しない。" },

{ id:"d4-15", dom:4, cat:"モダナイゼーション",
  q:"社内の Windows ファイルサーバー群を AWS へ移し、既存の AD 認証と Windows ACL をそのまま使いたい。適した組み合わせは?",
  choices:[
    "Amazon FSx for Windows File Server へ AWS DataSync で移行し、既存 AD（または AWS Managed Microsoft AD の信頼）と統合する",
    "Amazon EFS に移行して SMB でマウントする",
    "Amazon S3 に移行してブラウザからアクセスする",
    "EC2 に Windows Server を立てて自前運用を続ける"],
  answer:0,
  note:"FSx for Windows はネイティブの SMB・NTFS ACL・DFS 名前空間・シャドウコピーに対応しており、ファイルサーバーの置き換え先として最も素直。バックアップも自動。\nEFS は NFS のみで Windows ACL に対応しない。EC2 での自前運用は運用負荷が残る。" },

{ id:"d4-16", dom:4, cat:"モダナイゼーション",
  q:"月末だけ実行される社内バッチを、EC2 常時稼働から移行してコストを下げたい。処理は最大3時間かかります。適した移行先は?",
  choices:[
    "AWS Batch（または ECS/Fargate のスケジュールタスク）で必要なときだけコンピュートを起動する",
    "AWS Lambda に移す",
    "EC2 をリザーブドインスタンスにする",
    "EC2 のインスタンスサイズを小さくする"],
  answer:0,
  note:"Lambda の最大実行時間は 15 分なので3時間のバッチは載らない。AWS Batch はジョブキューとコンピュート環境（Fargate/EC2/スポット）を管理し、実行時だけ課金される。\nStep Functions で分割して Lambda に載せる設計もあり得るが、まずは Batch/Fargate が素直。スポットを併用すればさらに安くなる。" },

{ id:"d4-17", dom:4, cat:"移行",
  q:"DMS でのデータベース移行中、大量のトランザクションが発生するテーブルで CDC の遅延が拡大しています。まず検討すべきことを2つ選んでください。",
  choices:[
    "レプリケーションインスタンスのサイズを上げる（CPU/メモリ/ネットワークがボトルネックのことが多い）",
    "移行タスクを分割し、大きなテーブルを別タスクにして並列度を上げる",
    "ソース DB のバックアップを停止する",
    "ターゲットを一時的に読み取り専用にする"],
  answer:[0,1],
  note:"CDC 遅延の典型的な原因はレプリケーションインスタンスの能力不足、ターゲット側の書き込み性能、単一タスクへの詰め込みすぎ。ターゲット側では移行中だけセカンダリインデックスや外部キー、トリガーを無効化して書き込みを速くするのも定番。\nDMS はフルロード中はターゲットの制約を無効化することを推奨している。" },

{ id:"d4-18", dom:4, cat:"モダナイゼーション",
  q:"モノリスを分割する際、まずどこから切り出すべきかの判断として最も適切なのは?",
  choices:[
    "変更頻度が高くビジネス価値が大きい、かつ依存関係が比較的疎な機能から切り出す",
    "コード量が最も多いモジュールから切り出す",
    "最も古いコードから切り出す",
    "データベーステーブルの多い機能から切り出す"],
  answer:0,
  note:"分割の目的は「変更のスピードを上げること」なので、変更頻度と価値が高く、境界が引きやすい部分（バウンデッドコンテキスト）から着手して早く効果を出す。\nコード量や古さは分割の優先順位の根拠にならない。データの分割が難しい部分は後回しにし、当面は共有 DB のまま API で隠すこともある。" },

{ id:"d4-19", dom:4, cat:"移行",
  q:"移行のカットオーバー計画で必ず用意すべきものとして、最も重要なのは?",
  choices:[
    "明確なロールバック手順と、切り戻しを判断する基準（判定時刻・成功条件）",
    "移行当日の作業者の人数",
    "移行後のコスト試算",
    "新環境の DNS 名の一覧"],
  answer:0,
  note:"カットオーバーは「進む」か「戻す」かを短時間で判断する必要がある。判定基準（このチェックが通らなければ何時までに切り戻す）と、実際に検証済みのロールバック手順がないと、判断が遅れて被害が広がる。\nDNS の TTL を事前に短くしておく、旧環境を一定期間残す、といった準備もセットで問われる。" },

{ id:"d4-20", dom:4, cat:"データ分析",
  q:"オンプレの Hadoop クラスターを AWS へ移行します。ストレージとコンピュートを分離してコストを下げたい。適した構成は?",
  choices:[
    "データを S3 に置き（EMRFS）、Amazon EMR のクラスターを処理時だけ起動する（EMR Serverless も選択肢）",
    "EC2 に HDFS を構築してそのまま移す",
    "すべてのデータを Redshift にロードする",
    "EBS に HDFS を作り、クラスターを常時稼働させる"],
  answer:0,
  note:"HDFS をそのまま持ち込むとストレージのためにクラスターを止められない。S3 をデータレイクにすればコンピュートを使うときだけ起動でき、複数のクラスター/エンジン（Spark・Hive・Presto・Athena）から同じデータを読める。\n一時的な中間データだけ HDFS/インスタンスストアに置くのが定石。スポットとインスタンスフリートでさらに安くできる。" },

{ id:"d4-21", dom:4, cat:"モダナイゼーション",
  q:"リフト＆シフトで移行した後、コスト削減効果が思ったより出ていません。次に取るべき最も効果的なステップは?",
  choices:[
    "ライトサイジングとマネージドサービスへの置き換え（自前 DB→RDS、自前ロードバランサ→ELB 等）を進め、Savings Plans でコミットする",
    "リージョンを変更する",
    "インスタンスをすべてスポットに変更する",
    "アカウントを分割する"],
  answer:0,
  note:"リホスト直後はオンプレのサイズをそのまま持ってきていることが多く、まずライトサイジング（Compute Optimizer）で無駄を削る。次に運用コストの大きい自前ミドルウェアをマネージドサービスへ寄せる。安定した使用量が見えてから Savings Plans を購入する、という順序が重要。\n先にコミットを買うと、最適化後に使用量が減って余らせる。" },

{ id:"d4-22", dom:4, cat:"移行",
  q:"移行期間中、オンプレと AWS の間で安定した帯域と低レイテンシが必要です。Direct Connect の敷設には数か月かかることが判明しました。当面の対応として適切なのは?",
  choices:[
    "Site-to-Site VPN で先に接続を開始し、Direct Connect 開通後に VPN をバックアップに回す",
    "移行を Direct Connect の開通まで延期する",
    "パブリックインターネット経由で暗号化せずに転送する",
    "Snowball だけで全データを運ぶ"],
  answer:0,
  note:"VPN は数分〜数時間で開通できるため、DX 待ちの繋ぎとして使うのが定番。DX 開通後は DX をプライマリ、VPN をバックアップにする構成（VPN over DX にすると暗号化も維持できる）へ移行する。\n複数の VPN トンネルや ECMP で帯域を稼ぐこともできる。" },

{ id:"d4-23", dom:4, cat:"コスト最適化",
  q:"移行後の実行環境として、EC2・Fargate・Lambda のどれを選ぶかを検討しています。コスト面の一般的な傾向として正しいのは?",
  choices:[
    "リクエストが断続的でアイドル時間が長いなら Lambda/Fargate が有利、高負荷が常時続くなら EC2（＋Savings Plans/スポット）が有利になりやすい",
    "常にサーバーレスのほうが安い",
    "常に EC2 のほうが安い",
    "Fargate は EC2 より必ず安い"],
  answer:0,
  note:"サーバーレスは「使った分だけ」なのでアイドルの多いワークロードに強く、逆に高稼働率が続くと単価の高さが効いてくる。運用工数まで含めた総コストで比較するのが正しい。\nSAP では「トラフィックが不定期」「夜間は使わない」といった記述がサーバーレス誘導のヒントになる。" },

{ id:"d4-24", dom:4, cat:"移行",
  q:"移行対象のアプリの中に、ライセンスやサポート契約の都合で当面オンプレに残すものがあります。7 R のどれに当たりますか?",
  choices:[
    "リテイン（Retain）",
    "リタイア（Retire）",
    "リロケート（Relocate）",
    "リパーチェス（Repurchase）"],
  answer:0,
  note:"Retain は「今は移さない」という積極的な判断。Retire は「そもそも使われていないので廃止する」で、実は移行案件で最もコスト効果が大きいことも多い。\n発見フェーズで使用実績のないサーバーを見つけて Retire に振り分けると、移行対象そのものが減る。" },

{ id:"d4-25", dom:4, cat:"モダナイゼーション",
  q:"既存の REST API サーバー（EC2）を、トラフィックの急変に強く運用の軽い構成へ変えたい。API のレスポンスは 100 ミリ秒程度で、認証は JWT です。適した移行先は?",
  choices:[
    "API Gateway（HTTP API）＋ Lambda、または ALB ＋ ECS on Fargate",
    "EC2 のインスタンスサイズを大きくする",
    "CloudFront のみを前段に置く",
    "Elastic Beanstalk の単一インスタンス環境"],
  answer:0,
  note:"短時間のリクエスト処理はサーバーレスに向く。HTTP API は JWT オーソライザーを標準で持つ。コンテナ資産があるなら ALB + Fargate も同等に有力で、どちらもスケーリングとパッチ管理から解放される。\nキャッシュ可能な GET が多いなら CloudFront を前段に足すのは有効だが、それ「だけ」ではスケーリングの問題は解決しない。" },

{ id:"d4-26", dom:4, cat:"移行",
  q:"DMS のフルロードが完了した後、ソースとターゲットのデータが一致しているかを確認したい。適した方法は?",
  choices:[
    "DMS のデータ検証（Data Validation）を有効にし、行単位の比較レポートを確認する",
    "両方のテーブルの行数だけを比較する",
    "アプリを切り替えてから利用者の報告を待つ",
    "ターゲットのスナップショットを取得する"],
  answer:0,
  note:"DMS のデータ検証は移行タスクの設定で有効化でき、行を継続的に比較して不一致を検証テーブルに記録する。CDC 中も動作する。\n行数比較だけでは値の欠損や文字コード・型変換の問題を見逃す。異種間移行では特に日付・数値精度・文字セットの差異が問題になりやすい。" },

{ id:"d4-27", dom:4, cat:"モダナイゼーション",
  q:"移行にあわせてイベント駆動アーキテクチャへ変えたい。既存の SaaS（例: Salesforce、Zendesk）のデータを、コードをほとんど書かずに AWS へ取り込みたい。適したサービスは?",
  choices:[
    "Amazon AppFlow",
    "AWS Glue のみ",
    "AWS DataSync",
    "AWS Transfer Family"],
  answer:0,
  note:"AppFlow は SaaS と AWS（S3・Redshift など）の間で、認証・マッピング・フィルタ・スケジュール/イベント起動をノーコードで構成できるデータ統合サービス。\nEventBridge のパートナーイベントソースを使えば、SaaS のイベントを直接イベントバスで受けることもできる。" },

{ id:"d4-29", dom:4, cat:"移行",
  q:"移行の初期段階で、経営層に対して「AWS に移すとどれくらい安くなるか」を示す必要があります。適したものは?",
  choices:[
    "Migration Evaluator（旧 TSO Logic）でオンプレの実使用状況を収集し、AWS でのコスト試算とビジネスケースを作る",
    "AWS Pricing Calculator に希望のインスタンスを入力する",
    "Cost Explorer の予測機能を使う",
    "Trusted Advisor のコストチェックを実行する"],
  answer:0,
  note:"Migration Evaluator は実際のサーバー使用状況（CPU・メモリ・稼働時間）とライセンス情報を収集し、ライトサイジング済みの現実的な試算とビジネスケースを提示する。\nPricing Calculator は前提を人が入力する必要があり、Cost Explorer と Trusted Advisor は既に AWS 上にあるリソースが対象で、移行前の評価には使えない。" },

{ id:"d4-30", dom:4, cat:"移行",
  q:"AWS へ移行した後も、一部のデータをオンプレのアプリから低レイテンシで参照する必要があります。データの正本は S3 に置きたい。適したものは?",
  choices:[
    "S3 File Gateway をオンプレに配置し、NFS/SMB で S3 をマウントしつつローカルキャッシュを効かせる",
    "オンプレから毎回 S3 API を直接呼び出す",
    "S3 の内容を毎晩オンプレにフルコピーする",
    "オンプレに Snowball Edge を常設する"],
  answer:0,
  note:"File Gateway は最近使ったデータをローカルにキャッシュしつつ、正本を S3 に置くハイブリッド構成を実現する。既存アプリはファイル共有として扱えるので改修が不要。\nフルコピーは帯域と鮮度の両面で不利。Snowball は一時的な搬送用途で常設するものではない。" },

{ id:"d4-31", dom:4, cat:"コンピュート",
  q:"オンプレの VMware 仮想マシンのイメージを、AWS 上で AMI として使いたい（1回限りの持ち込み）。適したものは?",
  choices:[
    "VM Import/Export で OVA/VMDK/VHD をインポートして AMI 化する",
    "AWS Application Migration Service（MGN）を使う",
    "AWS Backup でリストアする",
    "EC2 Image Builder でビルドする"],
  answer:0,
  note:"VM Import/Export は仮想マシンイメージファイルを S3 経由で取り込み AMI にする。ゴールデンイメージの持ち込みなど、1回限りの静的なインポートに向く。\n稼働中サーバーを最小ダウンタイムで移すなら MGN（継続レプリケーション）のほうが適切。両者の使い分けが問われる。" },

{ id:"d4-32", dom:4, cat:"モダナイゼーション",
  q:"移行後、複数のマイクロサービス間で同期呼び出しが連鎖し、1つの障害が全体に波及します。アーキテクチャ上の改善として最も適切なのは?",
  choices:[
    "同期呼び出しを、キュー/イベント（SQS・EventBridge）を介した非同期の疎結合に置き換えられる箇所を洗い出して変更する",
    "すべてのサービスを1つのモノリスに戻す",
    "各サービスのインスタンス数を増やす",
    "タイムアウトを長くする"],
  answer:0,
  note:"「即座に結果が要らない処理」を非同期化すると、下流が落ちてもメッセージがキューに溜まるだけで上流は動き続けられる（バッファリング）。あわせてサーキットブレーカーとフォールバックを入れる。\nタイムアウトを長くすると、むしろリソースが詰まって障害が拡大する。" },

{ id:"d4-33", dom:4, cat:"セキュリティ/コンプライアンス",
  q:"移行後もオンプレと同じセキュリティ基準を満たす必要があります。データの保存先はすべて暗号化し、鍵は自社が管理する HSM で保持するという要件があります。適したのは?",
  choices:[
    "AWS CloudHSM でキーを保持し、KMS のカスタムキーストアとして連携させる",
    "KMS の AWS 管理キーをそのまま使う",
    "アプリ側で独自に暗号化してキーをコードに埋め込む",
    "S3 のデフォルト暗号化（SSE-S3）を使う"],
  answer:0,
  note:"CloudHSM は FIPS 140-2 レベル3 の専有 HSM で、AWS がキーマテリアルに触れない。KMS のカスタムキーストアとして構成すれば、KMS 統合サービス（S3・EBS・RDS など）を使いながら実際の鍵は CloudHSM に置ける。\n「自社が鍵を完全に管理」「AWS も鍵にアクセスできない」という要件が出たら CloudHSM または外部キーストア。" },

{ id:"d4-34", dom:4, cat:"移行",
  q:"大規模移行を数百アプリ規模で進めます。移行の「波（ウェーブ）」を設計するうえで最も重要な観点は?",
  choices:[
    "アプリ間の依存関係を把握し、密に通信するアプリを同じ波でまとめて移す",
    "アルファベット順にアプリを並べる",
    "コストの高いアプリから順に移す",
    "1つの波にできるだけ多くのアプリを詰め込む"],
  answer:0,
  note:"依存し合うアプリを別々の波に分けると、移行期間中ずっとオンプレと AWS の間を通信が往復し、レイテンシ・帯域・コストの問題が出る（いわゆるスパゲッティ状態）。Application Discovery Service のネットワーク接続データで依存を可視化して波を切る。\n最初の波は依存が少なく影響の小さいアプリを選び、手順を確立してから規模を広げる。" },

/* =======================================================================
 * 公式試験ガイド（SAP-C02）のタスクステートメントと突き合わせて
 * 手薄だった論点の補充。id は d1-46〜 / d2-51〜 / d3-44〜 / d4-35〜 で継続。
 * 「生成AI(新領域)」カテゴリは試験ガイドの Emerging Topics に対応する
 *（AWS は現時点で採点対象外の pretest 問題として出題されうると明記している）。
 * ===================================================================== */

{ id:"d1-46", dom:1, cat:"セキュリティ/コンプライアンス",
  q:"CloudFront ディストリビューションに独自ドメインの HTTPS 証明書を設定しようとしたところ、ACM で発行した証明書が選択肢に出てきません。原因として最も可能性が高いのは?",
  choices:[
    "証明書を us-east-1（バージニア北部）以外のリージョンで発行しているため",
    "証明書の検証方法に DNS 検証を使っているため",
    "証明書がワイルドカード証明書であるため",
    "CloudFront では ACM の証明書を使えないため"],
  answer:0,
  note:"CloudFront に関連付ける ACM 証明書は必ず us-east-1 で発行・インポートする必要がある（CloudFront がグローバルサービスで、コントロールプレーンが us-east-1 にあるため）。ALB など各リージョンのリソースには、そのリージョンの証明書を使う。\nまた ACM のパブリック証明書は DNS 検証にしておくと自動更新される（Eメール検証だと更新のたびに手動対応が要る）。社内向けのプライベート証明書は AWS Private CA で発行する。" },

{ id:"d1-47", dom:1, cat:"ハイブリッド接続",
  q:"工場内の製造ラインを制御するアプリを AWS のサービスとして動かしたいが、ラインとの通信に一桁ミリ秒のレイテンシが必要で、かつ通信断が起きても工場内で処理を継続する必要があります。適したものは?",
  choices:[
    "AWS Outposts をオンプレミスのデータセンターに設置する",
    "AWS Local Zones を利用する",
    "AWS Wavelength を利用する",
    "最寄りリージョンのマルチ AZ 構成にする"],
  answer:0,
  note:"Outposts は AWS が管理するラックを自社の建屋に設置し、その上で EC2/EBS/ECS などをローカルに動かす。「AWS 側との通信が切れてもローカルで動き続ける」「データを敷地内から出せない」といった要件を満たせるのは Outposts だけ。\nLocal Zones は大都市圏に置かれた AWS 側の拠点で、数ミリ秒のレイテンシを狙うが自社建屋ではない。Wavelength は通信事業者の 5G ネットワーク内にあり、モバイル端末向け。3つの使い分けは頻出。" },

{ id:"d1-48", dom:1, cat:"ネットワーク",
  q:"EKS クラスターで Pod 数を増やしたところ「IP アドレスが割り当てられない」というエラーで Pod が起動しなくなりました。VPC CNI を使っています。対策として適切なものを2つ選んでください。",
  choices:[
    "VPC にセカンダリ CIDR（100.64.0.0/10 などの CG-NAT 範囲）を追加し、カスタムネットワーキングで Pod をそちらのサブネットに配置する",
    "プレフィックス委任（prefix delegation）を有効にして、ENI あたりに割り当てられる IP 数を増やす",
    "Pod の resources.limits を引き上げる",
    "ノードのインスタンスタイプを CPU の多いものに変更する"],
  answer:[0,1],
  note:"EKS の VPC CNI は Pod に VPC の実 IP を直接割り当てるため、サブネットの IP が枯渇すると Pod が起動できなくなる。ECS の awsvpc モードもタスクごとに ENI と IP を消費するので同じ問題が起きる。\n対策は「IP を増やす」（セカンダリ CIDR ＋カスタムネットワーキング）か「1 ENI あたりの IP 密度を上げる」（プレフィックス委任）。CPU/メモリの設定は IP 枯渇とは無関係。マルチアカウントでは IPAM で CIDR を計画的に配ることも重要。" },

{ id:"d1-49", dom:1, cat:"コスト最適化",
  q:"全リソースに Project タグを付け終えたので、Cost Explorer で Project 別のコストを見ようとしたところ、Project がディメンションに現れません。さらに、有効化した後も過去分のコストが Project 別に分かれませんでした。理由として正しいものは?",
  choices:[
    "ユーザー定義のコスト配分タグは請求コンソールで個別に有効化する必要があり、有効化した時点以降のコストにしか適用されない（遡及しない）",
    "コスト配分タグは AWS 生成タグしか使えない",
    "Cost Explorer はタグに対応していないので Cost and Usage Report を使う必要がある",
    "タグを付けてから24時間以内はコストが表示されない仕様のため"],
  answer:0,
  note:"タグを付けただけではコスト配分に使えない。管理アカウントの請求コンソールで「コスト配分タグ」としてキーを有効化する必要があり、有効化は遡及適用されない。だからタグ設計は「使い始める前」に決めておく必要がある。\nタグ付け漏れを防ぐには SCP の aws:RequestTag 条件で必須化し、既存リソースはタグエディタで一括付与する。アカウント自体をまたぐ集計には Cost Categories を併用する。" },

{ id:"d1-50", dom:1, cat:"監視/運用自動化",
  q:"組織内の各メンバーアカウントで発生した特定のイベント（例: ルートユーザーのログイン）を、中央のセキュリティアカウントに集めて一括処理したい。適した構成は?",
  choices:[
    "各アカウントの EventBridge ルールのターゲットに、中央アカウントのイベントバスを指定して転送する（中央側でリソースポリシーにより組織からの PutEvents を許可）",
    "各アカウントで Lambda を動かし、中央アカウントの API を独自に呼び出す",
    "各アカウントの CloudTrail ログを毎晩まとめてコピーし、バッチで解析する",
    "中央アカウントから各アカウントのイベントバスを定期的にポーリングする"],
  answer:0,
  note:"EventBridge はイベントバスをクロスアカウント／クロスリージョンのターゲットにできる。中央バスのリソースポリシーで aws:PrincipalOrgID を条件に PutEvents を許可すれば、組織内の全アカウントから安全に集約できる。\nStackSets でこの転送ルールを全アカウントへ自動展開するのが定番。EventBridge にポーリングの概念はない。" },

{ id:"d1-51", dom:1, cat:"生成AI(新領域)",
  q:"社内向けの生成AI アシスタントを Amazon Bedrock で構築します。規制対応として、特定の話題への回答拒否、不適切表現のフィルタ、個人情報のマスキング、モデルが根拠のない内容を答えていないかの検査を、アプリ側の実装に頼らず一元的に適用したい。適したものは?",
  choices:[
    "Amazon Bedrock Guardrails をモデル呼び出しに適用する",
    "IAM ポリシーで特定のプロンプトを拒否する",
    "AWS WAF のマネージドルールをモデルエンドポイントに適用する",
    "Amazon Macie でプロンプトをスキャンする"],
  answer:0,
  note:"Bedrock Guardrails は拒否トピック、単語・コンテンツフィルタ、機密情報（PII）のマスキング/ブロック、コンテキスト接地チェック（ハルシネーション検出）をモデル非依存に適用でき、複数アプリで同じガードレールを再利用できる。\nこれは公式試験ガイドの Emerging Topics「Design security and responsible AI controls」に対応する領域。IAM はプロンプト内容を判断できず、WAF は HTTP レイヤ、Macie は S3 のデータ検出で、いずれも役割が違う。" },

{ id:"d2-51", dom:2, cat:"監視/運用自動化",
  q:"CloudFormation テンプレートが 3,000 行を超え、更新のたびに影響範囲が読めなくなっています。ネットワーク層は複数のアプリスタックから参照されます。適した分割方法は?",
  choices:[
    "ネットワーク層を独立したスタックにして Export し、アプリスタックから Fn::ImportValue で参照する（共通部品はネストスタックとして切り出す）",
    "1つのテンプレートのままリソースに DependsOn を追加する",
    "スタックを分けたうえで、値はすべて手作業でパラメータに転記する",
    "テンプレートを JSON から YAML に書き換える"],
  answer:0,
  note:"ライフサイクルの違う層はスタックを分けるのが原則。他スタックから参照する値は Export/ImportValue、再利用したい部品はネストスタックにする。\n注意点として、Export された値は他スタックから Import されている間は変更も削除もできない。頻繁に変わる値は Export ではなく SSM パラメータストア経由で渡すほうが柔軟。更新前は必ず変更セットで差分を確認する。" },

{ id:"d2-52", dom:2, cat:"モダナイゼーション",
  q:"本番デプロイのパイプラインに、(1) 承認者の明示的な承認を経てから本番に進む、(2) 失敗時に自動で切り戻す、という要件があります。AWS のマネージドサービスで組む構成として適切なものを2つ選んでください。",
  choices:[
    "CodePipeline に手動承認アクションを挟み、承認されるまで本番ステージに進まないようにする",
    "デプロイに CodeDeploy を使い、CloudWatch アラームと関連付けて失敗時の自動ロールバックを有効にする",
    "パイプラインの最後に管理者へメールを送り、問題があれば手動で前のバージョンを再デプロイしてもらう",
    "本番ステージだけパイプラインを分け、担当者が手元から直接デプロイする"],
  answer:[0,1],
  note:"CodePipeline の手動承認アクションは SNS 通知つきでパイプラインを一時停止し、承認・却下を記録として残せる。CodeDeploy はデプロイ中に指定した CloudWatch アラームが発報すると自動でロールバックする（デプロイ失敗時のロールバックも設定可能）。\n「人が気づいて手で戻す」構成は MTTR が読めず、SAP では不正解になりやすい。自動化された検知とロールバックがあるかで判断する。" },

{ id:"d2-53", dom:2, cat:"データベース",
  q:"次の4つのワークロードに対して、最も適した AWS のデータベースの組み合わせはどれですか。(1) SNS の友達関係をたどる検索、(2) IoT センサーの時系列データ、(3) 既存の Cassandra アプリ、(4) 既存の MongoDB アプリ",
  choices:[
    "(1) Neptune、(2) Timestream、(3) Keyspaces、(4) DocumentDB",
    "(1) DynamoDB、(2) RDS、(3) Neptune、(4) Keyspaces",
    "(1) DocumentDB、(2) Neptune、(3) Timestream、(4) Keyspaces",
    "すべて Aurora PostgreSQL で実装する"],
  answer:0,
  note:"SAP は「目的別データベース（purpose-built database）」の選定が頻出。Neptune＝グラフ（関係をたどる）、Timestream＝時系列、Keyspaces＝Apache Cassandra 互換、DocumentDB＝MongoDB 互換、ElastiCache/MemoryDB＝インメモリ、DynamoDB＝キーバリュー/ドキュメント、Redshift＝データウェアハウス、OpenSearch＝全文検索とログ分析。\n「既存の◯◯互換」というキーワードが出たら、アプリ改修を避けられる互換サービスを選ぶ。" },

{ id:"d2-54", dom:2, cat:"可用性/DR",
  q:"新規サービスの負荷試験中、想定台数まで EC2 をスケールできず起動が失敗しました。原因はアカウントのサービス上限でした。本番稼働に向けた対策として適切なものを2つ選んでください。",
  choices:[
    "Service Quotas でクォータ使用率の CloudWatch アラームを設定し、上限に近づいたら通知されるようにする",
    "必要なクォータの引き上げを事前に申請し、Organizations のクォータリクエストテンプレートで新規アカウントにも自動適用する",
    "起動に失敗したらリトライし続けるようアプリを改修する",
    "クォータは自動的に拡張されるため、対応は不要である"],
  answer:[0,1],
  note:"サービスクォータはアカウント×リージョン単位で、多くは調整可能だが即時ではないので事前申請が要る。Service Quotas はクォータ使用率をメトリクスとして出せるので、CloudWatch アラームで枯渇の前に気づける。\nOrganizations と統合したクォータリクエストテンプレートを使うと、新規アカウント作成時に必要な引き上げが自動で申請される。SAP では「アカウント分割の理由」「DR リージョンでも同じ上限を確保できているか」という文脈でも問われる。" },

{ id:"d2-55", dom:2, cat:"生成AI(新領域)",
  q:"社内の生成AI エージェントが、ユーザーの代理で外部 SaaS の API を呼び出します。エージェントに広い権限を持たせず、呼び出し元ユーザーの同一性と権限に紐づけて外部リソースへアクセスさせたい。試験ガイドが例に挙げている仕組みは?",
  choices:[
    "AgentCore Identity でエージェントの ID と、ユーザーに代わった外部リソースへのアクセスを管理する",
    "エージェント用の IAM ユーザーを作り、アクセスキーを埋め込む",
    "全ユーザーで共有する1つの管理者ロールをエージェントに割り当てる",
    "Cognito ユーザープールにエージェントを1ユーザーとして登録する"],
  answer:0,
  note:"エージェント型アプリでは「誰の代理で動いているか」を保ったまま権限を絞るのが課題になる。公式試験ガイドの Emerging Topics は、この用途の例として AgentCore Identity を挙げている。\n共有の管理者ロールや埋め込みアクセスキーは、従来どおり最小権限と一時認証情報の原則に反する。この領域は現時点では採点対象外の pretest 問題として出題されうる位置づけ。" },

{ id:"d3-44", dom:3, cat:"コスト最適化",
  q:"「先月どのアカウントのどのリソースが、どの時間帯に、いくらかかったのか」をリソース ID 単位・時間単位で分析したい。Cost Explorer では粒度が足りません。適したものは?",
  choices:[
    "AWS Cost and Usage Report（CUR）を S3 に出力し、Athena（または QuickSight）で分析する",
    "AWS Budgets のレポートを毎日確認する",
    "CloudWatch の請求メトリクスにアラームを設定する",
    "Trusted Advisor のコスト最適化チェックを実行する"],
  answer:0,
  note:"CUR は最も粒度の細かい請求データで、時間単位・リソース ID 単位の明細を S3 に出力できる。Parquet 形式にして Athena でクエリ、QuickSight で可視化するのが定番パターン。\nCost Explorer は分析が手軽だが粒度と保持期間に制約がある。Budgets はしきい値によるアラート、CloudWatch の請求メトリクスは概算の総額監視、Trusted Advisor は汎用的な推奨で、いずれも明細分析には使えない。" },

{ id:"d3-45", dom:3, cat:"監視/運用自動化",
  q:"既存ワークロードの弱点を体系的に洗い出し、改善項目に優先順位を付けて経営層に報告したい。AWS が提供する無償の仕組みは?",
  choices:[
    "AWS Well-Architected Tool でワークロードをレビューし、リスクと改善計画を出力する",
    "AWS Trusted Advisor のすべてのチェックを実行する",
    "AWS Compute Optimizer の推奨を一覧する",
    "AWS Config のコンプライアンスレポートを出力する"],
  answer:0,
  note:"Well-Architected Tool は6つの柱（運用上の優秀性・セキュリティ・信頼性・パフォーマンス効率・コスト最適化・持続可能性）の質問に答える形でワークロードをレビューし、高リスク/中リスク項目と改善計画を生成する。サーバーレスや SaaS などのレンズも適用できる。\nTrusted Advisor/Compute Optimizer/Config はいずれも自動チェックで、設計上の意思決定（アーキテクチャの妥当性）までは評価しない。" },

{ id:"d3-46", dom:3, cat:"監視/運用自動化",
  q:"EKS で動くマイクロサービス群を、チームが慣れている Prometheus のクエリと Grafana のダッシュボードで監視したい。運用負荷を抑えたい。適した構成は?",
  choices:[
    "Amazon Managed Service for Prometheus にメトリクスを収集し、Amazon Managed Grafana から可視化する",
    "EC2 上に Prometheus と Grafana を自前で構築して冗長化する",
    "CloudWatch のカスタムメトリクスにすべて変換して送る",
    "各 Pod のログを S3 に出力して Athena で集計する"],

  answer:0,
  note:"既存の PromQL クエリや Grafana ダッシュボードの資産をそのまま活かしつつ、スケーリング・可用性・アップグレードを AWS に任せられる。Managed Grafana は IAM Identity Center と統合でき、CloudWatch や X-Ray もデータソースにできる。\n「既存のツールチェーンをそのまま使いたい」という記述はマネージド互換サービスへの誘導。自前構築は運用負荷が最大。" },

{ id:"d4-35", dom:4, cat:"データ分析",
  q:"オンプレで自前運用している Elasticsearch クラスター（ログ検索用、数十 TB、直近1か月以外はほとんど検索されない）を AWS に移行し、運用とコストを下げたい。適した構成は?",
  choices:[
    "Amazon OpenSearch Service に移行し、古いインデックスを UltraWarm / コールドストレージ階層へ自動移行する",
    "EC2 に Elasticsearch を構築してそのまま移す",
    "全ログを S3 に置き、検索は Athena だけで行う",
    "Amazon Redshift にログをロードする"],
  answer:0,
  note:"OpenSearch Service はマネージドで、ホットノードに加えて UltraWarm（S3 バックの低コスト検索可能層）とコールドストレージを持つ。インデックスステート管理（ISM）で「◯日経ったら UltraWarm へ」を自動化でき、アクセス頻度に応じたコスト最適化ができる。\n移行はスナップショットを S3 に取って復元するのが一般的。Athena は対話的な SQL 分析向けで、全文検索やログのリアルタイム可視化には向かない。" },

{ id:"d4-36", dom:4, cat:"モダナイゼーション",
  q:"オンプレの Java 業務アプリが JMS で ActiveMQ と通信しています。短期間で AWS へ移行したく、アプリのメッセージング部分は書き換えたくありません。適した移行先は?",
  choices:[
    "Amazon MQ",
    "Amazon SQS",
    "Amazon SNS",
    "Amazon Kinesis Data Streams"],
  answer:0,
  note:"Amazon MQ はマネージドの Apache ActiveMQ / RabbitMQ で、JMS・AMQP・MQTT・STOMP・OpenWire といった業界標準プロトコルをそのまま話せる。既存アプリのコードを変えずに済むのが最大の利点で、まさにリプラットフォームの典型例。\nSQS/SNS はプロトコルが AWS 独自の API なのでアプリ改修が要る。新規開発でプロトコル互換の制約がないなら、スケーラビリティと運用の軽さから SQS/SNS のほうが望ましい。" },

{ id:"d4-37", dom:4, cat:"モダナイゼーション",
  q:"コンテナ化済みのシンプルな Web API を、CI からイメージを push するだけで公開・自動スケールさせたい。ロードバランサーやクラスターの構成もしたくありません。最も運用が軽いのは?",
  choices:[
    "AWS App Runner",
    "Amazon ECS on Fargate をゼロから構成する",
    "AWS Elastic Beanstalk の EC2 環境",
    "Amazon EKS のマネージドノードグループ"],
  answer:0,
  note:"App Runner はコンテナイメージ（またはソースリポジトリ）を指定するだけで、ビルド・デプロイ・ロードバランサー・TLS・オートスケールまで面倒を見る。VPC 構成やクラスター管理が不要で、最も抽象度が高い。\n細かい制御が必要になったら ECS on Fargate、Kubernetes の資産があれば EKS へ。Elastic Beanstalk は EC2 が見える PaaS で、既存の非コンテナアプリの受け皿としては有効だが、コンテナ前提なら App Runner/ECS のほうが素直。" },

{ id:"d4-38", dom:4, cat:"コンピュート",
  q:"移行の途中で、規制上オンプレに残さざるを得ないサーバーが残ります。オンプレとクラウドのコンテナを同じ仕組みでデプロイ・監視したい。適したものは?",
  choices:[
    "AWS 上の ECS コントロールプレーンにオンプレのサーバーを外部インスタンスとして登録する（Amazon ECS Anywhere）",
    "オンプレに独立した Docker 環境を構築し、別々に運用する",
    "オンプレのサーバーを AWS Outposts に置き換える",
    "オンプレのコンテナを Lambda に移す"],
  answer:0,
  note:"ECS Anywhere は SSM エージェント経由でオンプレのサーバーを ECS の外部インスタンスとして登録し、AWS 側のコントロールプレーンから同じタスク定義でデプロイ・監視できる。Kubernetes を使うなら EKS Anywhere（こちらはコントロールプレーンもオンプレ側）。\n「クラウドとオンプレを同じ運用に寄せたい」という要件で選ばれる。Outposts はハードウェアごと置き換える大掛かりな選択で、既存サーバーを残す前提には合わない。" },

{ id:"d4-39", dom:4, cat:"移行",
  q:"世界各地の支社から、本社リージョンの S3 バケットへ日々数百 GB のファイルをアップロードしています。地理的に遠い支社ほどアップロードが遅く、業務時間内に終わりません。継続的に発生する転送なので物理搬送は使えません。適した対策は?",
  choices:[
    "S3 Transfer Acceleration を有効にし、各支社は最寄りのエッジロケーション経由で AWS のバックボーンに乗せる",
    "AWS Snowball Edge を各支社に常設する",
    "支社ごとに S3 バケットを作り、あとで手動で統合する",
    "アップロードを夜間バッチに変更する"],
  answer:0,
  note:"Transfer Acceleration は CloudFront のエッジロケーションで受けてから AWS のバックボーンでバケットまで運ぶため、長距離・高遅延の回線ほど効果が出る。有効化は追加料金がかかるので、速度比較ツールで効果を測ってから使う。\n大容量の「1回限り」の移送は Snow ファミリー、継続的なファイル同期は DataSync、長距離の継続アップロードは Transfer Acceleration、という使い分けを押さえる。マルチパートアップロードの併用も前提。" },

{ id:"d4-40", dom:4, cat:"生成AI(新領域)",
  q:"生成AI が起票した変更内容を、本番へ適用する前に必ず人間がレビュー・承認する仕組みを、ワークフローとして組み込みたい。試験ガイドが例に挙げているサービスは?",
  choices:[
    "AWS Step Functions で承認待ちの状態を持たせ、承認後に後続処理へ進める",
    "Lambda の中で承認結果をポーリングし続ける",
    "承認は運用手順書に記載し、担当者の目視確認に任せる",
    "EventBridge のスケジュールで24時間後に自動適用する"],
  answer:0,
  note:"公式試験ガイドの Emerging Topics は「AI の操作に承認機構を含む人間の監督（human oversight）ワークフローの設計」の例として Step Functions を挙げている。コールバックパターン（タスクトークン）を使えば、承認が返るまで状態を保持したまま最長1年待てる。\nLambda のポーリングは15分の実行時間上限に阻まれ、手順書頼みや時間経過での自動適用は「監督」になっていない。" },

/* =======================================================================
 * SAP-C02-quiz.md から取り込んだ30問（id は md-NN）
 * 出典ファイルは awsquiz/SAP-C02-quiz.md。あちらを直したらこちらも直すこと。
 * 内訳: Q1-9=ドメイン1 / Q10-15=ドメイン4 / Q16-24=ドメイン2 / Q25-30=ドメイン3
 * ===================================================================== */

{ id:"md-05", dom:1, cat:"ネットワーク",
  q:"中央のネットワークアカウントが所有する Transit Gateway とサブネットを、Organizations 内の複数アカウントで共有して VPC を集中管理したい。適切な選択肢を2つ選べ。",
  choices:[
    "AWS Resource Access Manager (RAM) を有効化し、Organizations 内での共有を許可する",
    "各アカウントに Transit Gateway を個別に複製する",
    "RAM で Transit Gateway とサブネットを対象アカウント/OU に共有する",
    "各アカウント間で手動の VPC ピアリングを設定する",
    "リソースを共有するために全アカウントに Admin 権限を付与する"],
  answer:[0,2],
  note:"RAM は Organizations との統合を有効化することで、Transit Gateway や VPC サブネットなどを対象アカウント/OU へ安全に共有でき、共有サブネット上に各アカウントが独自リソースを配置できる（VPC 共有）。TGW の個別複製は集中管理の目的に反し、手動ピアリングは RAM があれば不要、Admin 権限の一律付与は最小権限違反。\n参照: AWS Resource Access Manager、VPC Sharing。" },

{ id:"md-09", dom:1, cat:"ハイブリッド接続",
  q:"基幹システムがオンプレミスと AWS 間で低遅延・安定帯域を必要としており、単一の Direct Connect 接続の障害に備えて回復力を高めたい。適切な設計を2つ選べ。",
  choices:[
    "2 つ目の Direct Connect 接続を別のロケーション/デバイスで冗長化する",
    "Direct Connect のバックアップとしてサイト間 VPN を構成する",
    "Direct Connect を廃止し、インターネット VPN のみにする",
    "すべてのトラフィックを 1 本の Direct Connect に集約して単純化する",
    "NAT Gateway を追加して冗長化する"],
  answer:[0,1],
  note:"高可用性の推奨は、複数ロケーション/デバイスにまたがる Direct Connect の冗長化（最大耐障害性）と、コスト効率のよいフェイルオーバーとして Site-to-Site VPN のバックアップを併用することである。VPN のみへの切り替えは低遅延/帯域要件を犠牲にし、1 本への集約は単一障害点を残し、NAT Gateway はオンプレ接続の冗長化と無関係。\n参照: AWS Direct Connect Resiliency、Site-to-Site VPN。" },

{ id:"md-10", dom:4, cat:"移行",
  q:"オンプレミスの商用ライセンスのレガシー業務アプリを、コードを変更せずに短期間で AWS へ移すことが求められている。将来的な最新化は別途検討する。最も適した移行戦略はどれか。",
  choices:[
    "Refactor（リファクタリング）でサーバーレスに再設計する",
    "Rehost（リホスト、リフト＆シフト）で AWS Application Migration Service を使い EC2 へ移行する",
    "Retire（廃止）する",
    "Repurchase（リパーチェス）で全く別の SaaS に置き換える"],
  answer:1,
  note:"コード変更なし・短期間という要件は Rehost（リフト＆シフト）に合致し、AWS MGN（Application Migration Service）がブロックレベル複製で最小の変更で EC2 へ移行できる。Refactor は時間とコストがかかり要件に反し、Retire はまだ使用中のため不適、Repurchase は業務要件が満たされる保証がなく再学習も必要。\n参照: 6R 戦略、AWS MGN。" },

{ id:"md-16", dom:2, cat:"可用性/DR",
  q:"ある企業は EC2 上で稼働する 3 層 Web アプリケーションを別リージョンへの災害復旧対応させたい。要件は RTO 数分、RPO 数秒で、平常時のコストは最小限に抑えたい。DR リージョンには常に縮小構成のスタックを稼働させておく方針である。この要件に最も適合する DR 戦略はどれか。",
  choices:[
    "Backup and Restore（AMI とスナップショットを定期取得し障害時に構築）",
    "Pilot Light（DB のみ複製し、アプリ層は障害時に起動）",
    "Warm Standby（縮小版フルスタックを常時稼働させ障害時にスケールアップ）",
    "Multi-site active-active（両リージョンで本番同等を稼働）"],
  answer:2, fig:"dr",
  note:"Warm Standby は縮小版の完全なスタック（全層）を常時稼働させておき、フェイルオーバー時にスケールアップするため、数分の RTO と常時稼働による低い RPO を満たしつつ、active-active より低コストである。Backup and Restore と Pilot Light はアプリ層の起動・構築に時間がかかり RTO 数分を満たしにくい。active-active はコストが最も高く「平常時コスト最小」の要件に反する。\n参照: AWS DR 戦略。" },

{ id:"md-20", dom:2, cat:"モダナイゼーション",
  q:"注文イベントを、(1) 複数の内部マイクロサービスへ同報配信し、かつ (2) イベントの属性内容（例: 金額が閾値以上）に基づいて異なる SaaS パートナーへルーティングしたい。それぞれに最適なサービスの組み合わせを2つ選択してください。",
  choices:[
    "内部サービスへの同報には SNS のトピック + 複数 SQS サブスクリプション（ファンアウト）",
    "内部サービスへの同報には単一の SQS キューを共有させる",
    "属性ベースの高度なルーティングには EventBridge のイベントバス + ルール",
    "属性ベースのルーティングには SNS のメッセージフィルタリングのみで SaaS パートナーへ直接配信",
    "属性ベースのルーティングには Kinesis Data Streams"],
  answer:[0,2],
  note:"SNS のトピックに複数の SQS をサブスクライブするファンアウトは、複数の内部コンシューマーへの信頼性の高い同報配信の定番パターンである。EventBridge はイベントのペイロード内容に対する詳細なパターンマッチングと SaaS パートナー含む多様なターゲットへのルーティングに優れる。単一 SQS キューの共有は 1 コンシューマーしか扱えず同報にならない。SNS のフィルタは属性ベースで限定的。\n参照: Amazon SNS, Amazon EventBridge。" },

{ id:"md-21", dom:2, cat:"モダナイゼーション",
  q:"複数の Lambda と外部承認ステップを含む長時間の業務ワークフローを構築する。途中で人間の承認（メール返信で数時間〜数日かかる場合あり）を待ち、承認後に後続処理を続けたい。最小の運用負荷で状態管理する方法はどれか。",
  choices:[
    "Lambda 内で承認をポーリングし、待機中も実行し続ける",
    "Step Functions のコールバックパターン（waitForTaskToken）を使い、トークン受領で再開する",
    "SQS の遅延キューで固定時間待ってから続行する",
    "EC2 上で常駐ワーカーを動かしステータスを管理する"],
  answer:1,
  note:"Step Functions の waitForTaskToken コールバックパターンは、タスクトークンを外部へ渡し、承認完了時に SendTaskSuccess で返すことでワークフローを再開でき、最長 1 年まで待機可能でマネージドに状態を保持する。Lambda は最大 15 分制限を超えられずコストも無駄。不定期な承認に固定待機は不適。常駐ワーカーは運用負荷が高い。\n参照: AWS Step Functions callback pattern。" },

{ id:"md-23", dom:2, cat:"セキュリティ/コンプライアンス",
  q:"アプリを 2 リージョンで active-active 展開し、両リージョンで同一の暗号化データを復号できる必要がある。また DB 認証情報は自動ローテーションしたい。適切な組み合わせを2つ選択してください。",
  choices:[
    "KMS マルチリージョンキー（プライマリ + レプリカキー）で両リージョンから同一暗号文を復号する",
    "各リージョンで独立した単一リージョン KMS キーを作り、暗号文を復号時に相互変換する",
    "Secrets Manager のマネージドローテーション（Lambda ローテーション関数）で DB 認証情報を自動ローテーションする",
    "認証情報を KMS で暗号化して S3 に置き、手動で更新する",
    "Systems Manager Parameter Store の SecureString でローテーションを有効化する"],
  answer:[0,2],
  note:"KMS マルチリージョンキーは同じキーマテリアルをリージョン間で複製するため、あるリージョンで暗号化したデータを別リージョンのレプリカキーで復号でき、active-active に適する。Secrets Manager は RDS 等に対しローテーション用 Lambda を用いた自動ローテーションをネイティブに提供する。独立キーでは暗号文の相互復号ができず非現実的。Parameter Store 自体にローテーション機能はない。\n参照: AWS KMS multi-Region keys, AWS Secrets Manager rotation。" },

{ id:"md-24", dom:2, cat:"セキュリティ/コンプライアンス",
  q:"公開 Web アプリを ALB と CloudFront 経由で提供している。SQL インジェクションや不正な HTTP リクエストをブロックしつつ、大規模な L3/L4 DDoS 攻撃に対する高度な保護と DDoS 費用補償を得たい。適切な組み合わせを2つ選択してください。",
  choices:[
    "AWS WAF の Web ACL（マネージドルール含む）を CloudFront/ALB に関連付ける",
    "Security Group のインバウンドで攻撃元 IP を都度ブロックする",
    "AWS Shield Advanced を有効化する",
    "AWS Shield Standard のみに依存し追加設定は不要とする",
    "Network ACL でアプリ層攻撃をフィルタする"],
  answer:[0,2],
  note:"AWS WAF は SQLi/XSS などの L7 攻撃をルール（マネージドルール含む）でブロックできる。Shield Standard は無償で L3/L4 を自動保護するが、Shield Advanced は加えて高度な検知、24x7 の DDoS 対応チーム（SRT）による支援、DDoS 起因のスケーリング費用補償を提供する。Security Group での都度ブロックは運用が手動で追いつかない。NACL はステートレスで L7 攻撃には無力。\n混同しやすい隣接サービス: GuardDuty は脅威検知、Inspector は脆弱性スキャン、Macie は S3 の機密データ検出で、いずれも「防御」そのものではない。組織横断で WAF/Shield を強制したい場合は Firewall Manager を重ねる。\n参照: AWS WAF, AWS Shield Advanced。" },

{ id:"md-25", dom:3, cat:"コスト最適化",
  q:"ある企業のワークロードは、(1) 24 時間安定稼働する Fargate/Lambda/EC2 混在のベースライン、(2) 中断耐性のあるバッチ処理、で構成される。最もコスト効率よく、かつ柔軟性を保つ選択の組み合わせはどれか。2つ選択してください。",
  choices:[
    "ベースラインには Compute Savings Plans を購入する",
    "ベースラインには Standard RI を各インスタンスタイプ個別に購入する",
    "中断耐性のあるバッチには Spot Instances / Spot を使う",
    "すべて On-Demand のままにする",
    "中断耐性のあるバッチにも 3 年 All Upfront の Standard RI を購入する"],
  answer:[0,2],
  note:"Compute Savings Plans は EC2 だけでなく Fargate と Lambda にも適用され、インスタンスファミリー/リージョン/サービスをまたいだ柔軟性を保ちつつ割引を得られるため混在ベースラインに最適。中断耐性のあるバッチは Spot で大幅な割引を得られる。Standard RI は柔軟性が低く、中断され得るバッチに長期固定コミットは不適。On-Demand のままでは割引機会を逃す。\n参照: AWS Savings Plans, Amazon EC2 Spot。" },

{ id:"md-26", dom:3, cat:"ストレージ",
  q:"アクセスパターンが予測不能なデータと、90 日後にほぼアクセスされず数年間保持義務のある監査ログが混在する S3 バケットがある。運用の手間なくコストを最適化したい。適切な設定はどれか。",
  choices:[
    "すべて S3 Standard に置き続ける",
    "アクセス不定のデータは S3 Intelligent-Tiering、監査ログはライフサイクルで一定日数後に Glacier Flexible Retrieval / Deep Archive へ移行する",
    "すべて S3 One Zone-IA に移行する",
    "すべて即座に Glacier Deep Archive に移行する"],
  answer:1, fig:"s3class",
  note:"アクセスパターンが読めないデータは Intelligent-Tiering が自動で最適な階層へ移動し、監視のみで手動管理不要。長期保持でアクセス頻度が低い監査ログはライフサイクルルールで Glacier 系へ移行してコスト削減できる。Standard のままはコスト過大。One Zone-IA は単一 AZ で耐久性リスクがあり頻繁アクセスにも不適。即時 Deep Archive は監査ログの初期 90 日アクセスに取り出しコスト/遅延が発生し不適。\n参照: S3 Intelligent-Tiering, S3 Lifecycle。" },

{ id:"md-29", dom:3, cat:"監視/運用自動化",
  q:"数百アカウントのマルチアカウント環境で、(1) リソース構成のコンプライアンス（例: 暗号化されていない EBS の検出と自動修復）、(2) EC2 フリートへの一括パッチ適用を、中央集権的かつ自動で実施したい。適切な組み合わせを2つ選択してください。",
  choices:[
    "AWS Config のマネージドルール + 自動修復（SSM Automation）で非準拠リソースを検出・是正する",
    "CloudTrail のログを人手で毎日確認して是正する",
    "Systems Manager Patch Manager + パッチベースラインとメンテナンスウィンドウで一括パッチ適用する",
    "各 EC2 に SSH して手動で yum update する",
    "GuardDuty でパッチ適用状況を管理する"],
  answer:[0,2],
  note:"AWS Config のルールで非準拠リソース（例: 非暗号化 EBS）を継続評価し、SSM Automation ドキュメントによる自動修復を紐づければ検出と是正を自動化できる（Organizations で集約可能）。Systems Manager Patch Manager はパッチベースラインとメンテナンスウィンドウでフリート全体のパッチ適用をスケジュール実行できる。人手による確認や SSH での手動更新はスケールしない。GuardDuty は脅威検知であってパッチ管理機能ではない。\n参照: AWS Config remediation, SSM Patch Manager。" },

{ id:"md-30", dom:3, cat:"データベース",
  q:"既存の RDS MySQL が、読み取り負荷急増でレイテンシー悪化と AZ 障害時のダウンタイムに悩んでいる。可用性と読み取りスケーラビリティの両方を改善したい。最適な組み合わせを2つ選択してください。",
  choices:[
    "RDS Multi-AZ 配置を有効化して AZ 障害時の自動フェイルオーバーを得る",
    "リードレプリカを追加し読み取りクエリを振り分けて読み取りをスケールする（必要に応じ ElastiCache でキャッシュ）",
    "Multi-AZ のスタンバイをアプリの読み取りに使ってスケールする",
    "インスタンスを毎回手動で垂直スケールアップして対処する",
    "単一 AZ のまま自動バックアップ頻度だけ上げる"],
  answer:[0,1],
  note:"Multi-AZ は同期スタンバイへ自動フェイルオーバーして AZ 障害時の可用性を高める（ただしスタンバイは読み取りに使えない）。読み取りスケールにはリードレプリカへ読み取りを振り分け、ElastiCache でホットデータをキャッシュしてさらに DB 負荷を軽減する。Multi-AZ のスタンバイは読み取りに使えないため誤り。手動の垂直スケールは運用負荷が高くスパイクに追随しにくい。バックアップ頻度は可用性もスケールも解決しない。\n参照: RDS Multi-AZ, RDS Read Replica, Amazon ElastiCache。" }

];
