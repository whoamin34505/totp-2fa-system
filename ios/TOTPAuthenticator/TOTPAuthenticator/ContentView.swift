//
//  ContentView.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 10.11.2026.
//

import SwiftUI
import UIKit

struct Account: Identifiable {
    let id = UUID()
    let login: String
    let service: String
    let code: String
}

struct ContentView: View {
    @State private var isEditing = false
    @State private var isCopied = false
    @State private var hideTask: Task<Void, Never>?
    let accounts = [
        Account(login:"kolyan",service: "GitHub",code: "020 202"),
        Account(login: "nikolay@gmail.com", service: "Google", code: "123 456"),
        Account(login: "admin", service: "Microsoft", code: "987 654")]
    var body: some View {
        VStack {
            TimelineView(.animation) { context in

                let seconds = Int(context.date.timeIntervalSince1970)
                let passed = seconds % 30
                let left = 30 - passed
                
                let passedExact = context.date.timeIntervalSince1970
                    .truncatingRemainder(dividingBy: 30.0)

                let remainingExact = 30.0 - passedExact

                let progress = remainingExact / 30.0

                let color = progressColor(left: left)

                ProgressView(value: progress)
                   
                    .tint(color)
                    .sensoryFeedback(.impact(weight: .light), trigger: left) { old, new in
                        old != new && (1...5).contains(new)
                    }
            }
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
            ForEach (accounts) { account in
                Button {
                    UIPasteboard.general.string = account.code.replacingOccurrences(of: " ", with: "")
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
                        Text(account.code)
                            .font(.title2)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                Divider()
            }
            .padding(.horizontal)
            if isCopied {
                Text("Скопировано")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer()
        }
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
