//
//  ContentView.swift
//  TOTPAuthenticator
//
//  Created by whoamin on 10.11.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var isEditing = false
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
            HStack {
                VStack
                {
                    Text("kolyan")
                    Text("GitHub")
                }
                Spacer()
                Text("020202")
            }
            .padding()
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
