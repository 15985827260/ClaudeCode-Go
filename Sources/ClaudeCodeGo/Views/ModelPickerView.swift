import SwiftUI

/// Dropdown for selecting a model, grouped by category.
struct ModelPickerView: View {
    @Binding var selectedModel: ModelOption
    let models: [ModelOption]
    let onSwitch: (ModelOption) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("当前模型", systemImage: "cpu")
                .font(.headline)
                .foregroundColor(.secondary)

            Picker(selection: $selectedModel) {
                ForEach(ModelCategory.allCases, id: \.self) { category in
                    Section {
                        ForEach(models.filter { $0.category == category }) { model in
                            HStack {
                                Text(model.name)
                                Text("— \(model.description)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(model)
                        }
                    } header: {
                        Text(category.rawValue)
                    }
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedModel) { newModel in
                onSwitch(newModel)
            }

            Text(selectedModel.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.controlBackgroundColor))
        )
    }
}
