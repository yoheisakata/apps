import SwiftUI

struct AppUninstallerView: View {
    @StateObject private var vm = AppViewModel()
    @ObservedObject private var jobRunner = JobRunner.shared
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .alert("アプリをゴミ箱に移動しますか？", isPresented: $showConfirm) {
            Button("キャンセル", role: .cancel) {}
            Button("ゴミ箱に移動", role: .destructive) {
                Task { await vm.uninstall() }
            }
        } message: {
            Text(confirmMessage)
        }
        .alert("削除できなかった項目があります", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var confirmMessage: String {
        let appCount = vm.selectedApps.count
        let leftoverCount = vm.pendingLeftovers.count
        var text = "\(appCount) 個のアプリ（約 \(ByteFmt.string(vm.selectedSize))）"
        if leftoverCount > 0 {
            text += " と関連ファイル \(leftoverCount) 件"
        }
        text += " をゴミ箱へ移動します。ゴミ箱を空にするまで復元できます。"
        return text
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("アプリのアンインストール")
                    .font(.headline)
                if vm.hasScanned {
                    Text("\(vm.apps.count) 個のアプリ / 選択中 \(vm.selectedApps.count) 個（\(ByteFmt.string(vm.selectedSize))）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("インストール済みアプリを一覧表示します")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await vm.scan() }
            } label: {
                Label("スキャン", systemImage: "magnifyingglass")
            }
            .disabled(vm.isScanning || vm.isCleaning)

            Button(role: .destructive) {
                if jobRunner.isRunning {
                    vm.errorMessage = "他の処理(\(jobRunner.title))を実行中です。完了してからもう一度お試しください。"
                } else {
                    Task {
                        await vm.prepareLeftovers()
                        showConfirm = true
                    }
                }
            } label: {
                Label("アンインストール", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.hasSelection || vm.isScanning || vm.isCleaning)
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isScanning {
            Spacer()
            ProgressView("アプリをスキャン中…")
            Spacer()
        } else if vm.isCleaning {
            Spacer()
            ProgressView("ゴミ箱へ移動中…")
            Spacer()
        } else if !vm.hasScanned {
            emptyState
        } else {
            List {
                ForEach($vm.apps) { $app in
                    appRow($app)
                }
            }
            .listStyle(.inset)
            if !vm.status.isEmpty {
                Text(vm.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
    }

    private func appRow(_ app: Binding<InstalledApp>) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: app.isSelected) { EmptyView() }
                .labelsHidden()

            if let icon = app.wrappedValue.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(app.wrappedValue.name)
                    .font(.body)
                Text(subtitle(for: app.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFmt.string(app.wrappedValue.size))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for app: InstalledApp) -> String {
        var parts: [String] = []
        if let version = app.version { parts.append("v\(version)") }
        parts.append(app.url.deletingLastPathComponent().path)
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "app.badge")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("「スキャン」を押してアプリ一覧を取得してください。")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
