//
//  ContentView.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 10.11.2026.
//

import SwiftUI

struct Account: Identifiable {
    let id = UUID()
    let login: String
    let service: String
    let code: String
}

struct ContentView: View {
    @State private var isEditing = false
    let services = ["Apple", "Google", "Microsoft"]
    let accounts = [
        Account(login:"kolyan",service: "GitHub",code: "020 202"),
        Account(login: "nikolay@gmail.com", service: "Google", code: "123 456"),
        Account(login: "admin", service: "Microsoft", code: "987 654")]
    var body: some View {
        VStack {
            HStack {
                Text("Аккаунты")
                    .font(.title2)
                Spacer()
                if isEditing {
                    Button("Готово") {
                        print("Режим редактирования завершен")
                        isEditing.toggle()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                else {
                    Button("Изменить") {
                        print("Режим редактирования")
                        isEditing.toggle()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
            }
            .padding()
            ForEach (accounts) {account in
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
                    Text(account.code)
                        .font(.title2)
                }
            }
            .padding()
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
