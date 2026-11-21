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
    @State private var cameraAuthorized = false
    @State private var showManualAdd = false
    @State private var isCopied = false
    @State private var service = ""
    @State private var login = ""
    @State private var secret = ""
    @State private var hideTask: Task<Void, Never>?
    @State private var totpCodes: [String: String] = [:]
    @State private var accounts: [Account] = []
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("faceIDEnabled") private var faceIDEnabled = false
    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var shouldAutoAuthenticate = true
    @Environment(\.scenePhase) private var scenePhase

    private var isLocked: Bool {
        faceIDEnabled && !isUnlocked
    }

    private var showBlur: Bool {
        isLocked || (scenePhase != .active && !isAuthenticating)
    }

    private func checkCameraPermission() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
    }
    
    private func updateCodes() {
        for account in accounts {
            let store = KeychainStore()
            if let secret = store.readSecret(accountID: account.id) {
                if let decoded_secret = Base32Decoder().decode(secret) {
                    let code = TOTP().generate(key: decoded_secret)
                    totpCodes[account.id] = code
                } else {
                    print("Ошибка декодирования")
                }
                
            } else {
                print("Секрет не найден")
            }
        }
    }
    
    private func addAccount() {
        if service.isEmpty || login.isEmpty || secret.isEmpty {
            return
        }
        guard let decodedSecret = Base32Decoder().decode(secret) else {
            print("Некорректный Base32-секрет")
            return
        }
        let id = UUID().uuidString
        let store = KeychainStore()
        guard store.saveSecret(secret, accountID: id) else {
            print("Не удалось сохранить секрет")
            return
        }
        accounts.append(Account(id: id, login: login, service: service))
        saveAccounts()
        totpCodes[id] = TOTP().generate(key: decodedSecret)
        service = ""
        login = ""
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
            print("Не удалось декодировать аккаунты: \(error)")
            accounts = []
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        let ids = offsets.map { accounts[$0].id }
        for id in ids {
            let store = KeychainStore()
            if store.deleteSecret(accountID: id) {
                accounts.removeAll { account in
                    account.id == id
                }
                totpCodes.removeValue(forKey: id)
            }
        }
        saveAccounts()
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
        } catch {
            print("Ошибка Face ID: \(error)")
            return false
        }
    }

    private func unlockIfNeeded() async {
        guard isLocked, shouldAutoAuthenticate, !isAuthenticating else { return }
        shouldAutoAuthenticate = false

        if await authenticate() {
            withAnimation(.easeInOut(duration: 0.25)) {
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
                        }
                    }
                    .navigationTitle("Настройки")
                }
            }
        }
        .onAppear {
            loadAccounts()
            updateCodes()
        }
        .sheet(isPresented: $showManualAdd) {
            addAccountView
        }
        .task(id: selectedTab) {
            if selectedTab == 1 {
                await checkCameraPermission()
            }
        }
        .blur(radius: showBlur ? 24 : 0)
        .allowsHitTesting(!showBlur)
        .overlay {
            if showBlur {
                privacyView
                    .transition(.opacity)
            }
        }
        .overlay {
            if isLocked {
                lockView
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showBlur)
        .preferredColorScheme(
            appTheme == "dark" ? .dark :
            appTheme == "light" ? .light : nil
        )
        .task {
            await unlockIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && faceIDEnabled {
                isUnlocked = false
                shouldAutoAuthenticate = true
            } else if newPhase == .active {
                Task {
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
                    .onChange(of: period, initial: true) { old, new in
                        updateCodes()
                    }
            }
            HStack {
                Text("Аккаунты")
                    .font(.title2)
                Spacer()
                EditButton().buttonStyle(.glass)
            }
            .padding()
            List {
                ForEach (accounts) { account in
                    Button {
                        if let code = totpCodes[account.id] {
                            UIPasteboard.general.string = code
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                            hideTask?.cancel()
                            withAnimation(.easeInOut(duration: 0.1)) {
                                isCopied = true
                            }
                            print("Код скопирован в буфер обмена")
                            hideTask = Task {
                                do {
                                    try await Task.sleep(for: .seconds(2))
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isCopied = false
                                    }
                                } catch {
                                    return
                                }
                            }
                        }
                    } label: {
                        HStack {
                            VStack (alignment: .leading)
                            {
                                Text(account.login)
                                    .fontWeight(.semibold)
                                Text(account.service)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(totpCodes[account.id] ?? "— — — — — —")
                                .font(.title2)
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }.onDelete(perform: deleteAccounts)
                    .onMove(perform: moveAccounts)
            }.listStyle(.plain)
            if isCopied {
                Text("Скопировано")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
        }
    }

    private var addAccountView: some View {
        VStack {
            Text("Добавление аккаунта").font(.title2)
            TextField("Название сервиса", text: $service).textFieldStyle(.roundedBorder)
            TextField("Название аккаунта", text: $login).textFieldStyle(.roundedBorder)
            TextField("Секрет", text: $secret).textFieldStyle(.roundedBorder)
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
                        withAnimation(.easeInOut(duration: 0.25)) {
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
        .transition(.opacity)
    }

    private var privacyView: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }

    private var scannerView: some View {
        VStack(spacing: 20) {
            Text("Сканирование QR-кода")
                .font(.title2.bold())

            if cameraAuthorized
                && DataScannerViewController.isSupported
                && DataScannerViewController.isAvailable {

                ZStack {
                    QRScannerView(isActive: selectedTab == 1 && !showManualAdd && !showBlur) { payload in

                        guard let result = OTPAuthParser().parse(payload) else {
                            print("Некорректный или неподдерживаемый TOTP QR-код")
                            return
                        }

                        service = result.service
                        login = result.login
                        secret = result.secret

                        showManualAdd = true
                    }
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
            } else {
                Text("Камера недоступна. Проверьте разрешение в настройках iPhone и перезапустите приложение.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Ввести вручную") {
                showManualAdd = true
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.top)
    }
}

#Preview {
    ContentView()
}
