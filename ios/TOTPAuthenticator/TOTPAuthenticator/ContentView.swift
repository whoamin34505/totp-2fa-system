//
//  ContentView.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 10.11.2026.
//

import SwiftUI
import UIKit
import VisionKit
import AVFoundation
import LocalAuthentication

struct Account: Codable, Identifiable {
    let id : String
    let login: String
    let service: String
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var cameraAuthorization: AVAuthorizationStatus?
    @State private var scannerFailed = false
    @State private var showManualAdd = false
    @State private var isCopied = false
    @State private var service = ""
    @State private var login = ""
    @State private var secret = ""
    @State private var hideTask: Task<Void, Never>?
    @State private var userAlert: UserAlert?
    @State private var addAccountAlert: UserAlert?
    @State private var accountsToDelete: [Account] = []
    @State private var showDeleteConfirmation = false
    @State private var totpCodes: [String: String] = [:]
    @State private var accounts: [Account] = []
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var shouldAutoAuthenticate = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct UserAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String

        var presentation: Alert {
            Alert(title: Text(title), message: Text(message), dismissButton: .default(Text("Понятно")))
        }
    }

    private var isLocked: Bool {
        faceIDEnabled && !isUnlocked
    }

    private var showBlur: Bool {
        isLocked || (scenePhase != .active && !isAuthenticating)
    }

    private func checkCameraPermission() async {
        guard DataScannerViewController.isSupported else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard !Task.isCancelled else { return }
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    private func updateCodes() {
        let store = KeychainStore()
        var codes: [String: String] = [:]
        for account in accounts {
            if let secret = store.readSecret(accountID: account.id),
               let key = Base32Decoder().decode(secret) {
                codes[account.id] = TOTP().generate(key: key)
            }
        }
        totpCodes = codes
    }
    
    private func addAccount() {
        let serviceName = service.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !serviceName.isEmpty, !accountLogin.isEmpty, !accountSecret.isEmpty else {
            addAccountAlert = UserAlert(
                title: "Заполните все поля",
                message: "Укажите название сервиса, название аккаунта и секрет."
            )
            return
        }
        guard let key = Base32Decoder().decode(accountSecret) else {
            addAccountAlert = UserAlert(
                title: "Неверный секрет",
                message: "Проверьте ключ настройки, который выдал сервис. Ожидается ключ в формате Base32."
            )
            return
        }
        let id = UUID().uuidString
        let store = KeychainStore()
        guard store.saveSecret(accountSecret, accountID: id) else {
            addAccountAlert = UserAlert(
                title: "Не удалось добавить аккаунт",
                message: "Не удалось сохранить секрет в Связке ключей. Попробуйте ещё раз."
            )
            return
        }
        accounts.append(Account(id: id, login: accountLogin, service: serviceName))
        saveAccounts()
        totpCodes[id] = TOTP().generate(key: key)
        secret = ""
        selectedTab = 0
        showManualAdd = false
    }
    
    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "accounts")
        }
    }
    
    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: "accounts") else {
            accounts = []
            return
        }
        do {
            accounts = try JSONDecoder().decode([Account].self, from: data)
        } catch {
            accounts = []
            userAlert = UserAlert(
                title: "Не удалось загрузить аккаунты",
                message: "Перезапустите приложение и попробуйте снова."
            )
        }
    }

    private func deleteAccounts(_ selection: [Account]) {
        let store = KeychainStore()
        var deleteFailed = false

        for account in selection {
            if store.deleteSecret(accountID: account.id) {
                accounts.removeAll { $0.id == account.id }
                totpCodes.removeValue(forKey: account.id)
            } else {
                deleteFailed = true
            }
        }
        saveAccounts()

        if deleteFailed {
            userAlert = UserAlert(
                title: "Не удалось завершить удаление",
                message: "Попробуйте ещё раз удалить аккаунты, оставшиеся в списке."
            )
        }
    }
    
    private func moveAccounts(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        saveAccounts()
    }
    
    private func authenticate() async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Разблокируйте доступ к кодам"
            )
        } catch let error as LAError {
            switch error.code {
            case .appCancel, .systemCancel:
                shouldAutoAuthenticate = true
            case .userCancel:
                break
            case .passcodeNotSet:
                userAlert = UserAlert(
                    title: "Требуется код-пароль",
                    message: "Установите код-пароль устройства в настройках iPhone и попробуйте снова."
                )
            default:
                showAuthenticationFailure()
            }
            return false
        } catch {
            showAuthenticationFailure()
            return false
        }
    }

    private func showAuthenticationFailure() {
        userAlert = UserAlert(
            title: "Не удалось подтвердить личность",
            message: "Попробуйте ещё раз с Face ID или кодом-паролем устройства."
        )
    }

    private func unlockIfNeeded() async {
        guard scenePhase == .active, isLocked, shouldAutoAuthenticate, !isAuthenticating,
              userAlert == nil else { return }
        shouldAutoAuthenticate = false

        if await authenticate() {
            withAnimation(.easeOut(duration: 0.45)) {
                isUnlocked = true
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Главная", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    homeView
                }
            }

            Tab("Добавить", systemImage: "plus.circle.fill", value: 1) {
                scannerView
            }

            Tab("Настройки", systemImage: "gearshape.fill", value: 2) {
                NavigationStack {
                    Form {
                        Section("Настройки оформления") {
                            Picker("Тема оформления", selection: $appTheme) {
                                Text("Системная").tag("system")
                                Text("Светлая").tag("light")
                                Text("Тёмная").tag("dark")
                            }
                        }
                        Section("Безопасность") {
                            Toggle("Защита Face ID", isOn: Binding(
                                get: {
                                    faceIDEnabled
                                },
                                set: { newValue in
                                    Task {
                                        if await authenticate() {
                                            faceIDEnabled = newValue
                                            isUnlocked = true
                                        }
                                    }
                                }
                            ))
                            .disabled(isAuthenticating)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        HStack {
                            Text("Настройки")
                                .font(.largeTitle.bold())
                            Spacer()
                        }
                        .padding(.leading, 28)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemGroupedBackground))
                    }
                }
            }
        }
        .onAppear {
            loadAccounts()
            updateCodes()
        }
        .alert(item: $userAlert) { $0.presentation }
        .sheet(isPresented: $showManualAdd, onDismiss: {
            service = ""
            login = ""
            secret = ""
            addAccountAlert = nil
        }) {
            addAccountView
        }
        .task(id: selectedTab) {
            if selectedTab == 1 {
                scannerFailed = false
                await checkCameraPermission()
            }
        }
        .allowsHitTesting(!showBlur)
        .accessibilityHidden(showBlur)
        .overlay {
            SmoothBlurView(isBlurred: showBlur)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlay {
            if isLocked {
                lockView
            }
        }
        .animation(.easeOut(duration: 0.35), value: isLocked)
        .preferredColorScheme(
            appTheme == "dark" ? .dark :
            appTheme == "light" ? .light : nil
        )
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            if newPhase == .background && faceIDEnabled {
                isUnlocked = false
                shouldAutoAuthenticate = true
            } else if newPhase == .active {
                updateCodes()
                if selectedTab == 1 {
                    cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    await unlockIfNeeded()
                }
            }
        }
    }

    private var homeView: some View {
        VStack {
            TimelineView(.animation) { context in
                let seconds = Int(context.date.timeIntervalSince1970)
                let passed = seconds % 30
                let left = 30 - passed
                
                let period = seconds / 30

                let passedExact = context.date.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: 30.0)
                let remainingExact = 30.0 - passedExact
                let progress = remainingExact / 30.0

                let color = progressColor(left: left)

                Rectangle()
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(color)
                            .scaleEffect(x: progress, anchor: .leading)
                    }
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: color)
                    .sensoryFeedback(.impact(weight: .light), trigger: left) { old, new in
                        old != new && (1...5).contains(new)
                    }
                    .onChange(of: period, initial: true) {
                        updateCodes()
                    }
            }
            HStack {
                Text("Аккаунты")
                    .font(.title)
                Spacer()
                EditButton().buttonStyle(.glass)
            }
            .padding()
            List {
                ForEach(accounts) { account in
                    Button {
                        copyCode(for: account)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.login)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                Text(account.service)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            let code = totpCodes[account.id]
                            let formattedCode = code.map { "\($0.prefix(3)) \($0.suffix(3))" } ?? "··· ···"
                            Text(formattedCode)
                                .font(.title)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityLabel(code == nil ? "Код недоступен" : formattedCode)
                                .speechSpellsOutCharacters(code != nil)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                    .buttonStyle(CodeButtonStyle())
                }
                .onDelete { offsets in
                    accountsToDelete = offsets.map { accounts[$0] }
                    showDeleteConfirmation = true
                }
                .onMove(perform: moveAccounts)
            }
            .listStyle(.plain)
        }
        .alert(accountsToDelete.count == 1 ? "Удалить аккаунт?" : "Удалить аккаунты?",
               isPresented: $showDeleteConfirmation) {
            Button("Удалить", role: .destructive) {
                deleteAccounts(accountsToDelete)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            if let account = accountsToDelete.first, accountsToDelete.count == 1 {
                Text("Коды для «\(account.login)» (\(account.service)) больше не будут доступны в приложении.")
            } else {
                Text("Коды для выбранных аккаунтов больше не будут доступны в приложении.")
            }
        }
        .overlay(alignment: .bottom) {
            if isCopied {
                Label {
                    Text("Код скопирован")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.quaternary) }
                .padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }

    private struct CodeButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.45 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }

    private func copyCode(for account: Account) {
        guard let code = totpCodes[account.id] else {
            userAlert = UserAlert(
                title: "Код недоступен",
                message: "Не удалось получить секрет аккаунта из Связки ключей. Попробуйте открыть приложение снова."
            )
            return
        }

        UIPasteboard.general.string = code
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AccessibilityNotification.Announcement("Код скопирован").post()

        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            isCopied = true
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }

    private var addAccountView: some View {
        VStack {
            Text("Добавление аккаунта").font(.title2)
            TextField("Название сервиса", text: $service).textFieldStyle(.roundedBorder)
            TextField("Название аккаунта", text: $login).textFieldStyle(.roundedBorder)
            SecureField("Секрет", text: $secret)
                // iOS не предлагает сохранять секрет как пароль.
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button {
                addAccount()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Добавить")
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding()
        .alert(item: $addAccountAlert) { $0.presentation }
    }

    private func progressColor(left: Int) -> Color {
        if left <= 5 {
            return .red
        } else if left <= 10 {
            return .orange
        } else {
            return .green
        }
    }
    
    private var lockView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)

            Button {
                Task {
                    if await authenticate() {
                        withAnimation(.easeOut(duration: 0.45)) {
                            isUnlocked = true
                        }
                    }
                }
            } label: {
                Label("Разблокировать", systemImage: "faceid")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .disabled(isAuthenticating)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private struct SmoothBlurView: UIViewRepresentable {
        let isBlurred: Bool
        let style: UIBlurEffect.Style = .systemMaterial

        func makeUIView(context: Context) -> UIVisualEffectView {
            let view = UIVisualEffectView(effect: isBlurred ? UIBlurEffect(style: style) : nil)
            view.isUserInteractionEnabled = false
            return view
        }

        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
            let isCurrentlyBlurred = uiView.effect != nil
            guard isCurrentlyBlurred != isBlurred else { return }

            let targetEffect: UIVisualEffect? = isBlurred ? UIBlurEffect(style: style) : nil
            let duration: TimeInterval = isBlurred ? 0.15 : 0.5

            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                uiView.effect = targetEffect
            }
        }
    }

    private var scannerView: some View {
        VStack(spacing: 20) {
            Text("Сканирование QR-кода")
                .font(.title2.bold())

            if !DataScannerViewController.isSupported {
                cameraMessage("Сканирование QR-кодов недоступно на этом устройстве. Добавьте аккаунт вручную.")
            } else if cameraAuthorization == .denied {
                cameraMessage("Разрешите доступ к камере в настройках, чтобы сканировать QR-коды.")
                Button("Открыть настройки") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
            } else if cameraAuthorization == .restricted {
                cameraMessage("Доступ к камере ограничен. Добавьте аккаунт вручную.")
            } else if cameraAuthorization != .authorized {
                ProgressView("Ожидание доступа к камере")
            } else if scannerFailed || !DataScannerViewController.isAvailable {
                cameraMessage("Камера сейчас недоступна. Добавьте аккаунт вручную или попробуйте позже.")
                if scannerFailed {
                    Button("Повторить") {
                        scannerFailed = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ZStack {
                    QRScannerView(
                        isActive: selectedTab == 1 && !showManualAdd && !showBlur && userAlert == nil,
                        onCodeScanned: handleScannedCode,
                        onScannerUnavailable: handleScannerUnavailable
                    )
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 240, height: 240)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 400)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal)

                Text("Поместите QR-код внутрь рамки")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Ввести вручную") {
                showManualAdd = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.top)
    }

    private func cameraMessage(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private func handleScannedCode(_ payload: String) -> Bool {
        guard let result = OTPAuthParser().parse(payload) else {
            userAlert = UserAlert(
                title: "QR-код не поддерживается",
                message: "Поддерживаются QR-коды для TOTP с шестью цифрами, периодом 30 секунд и алгоритмом SHA-1."
            )
            return false
        }

        service = result.service
        login = result.login
        secret = result.secret
        showManualAdd = true
        return true
    }

    private func handleScannerUnavailable() {
        guard selectedTab == 1, !showBlur, !showManualAdd, userAlert == nil else { return }
        scannerFailed = true
        userAlert = UserAlert(
            title: "Не удалось запустить сканирование",
            message: "Попробуйте снова или добавьте аккаунт вручную."
        )
    }
}

#Preview {
    ContentView()
}
