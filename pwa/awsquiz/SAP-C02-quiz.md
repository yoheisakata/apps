# AWS SAP-C02 練習クイズ（30問）

> AWS Certified Solutions Architect – Professional (**SAP-C02**) 対策のオリジナル練習問題。
> **個人学習用**。問題文・選択肢・解説はすべて書き下ろしのオリジナルで、特定教材の文章を転載したものではありません。
> AWS サービス名は英語表記。各問の「解答・解説」は `<details>` で折りたたんでいます（クリックで開く）。
> 想定配分（本番）: Domain 1 =26% / Domain 2 =29% / Domain 3 =25% / Domain 4 =20%。

## 使い方
- 各設問で選択肢を選んでから「解答・解説」を開いて答え合わせ。
- 「2つ選択」と明記された問題は複数選択（2つ）です。
- 間違えた問題のトピックは、`SAP-C02 Trainer` アプリの該当ドメイン／サービス学習で復習を。

---

## Domain 1（組織の複雑性）・Domain 4（移行と最新化）

### Q1. [Domain 1] AWS Organizations と SCP
ある企業は AWS Organizations で数十のアカウントを管理している。セキュリティ部門は、開発用 OU 配下のすべてのアカウントで、承認済みリージョン（ap-northeast-1 と us-east-1）以外でのリソース作成を強制的に禁止したい。個々のアカウント管理者が回避できないようにする必要がある。最も適切な方法はどれか。

- A. 各アカウントの IAM ユーザーに、リージョンを制限する IAM 許可ポリシーを付与する
- B. 開発用 OU に対して、`aws:RequestedRegion` を条件に非承認リージョンを Deny する SCP を適用する
- C. 各アカウントで AWS Config ルールを作成し、非承認リージョンのリソースを自動削除する
- D. IAM Identity Center のアクセス許可セットでリージョン制限を設定する

<details><summary>解答・解説</summary>

**正解: B**

SCP は OU 配下の全アカウント（root ユーザー含む）の最大許可範囲を絞り込むガードレールであり、`aws:RequestedRegion` 条件で非承認リージョンを Deny すれば個々の管理者が回避できない。A/D は IAM の許可であり管理者が変更・回避できる。C は事後検知/削除で予防にならず、グローバルサービス操作の妨げにもなりうる。参照: AWS Organizations SCP。
</details>

### Q2. [Domain 1] クロスアカウント IAM ロールと STS
本番アカウント A のログ用 S3 バケットに、監査アカウント B の分析ツールから読み取りアクセスさせたい。長期的な認証情報の配布を避け、最小権限で実現する構成はどれか。

- A. アカウント A で IAM ユーザーを作成し、そのアクセスキーをアカウント B に共有する
- B. アカウント A にクロスアカウント IAM ロールを作成し信頼ポリシーでアカウント B を許可、アカウント B のプリンシパルが `sts:AssumeRole` で一時認証情報を取得する
- C. S3 バケットポリシーでアカウント B の全 IAM ユーザーを `Principal: *` で許可する
- D. アカウント B のリソースをアカウント A に移設して同一アカウント内でアクセスする

<details><summary>解答・解説</summary>

**正解: B**

クロスアカウントアクセスのベストプラクティスは、リソース側アカウントにロールを作り信頼ポリシーで相手アカウントを許可し、`sts:AssumeRole` による短命の一時認証情報を使うこと。A は長期キー配布でローテーション・漏洩リスクが高い。C の `Principal: *` は過剰許可で危険。D は不要な移設。参照: AWS STS、クロスアカウント IAM ロール。
</details>

### Q3. [Domain 1] AWS Control Tower とアカウント発行
企業は数百のアカウントを標準化されたガードレール、集約ログ、SSO 付きで迅速に発行できる基盤を最小の運用負荷で構築したい。最も適切なサービスはどれか。

- A. 手動で各アカウントを作成し、CloudFormation StackSets でベースラインを都度適用する
- B. AWS Control Tower を使い、Account Factory でアカウントをプロビジョニングし、予防的/発見的ガードレールと集約ログを自動適用する
- C. AWS Config のみを全アカウントに個別設定する
- D. 各チームに個別のスタンドアロンアカウントを作らせ、後から統合する

<details><summary>解答・解説</summary>

**正解: B**

Control Tower は Organizations、SCP ベースの予防的ガードレール、Config ベースの発見的ガードレール、集約ログ用の Log Archive アカウント、IAM Identity Center による SSO を含むランディングゾーンを自動構築し、Account Factory で標準化アカウントを発行できる。A は運用負荷が高く、C/D は基盤要件を満たさない。参照: AWS Control Tower、Account Factory。
</details>

### Q4. [Domain 1] Transit Gateway による接続の集約
50 個の VPC が相互に通信する必要があり、現在はフルメッシュの VPC ピアリングで管理が破綻している。オンプレミスとの接続も 1 か所に集約したい。最も拡張性が高い構成はどれか。

- A. すべての VPC 間で VPC ピアリングを追加し続ける
- B. 各 VPC を AWS Transit Gateway にアタッチし、ルートテーブルで通信を制御、Direct Connect / VPN も Transit Gateway に集約する
- C. すべての VPC を 1 つの巨大な VPC に統合する
- D. 各 VPC に NAT Gateway を置いてインターネット経由で通信させる

<details><summary>解答・解説</summary>

**正解: B**

Transit Gateway はハブアンドスポーク型でVPC 間およびオンプレミス接続を集約でき、ピアリングのフルメッシュ（N×(N-1)/2 の管理）を解消する。ルートテーブルでセグメント分離も可能。A は破綻の継続、C は非現実的で影響範囲が大きい、D はインターネット経由で内部通信させるべきでない。参照: AWS Transit Gateway。
</details>

### Q5. [Domain 1] AWS RAM によるリソース共有（2つ選択）
中央のネットワークアカウントが所有する Transit Gateway とサブネットを、Organizations 内の複数アカウントで共有して VPC を集中管理したい。適切な選択肢を2つ選べ。

- A. AWS Resource Access Manager (RAM) を有効化し、Organizations 内での共有を許可する
- B. 各アカウントに Transit Gateway を個別に複製する
- C. RAM で Transit Gateway とサブネットを対象アカウント/OU に共有する
- D. 各アカウント間で手動の VPC ピアリングを設定する
- E. リソースを共有するために全アカウントに Admin 権限を付与する

<details><summary>解答・解説</summary>

**正解: A, C**

RAM は Organizations との統合を有効化することで、Transit Gateway や VPC サブネットなどを対象アカウント/OU へ安全に共有でき、共有サブネット上に各アカウントが独自リソースを配置できる（VPC Sharing）。B は集中管理の目的に反し、D はRAMで不要、E は最小権限違反。参照: AWS Resource Access Manager、VPC Sharing。
</details>

### Q6. [Domain 1] 組織全体の集中ログ収集
企業は Organizations 内すべてのアカウントの API アクティビティを、改ざんされにくい形で 1 つの中央アカウントに集約したい。新規アカウントも自動的に対象にしたい。最適な方法はどれか。

- A. 各アカウントで個別に CloudTrail 証跡を作成し、手動で集約する
- B. 管理アカウントから組織証跡 (organization trail) を作成し、中央のログアーカイブアカウントの S3 バケットに配信する
- C. CloudWatch Logs を各アカウントで有効にし、メールで転送する
- D. VPC フローログのみを集約する

<details><summary>解答・解説</summary>

**正解: B**

CloudTrail の組織証跡は、管理アカウント（または委任管理者）が作成し、既存および将来のメンバーアカウントすべてのイベントを自動的に集約対象とし、中央 S3 バケットへ配信できる。バケットポリシーとオブジェクトロックで改ざん耐性も高められる。A は運用負荷と抜け漏れ、C は非現実的、D は API アクティビティを網羅しない。参照: AWS CloudTrail organization trail。
</details>

### Q7. [Domain 1] 委任管理者 (Delegated Administrator)
セキュリティチームは、Organizations の管理アカウントに高い権限を集中させることを避けつつ、GuardDuty や Security Hub を専用のセキュリティアカウントから組織全体で運用したい。適切な手法はどれか。

- A. 管理アカウントの root ユーザーの認証情報をセキュリティチームに共有する
- B. セキュリティアカウントを各サービスの委任管理者 (delegated administrator) に指定し、そのアカウントから組織全体の設定を管理する
- C. すべてのメンバーアカウントに Admin IAM ユーザーを作成する
- D. 管理アカウントでのみ各セキュリティサービスを個別運用する

<details><summary>解答・解説</summary>

**正解: B**

多くの AWS セキュリティ/ガバナンスサービス（GuardDuty、Security Hub、Config、Macie 等）は委任管理者をサポートし、管理アカウントに権限を集中させずに専用アカウントから組織全体を集中管理できる。これは管理アカウントの使用を最小化するベストプラクティスに沿う。A/C は重大なセキュリティ違反、D は権限集中を招く。参照: AWS Organizations delegated administrator。
</details>

### Q8. [Domain 1] PrivateLink によるサービス公開
ある SaaS プロバイダーは、自社 VPC 内のサービスを、多数の顧客 VPC に対して、IP 重複を気にせず、インターネットや VPC ピアリングを使わずに一方向で公開したい。最適な構成はどれか。

- A. 各顧客と VPC ピアリングを結ぶ
- B. サービスの前段に Network Load Balancer を置き、VPC エンドポイントサービス (AWS PrivateLink) を作成、顧客はインターフェイス VPC エンドポイントで接続する
- C. サービスをパブリックサブネットに置き、インターネット経由で公開する
- D. Transit Gateway で全顧客 VPC を相互接続する

<details><summary>解答・解説</summary>

**正解: B**

PrivateLink はエンドポイントサービス（NLB 背後）とインターフェイスエンドポイントにより、一方向・非公開・CIDR 重複に依存しないサービス公開を実現する。A/D は双方向接続で CIDR 重複に弱くマルチテナントに不向き、C はインターネット公開で要件に反する。参照: AWS PrivateLink、VPC エンドポイントサービス。
</details>

### Q9. [Domain 1] Direct Connect の高可用性設計（2つ選択）
基幹システムがオンプレミスと AWS 間で低遅延・安定帯域を必要としており、単一の Direct Connect 接続の障害に備えて回復力を高めたい。適切な設計を2つ選べ。

- A. 2 つ目の Direct Connect 接続を別のロケーション/デバイスで冗長化する
- B. Direct Connect のバックアップとしてサイト間 VPN を構成する
- C. Direct Connect を廃止し、インターネット VPN のみにする
- D. すべてのトラフィックを 1 本の Direct Connect に集約して単純化する
- E. NAT Gateway を追加して冗長化する

<details><summary>解答・解説</summary>

**正解: A, B**

高可用性の推奨は、複数ロケーション/デバイスにまたがる Direct Connect の冗長化（最大耐障害性）と、コスト効率のよいフェイルオーバーとして Site-to-Site VPN のバックアップを併用することである。C は低遅延/帯域要件を犠牲にし、D は単一障害点を残し、E はオンプレ接続の冗長化と無関係。参照: AWS Direct Connect Resiliency、Site-to-Site VPN。
</details>

### Q10. [Domain 4] 6R 戦略の選定
オンプレミスの商用ライセンスのレガシー業務アプリを、コードを変更せずに短期間で AWS へ移すことが求められている。将来的な最新化は別途検討する。最も適した移行戦略はどれか。

- A. Refactor（リファクタリング）でサーバーレスに再設計する
- B. Rehost（リホスト、リフト＆シフト）で AWS Application Migration Service を使い EC2 へ移行する
- C. Retire（廃止）する
- D. Repurchase（リパーチェス）で全く別の SaaS に置き換える

<details><summary>解答・解説</summary>

**正解: B**

コード変更なし・短期間という要件は Rehost（リフト＆シフト）に合致し、AWS MGN（Application Migration Service）がブロックレベル複製で最小の変更で EC2 へ移行できる。A は時間とコストがかかり要件に反し、C はまだ使用中のため不適、D は業務要件が満たされる保証がなく再学習も必要。参照: 6R 戦略、AWS MGN。
</details>

### Q11. [Domain 4] AWS DMS と SCT による異種DB移行
オンプレミスの Oracle データベースを Amazon Aurora PostgreSQL へ、ダウンタイムを最小化して移行したい。スキーマとストアドプロシージャの変換も必要である。適切なツールの組み合わせはどれか。

- A. DataSync でファイルとしてコピーする
- B. AWS Schema Conversion Tool (SCT) でスキーマ/コードを変換し、AWS DMS の継続的レプリケーション (CDC) で最小ダウンタイム移行を行う
- C. スナップショットを取得して Aurora に直接復元する
- D. mysqldump でエクスポートしインポートする

<details><summary>解答・解説</summary>

**正解: B**

異種エンジン間（Oracle→Aurora PostgreSQL）ではスキーマ差異があるため SCT でスキーマ/PL/SQL を変換し、DMS の CDC（変更データキャプチャ）で継続レプリケーションを行うことで最小ダウンタイムのカットオーバーが可能。A はDB移行に不適、C はエンジンが異なり不可、D は Oracle と無関係で異種変換もできない。参照: AWS DMS、AWS SCT。
</details>

### Q12. [Domain 4] Application Discovery Service と Migration Hub
数百台のオンプレミスサーバーの依存関係や使用状況を移行前に把握し、移行の進捗を単一ビューで追跡したい。適切なサービスの組み合わせはどれか。

- A. AWS Config と CloudWatch
- B. AWS Application Discovery Service で構成・依存関係・使用状況を収集し、AWS Migration Hub で発見データと移行進捗を一元的に追跡する
- C. AWS Trusted Advisor で移行計画を立てる
- D. Amazon Inspector で依存関係を可視化する


<details><summary>解答・解説</summary>

**正解: B**

Application Discovery Service（エージェントベース/エージェントレス）はサーバー構成、パフォーマンス、ネットワーク依存関係を収集し、Migration Hub がそのデータと各移行ツールの進捗を集約して単一ビューで可視化する。A/C/D はそれぞれ構成監査・推奨・脆弱性検査が目的で、移行の発見/追跡には設計されていない。参照: AWS Application Discovery Service、AWS Migration Hub。
</details>

### Q13. [Domain 4] DataSync による大容量データ転送
オンプレミス NAS 上の 200 TB のファイルを、既存のネットワーク回線を使って Amazon S3 と Amazon EFS へ、増分同期・整合性検証付きで定期転送したい。最適なサービスはどれか。

- A. AWS Snowball Edge を注文して郵送する
- B. AWS DataSync のエージェントをオンプレに配置し、S3/EFS への高速・増分・検証付き転送をスケジュールする
- C. S3 コンソールから手動でドラッグ＆ドロップする
- D. Storage Gateway のテープゲートウェイを使う

<details><summary>解答・解説</summary>

**正解: B**

DataSync はオンプレミス（NFS/SMB）から S3/EFS/FSx へ、ネットワーク回線経由で並列高速転送・増分同期・データ整合性検証・スケジュール実行を提供し、継続的な同期に適する。A は一括物理搬送向けで定期増分同期には非効率、C は非現実的、D はバックアップ/仮想テープ用途。参照: AWS DataSync。
</details>

### Q14. [Domain 4] Snow ファミリーによるオフライン移行
ネットワーク帯域が乏しい遠隔拠点から 500 TB のデータを AWS に移行する必要がある。回線での転送では数か月かかると試算された。最も現実的な方法はどれか。

- A. AWS DataSync で回線経由転送する
- B. Direct Connect を新設して転送する
- C. AWS Snowball Edge デバイスを取り寄せてローカルにデータをコピーし、物理的に AWS へ搬送してインポートする
- D. VPN を追加して並列で転送する

<details><summary>解答・解説</summary>

**正解: C**

帯域が乏しく回線転送に数か月かかる大容量オフライン移行は Snow ファミリー（Snowball Edge 等）の物理搬送が適し、数日〜数週間で S3 に取り込める。A/B/D はいずれも限られた回線帯域に依存し時間・コストの制約を解消できない。参照: AWS Snowball Edge、Snow Family。
</details>

### Q15. [Domain 4] Strangler Fig とコンテナ化による最新化
モノリシックなオンプレ Java アプリを、リスクを抑えながら段階的にマイクロサービス化して AWS 上でコンテナ運用したい。全面書き換えは避けたい。適切なアプローチはどれか。

- A. モノリスを一括で書き直し、完成後に一度で切り替える（ビッグバン移行）
- B. Strangler Fig パターンで機能を少しずつ切り出して Amazon ECS/EKS 上のマイクロサービスに移し、ルーティング層で新旧に振り分けながら段階的に置き換える
- C. モノリスをそのまま 1 つの巨大な Lambda 関数に載せる
- D. モノリスを EC2 にリホストするだけで最新化完了とする

<details><summary>解答・解説</summary>

**正解: B**

Strangler Fig パターンは、API Gateway/ALB 等のルーティング層で新旧を振り分けつつ機能単位で段階的にマイクロサービス（ECS/EKS コンテナ）へ移行し、最終的にモノリスを「絞め殺す」ため、リスクを抑えた最新化ができる。A は高リスク、C は Lambda の実行時間/サイズ制約に反し不適、D はリホストのみで最新化にならない。参照: Strangler Fig パターン、Amazon ECS/EKS。
</details>

---

## Domain 2（新規ソリューション）・Domain 3（継続的改善）

### Q16. [Domain 2] HA/DR - Warm Standby と RTO/RPO
ある企業は EC2 上で稼働する 3 層 Web アプリケーションを別リージョンへの災害復旧対応させたい。要件は RTO 数分、RPO 数秒で、平常時のコストは最小限に抑えたい。DR リージョンには常に縮小構成のスタックを稼働させておく方針である。この要件に最も適合する DR 戦略はどれか。

- A. Backup and Restore（AMI とスナップショットを定期取得し障害時に構築）
- B. Pilot Light（DB のみ複製し、アプリ層は障害時に起動）
- C. Warm Standby（縮小版フルスタックを常時稼働させ障害時にスケールアップ）
- D. Multi-site active-active（両リージョンで本番同等を稼働）

<details><summary>解答・解説</summary>

**正解: C**

Warm Standby は縮小版の完全なスタック（全層）を常時稼働させておき、フェイルオーバー時にスケールアップするため、数分の RTO と常時稼働による低い RPO を満たしつつ、active-active より低コストである。Backup and Restore と Pilot Light はアプリ層の起動・構築に時間がかかり RTO 数分を満たしにくい。active-active はコストが最も高く「平常時コスト最小」の要件に反する。参照: AWS DR 戦略。
</details>

### Q17. [Domain 2] Aurora Global Database
グローバル展開する金融アプリで、主リージョンの Aurora PostgreSQL に対し、別リージョンで読み取りレイテンシーを下げつつ、リージョン障害時に RPO 1 秒未満・RTO 1 分程度で昇格したい。マネージドで最小の運用負荷が求められる。最適な構成はどれか。

- A. Aurora のクロスリージョンリードレプリカをバイナリログレプリケーションで作成する
- B. Aurora Global Database をセカンダリリージョンに構成する
- C. RDS Multi-AZ をセカンダリリージョンにも独立して構築し、アプリで同期する
- D. DynamoDB Global Tables に移行する

<details><summary>解答・解説</summary>

**正解: B**

Aurora Global Database は専用インフラによるストレージレベルレプリケーションで、通常 1 秒未満のレプリケーション遅延と高速なマネージドフェイルオーバー（昇格）を提供し、リモートリージョンの読み取りレイテンシーも低減する。従来のクロスリージョンリードレプリカ (A) は遅延が大きく昇格も遅い。C は同期の実装負荷が高い。D はリレーショナル要件に合わない。参照: Amazon Aurora Global Database。
</details>

### Q18. [Domain 2] DynamoDB Global Tables
複数リージョンのユーザーが同一データを読み書きするモバイルバックエンドを設計している。各リージョンでローカルな低レイテンシー読み書きを実現し、リージョン間で自動的にデータを双方向レプリケートしたい。運用負荷を最小にする選択はどれか。

- A. 単一リージョンの DynamoDB テーブル + DAX
- B. DynamoDB Global Tables（マルチリージョン、マルチアクティブ）
- C. DynamoDB + Lambda で自作のクロスリージョンレプリケーション
- D. DynamoDB Streams を Kinesis 経由で他リージョンへ手動反映

<details><summary>解答・解説</summary>

**正解: B**

DynamoDB Global Tables はマルチアクティブなマルチリージョンレプリケーションをフルマネージドで提供し、各リージョンでローカル読み書きを可能にする（Last Writer Wins による競合解決）。C・D は自作となり運用負荷が高く整合性管理も複雑。A は単一リージョンのためマルチリージョン低レイテンシー要件を満たさない。参照: DynamoDB Global Tables。
</details>

### Q19. [Domain 2] サーバーレス - SQS と DLQ
Lambda が SQS 標準キューからメッセージを処理するが、特定の不正メッセージで繰り返し失敗し、正常メッセージの処理まで滞留している。失敗メッセージを隔離し、正常処理への影響を減らす設計として最適なものはどれか。

- A. SQS キューの可視性タイムアウトを 0 にする
- B. SQS に Dead Letter Queue を設定し maxReceiveCount を超えたメッセージを退避する
- C. Lambda の同時実行数を 1 に固定する
- D. FIFO キューに変更する

<details><summary>解答・解説</summary>

**正解: B**

DLQ を設定し maxReceiveCount を超えて処理失敗したメッセージを自動退避すれば、毒メッセージ（poison message）が正常処理をブロックせず、後で個別調査できる。A は同一メッセージが即再配信され問題を悪化させる。C はスループットを下げるだけで根本解決にならない。D は順序保証を加えるが失敗メッセージの滞留は解決しない。参照: Amazon SQS Dead Letter Queue。
</details>

### Q20. [Domain 2] イベント駆動 - SNS ファンアウトと EventBridge
注文イベントを、(1) 複数の内部マイクロサービスへ同報配信し、かつ (2) イベントの属性内容（例: 金額が閾値以上）に基づいて異なる SaaS パートナーへルーティングしたい。それぞれに最適なサービスの組み合わせを2つ選択してください。

- A. 内部サービスへの同報には SNS のトピック + 複数 SQS サブスクリプション（ファンアウト）
- B. 内部サービスへの同報には単一の SQS キューを共有させる
- C. 属性ベースの高度なルーティングには EventBridge のイベントバス + ルール
- D. 属性ベースのルーティングには SNS のメッセージフィルタリングのみで SaaS パートナーへ直接配信
- E. 属性ベースのルーティングには Kinesis Data Streams

<details><summary>解答・解説</summary>

**正解: A, C**

SNS のトピックに複数の SQS をサブスクライブするファンアウトは、複数の内部コンシューマーへの信頼性の高い同報配信の定番パターンである。EventBridge はイベントのペイロード内容に対する詳細なパターンマッチングと SaaS パートナー含む多様なターゲットへのルーティングに優れる。B は 1 コンシューマーしか扱えず同報にならない。D は SNS フィルタが属性ベースで限定的、SaaS 連携や内容ベースルーティングは EventBridge が適す。参照: Amazon SNS, Amazon EventBridge。
</details>

### Q21. [Domain 2] Step Functions と人的承認
複数の Lambda と外部承認ステップを含む長時間の業務ワークフローを構築する。途中で人間の承認（メール返信で数時間〜数日かかる場合あり）を待ち、承認後に後続処理を続けたい。最小の運用負荷で状態管理する方法はどれか。

- A. Lambda 内で承認をポーリングし、待機中も実行し続ける
- B. Step Functions のコールバックパターン（waitForTaskToken）を使い、トークン受領で再開する
- C. SQS の遅延キューで固定時間待ってから続行する
- D. EC2 上で常駐ワーカーを動かしステータスを管理する

<details><summary>解答・解説</summary>

**正解: B**

Step Functions の `.waitForTaskToken` コールバックパターンは、タスクトークンを外部へ渡し、承認完了時に `SendTaskSuccess` で返すことでワークフローを再開でき、最長 1 年まで待機可能でマネージドに状態を保持する。A は Lambda の最大 15 分制限を超えられずコストも無駄。C は不定期な承認に固定待機は不適。D は運用負荷が高い。参照: AWS Step Functions callback pattern。
</details>

### Q22. [Domain 2] コンテナ - ECS Fargate vs EKS
チームはコンテナ化したステートレス API を最小の運用負荷で稼働させたい。Kubernetes の専門知識はなく、EC2 インスタンスの管理やパッチ適用も避けたい。トラフィックに応じて自動スケールさせたい。最適な選択はどれか。

- A. Amazon EKS + セルフマネージド EC2 ノードグループ
- B. Amazon ECS on AWS Fargate
- C. Amazon EKS + マネージドノードグループ（EC2）
- D. EC2 上に自前で Docker を構築

<details><summary>解答・解説</summary>

**正解: B**

ECS on Fargate はサーバーレスなコンテナ実行環境で、EC2 のプロビジョニング・パッチ・スケーリング管理が不要、かつ Kubernetes の学習コストもない。A・C はいずれも EC2 ノード（およびK8s）の管理が残る。D は運用負荷が最大。参照: Amazon ECS, AWS Fargate。
</details>

### Q23. [Domain 2] KMS マルチリージョンと Secrets Manager
アプリを 2 リージョンで active-active 展開し、両リージョンで同一の暗号化データを復号できる必要がある。また DB 認証情報は自動ローテーションしたい。適切な組み合わせを2つ選択してください。

- A. KMS マルチリージョンキー（プライマリ + レプリカキー）で両リージョンから同一暗号文を復号する
- B. 各リージョンで独立した単一リージョン KMS キーを作り、暗号文を復号時に相互変換する
- C. Secrets Manager のマネージドローテーション（Lambda ローテーション関数）で DB 認証情報を自動ローテーションする
- D. 認証情報を KMS で暗号化して S3 に置き、手動で更新する
- E. Systems Manager Parameter Store の SecureString でローテーションを有効化する

<details><summary>解答・解説</summary>

**正解: A, C**

KMS マルチリージョンキーは同じキーマテリアルをリージョン間で複製するため、あるリージョンで暗号化したデータを別リージョンのレプリカキーで復号でき、active-active に適する。Secrets Manager は RDS 等に対しローテーション用 Lambda を用いた自動ローテーションをネイティブに提供する。B は暗号文の相互復号ができず非現実的。E は Parameter Store 自体にローテーション機能はない。参照: AWS KMS multi-Region keys, AWS Secrets Manager rotation。
</details>

### Q24. [Domain 2] エッジセキュリティ - WAF と Shield Advanced
公開 Web アプリを ALB と CloudFront 経由で提供している。SQL インジェクションや不正な HTTP リクエストをブロックしつつ、大規模な L3/L4 DDoS 攻撃に対する高度な保護と DDoS 費用補償を得たい。適切な組み合わせを2つ選択してください。

- A. AWS WAF の Web ACL（マネージドルール含む）を CloudFront/ALB に関連付ける
- B. Security Group のインバウンドで攻撃元 IP を都度ブロックする
- C. AWS Shield Advanced を有効化する
- D. AWS Shield Standard のみに依存し追加設定は不要とする
- E. Network ACL でアプリ層攻撃をフィルタする

<details><summary>解答・解説</summary>

**正解: A, C**

AWS WAF は SQLi/XSS などの L7 攻撃をルール（マネージドルール含む）でブロックできる。Shield Advanced は高度な L3/L4 DDoS 保護、24x7 DRT サポート、DDoS 起因のスケーリング費用補償を提供する。B は運用が手動で追いつかない。D の Standard は基本保護のみで費用補償や高度機能がない。E の NACL はステートレスで L7 攻撃には無力。参照: AWS WAF, AWS Shield Advanced。
</details>

### Q25. [Domain 3] コスト最適化 - Savings Plans vs RI vs Spot
ある企業のワークロードは、(1) 24 時間安定稼働する Fargate/Lambda/EC2 混在のベースライン、(2) 中断耐性のあるバッチ処理、で構成される。最もコスト効率よく、かつ柔軟性を保つ選択の組み合わせはどれか。2つ選択してください。

- A. ベースラインには Compute Savings Plans を購入する
- B. ベースラインには Standard RI を各インスタンスタイプ個別に購入する
- C. 中断耐性のあるバッチには Spot Instances / Spot を使う
- D. すべて On-Demand のままにする
- E. 中断耐性のあるバッチにも 3 年 All Upfront の Standard RI を購入する

<details><summary>解答・解説</summary>

**正解: A, C**

Compute Savings Plans は EC2 だけでなく Fargate と Lambda にも適用され、インスタンスファミリー/リージョン/サービスをまたいだ柔軟性を保ちつつ割引を得られるため混在ベースラインに最適。中断耐性のあるバッチは Spot で最大約 90% の割引を得られる。B は柔軟性が低い。E は中断され得るバッチに長期固定コミットは不適。D は割引機会を逃す。参照: AWS Savings Plans, Amazon EC2 Spot。
</details>

### Q26. [Domain 3] S3 ストレージクラスとライフサイクル
アクセスパターンが予測不能なデータと、90 日後にほぼアクセスされず数年間保持義務のある監査ログが混在する S3 バケットがある。運用の手間なくコストを最適化したい。適切な設定はどれか。

- A. すべて S3 Standard に置き続ける
- B. アクセス不定のデータは S3 Intelligent-Tiering、監査ログはライフサイクルで一定日数後に Glacier Flexible Retrieval / Deep Archive へ移行する
- C. すべて S3 One Zone-IA に移行する
- D. すべて即座に Glacier Deep Archive に移行する

<details><summary>解答・解説</summary>

**正解: B**

アクセスパターンが読めないデータは Intelligent-Tiering が自動で最適な階層へ移動し、監視のみで手動管理不要。長期保持でアクセス頻度が低い監査ログはライフサイクルルールで Glacier 系へ移行してコスト削減できる。A はコスト過大。C は単一 AZ で耐久性リスク、頻繁アクセスにも不適。D は監査ログの初期 90 日アクセスに取り出しコスト/遅延が発生し不適。参照: S3 Intelligent-Tiering, S3 Lifecycle。
</details>

### Q27. [Domain 3] パフォーマンス - CloudFront vs Global Accelerator
グローバルユーザー向けに、TCP/UDP ベースの非 HTTP なリアルタイムゲーム API を提供している。世界中からの接続で低レイテンシーと高速フェイルオーバー、静的 Anycast IP を求めている。最適なサービスはどれか。

- A. Amazon CloudFront
- B. AWS Global Accelerator
- C. Route 53 レイテンシールーティングのみ
- D. リージョンごとに個別 ALB を公開しクライアントで切替

<details><summary>解答・解説</summary>

**正解: B**

Global Accelerator は静的 Anycast IP を提供し、AWS のグローバルネットワーク経由で TCP/UDP を含む非 HTTP トラフィックを最寄りエッジから最適経路でルーティングし、高速なリージョンフェイルオーバーを行う。CloudFront は主に HTTP(S) のコンテンツ配信/キャッシュ向けで、任意 TCP/UDP のリアルタイム API には不適。C は DNS キャッシュにより切替が遅い。D はクライアント側実装負荷が高い。参照: AWS Global Accelerator。
</details>

### Q28. [Domain 3] デプロイ - Blue/Green とカナリア
本番の Lambda ベース API で、新バージョンをリリースする際に一部トラフィックのみで検証し、CloudWatch アラームで問題を検知したら自動ロールバックしたい。最小の運用負荷で実現する方法はどれか。

- A. Lambda のエイリアスと加重ルーティング + CodeDeploy のカナリアデプロイ（Canary10Percent…）+ CloudWatch アラームで自動ロールバック
- B. 新旧を別関数として作り、クライアント側で切り替える
- C. 全トラフィックを一度に新バージョンへ切り替える（All-at-once）
- D. Auto Scaling グループのローリング更新を使う

<details><summary>解答・解説</summary>

**正解: A**

Lambda エイリアスの加重ルーティングと CodeDeploy のカナリア（例: Canary10Percent5Minutes）を組み合わせると、一部トラフィックで新バージョンを検証し、関連付けた CloudWatch アラームが発報した場合に自動ロールバックできる。B はクライアント改修が必要。C は段階検証がなくリスク大。D は Lambda ではなく EC2 向けの手法。参照: AWS CodeDeploy for Lambda, Lambda alias traffic shifting。
</details>

### Q29. [Domain 3] 運用改善 - Config と Systems Manager
数百アカウントのマルチアカウント環境で、(1) リソース構成のコンプライアンス（例: 暗号化されていない EBS の検出と自動修復）、(2) EC2 フリートへの一括パッチ適用を、中央集権的かつ自動で実施したい。適切な組み合わせを2つ選択してください。

- A. AWS Config のマネージドルール + 自動修復（SSM Automation）で非準拠リソースを検出・是正する
- B. CloudTrail のログを人手で毎日確認して是正する
- C. Systems Manager Patch Manager + パッチベースラインとメンテナンスウィンドウで一括パッチ適用する
- D. 各 EC2 に SSH して手動で yum update する
- E. GuardDuty でパッチ適用状況を管理する

<details><summary>解答・解説</summary>

**正解: A, C**

AWS Config のルールで非準拠リソース（例: 非暗号化 EBS）を継続評価し、SSM Automation ドキュメントによる自動修復を紐づければ検出と是正を自動化できる（Organizations で集約可能）。Systems Manager Patch Manager はパッチベースラインとメンテナンスウィンドウでフリート全体のパッチ適用をスケジュール実行できる。B・D は手動でスケールしない。E の GuardDuty は脅威検知であってパッチ管理機能ではない。参照: AWS Config remediation, SSM Patch Manager。
</details>

### Q30. [Domain 3] RDS Multi-AZ vs リードレプリカ + ElastiCache
既存の RDS MySQL が、読み取り負荷急増でレイテンシー悪化と AZ 障害時のダウンタイムに悩んでいる。可用性と読み取りスケーラビリティの両方を改善したい。最適な組み合わせを2つ選択してください。

- A. RDS Multi-AZ 配置を有効化して AZ 障害時の自動フェイルオーバーを得る
- B. リードレプリカを追加し読み取りクエリを振り分けて読み取りをスケールする（必要に応じ ElastiCache でキャッシュ）
- C. Multi-AZ のスタンバイをアプリの読み取りに使ってスケールする
- D. インスタンスを毎回手動で垂直スケールアップして対処する
- E. 単一 AZ のまま自動バックアップ頻度だけ上げる

<details><summary>解答・解説</summary>

**正解: A, B**

Multi-AZ は同期スタンバイへ自動フェイルオーバーして AZ 障害時の可用性を高める（ただしスタンバイは読み取りに使えない）。読み取りスケールにはリードレプリカへ読み取りを振り分け、ElastiCache でホットデータをキャッシュしてさらに DB 負荷を軽減する。C は Multi-AZ スタンバイが読み取りに使えないため誤り。D は運用負荷が高くスパイクに追随しにくい。E は可用性もスケールも解決しない。参照: RDS Multi-AZ, RDS Read Replica, Amazon ElastiCache。
</details>

---

*このクイズはオリジナル問題です。継続的に追加・修正して自分専用の問題集に育ててください。*
