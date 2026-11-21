//
//  ContentView.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 10.11.2026.
//

import SwiftUI
import UIKit

struct Account: Codable, Identifiable {
    let id : String
    let login: String
    let service: String
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var isCopied = false
    @State private var showAddMenu = false
    @State private var service = ""
    @State private var login = ""
    @State private var secret = ""
    @State private var hideTask: Task<Void, Never>?
    @State private var totpCodes: [String: String] = [:]
    @State private var accounts: [Account] = []
    
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
    
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Главная", systemImage: "house.fill", value: 0) {
                NavigationStack {
                    homeView
                }
            }

            Tab("Добавить", systemImage: "plus.circle.fill", value: 1) {
                addAccountView
            }

            Tab("Настройки", systemImage: "gearshape.fill", value: 2) {
                NavigationStack {
                    ContentUnavailableView(
                        "Настройки пока недоступны",
                        systemImage: "gearshape"
                    )
                    .navigationTitle("Настройки")
                }
            }
        }.onAppear {
            loadAccounts()
            updateCodes()
        }
        .onChange(of: selectedTab) {
            if selectedTab == 1 {
                showAddMenu = true
                selectedTab = 0
            }
        }
        .confirmationDialog("test",isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("Ввести вручную") {}
            Button("Отсканировать QR-код") {}
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
}

#Preview {
    ContentView()
}
