import SwiftUI
import UniformTypeIdentifiers
import XCEngine

/// Pantalla principal: analizar, métricas y ajustes.
public struct RootView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        Group {
            if model.isUnlocked {
                TabView {
                    AnalyzeView(model: model).tabItem { Label("Analizar", systemImage: "text.magnifyingglass") }
                    MetricsView(model: model).tabItem { Label("Aprendizaje", systemImage: "chart.bar") }
                    HealthView(model: model).tabItem { Label("Diagnóstico", systemImage: "stethoscope") }
                    SettingsView(model: model).tabItem { Label("Ajustes", systemImage: "gearshape") }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.largeTitle)
                    Button("Desbloquear") { Task { await model.unlock() } }.buttonStyle(.borderedProminent)
                }.task { await model.unlock() }
            }
        }
    }
}

struct AnalyzeView: View {
    @Bindable var model: AppModel
    @State private var link = ""
    @State private var pasted = ""

    var body: some View {
        VStack(spacing: 0) {
            if !model.hasAPIKey {
                Label("Añade tu clave de la API en Ajustes para empezar.", systemImage: "key").padding(8)
                    .frame(maxWidth: .infinity).background(.yellow.opacity(0.2))
            }
            HStack {
                TextField("Pega el enlace de un post de X", text: $link)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.URL).textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(go)
                Button("Analizar", action: go).buttonStyle(.borderedProminent).disabled(link.isEmpty || model.isBusy)
            }.padding()
            Divider()
            ContextPanelView(model: model)
        }
    }

    func go() {
        let input = PostInput(url: URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)))
        Task { await model.analyze(input) }
    }
}

struct MetricsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Gasto de tus créditos") {
                ProgressView(value: min(model.spend.totalUSD, model.spend.limitUSD), total: max(model.spend.limitUSD, 0.01))
                Text(String(format: "%.2f de %.2f USD · %d análisis · %.3f USD de media", model.spend.totalUSD, model.spend.limitUSD,
                            model.spend.analyses, model.spend.analyses == 0 ? 0 : model.spend.totalUSD / Double(model.spend.analyses)))
                Text("La cifra exacta está en console.anthropic.com → Usage.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lo que la app ha aprendido de ti") {
                Text(String(format: "Usas un borrador en el %.0f%% de los análisis", model.prefs.conversionRate * 100))
                ForEach(DraftStance.allCases, id: \.self) { s in
                    HStack {
                        Text(s.label)
                        ProgressView(value: model.prefs.score(s, topic: ""))
                        Text(String(format: "%.0f%%", model.prefs.score(s, topic: "") * 100)).monospacedDigit()
                    }
                }
                if let l = model.prefs.preferredLength { Text("Longitud que prefieres: ~\(Int(l)) caracteres") }
                if !model.prefs.recentEdits.isEmpty { Text("Aprendiendo de tus últimas \(model.prefs.recentEdits.count) ediciones") }
                ForEach(model.prefs.totals.sorted { $0.value > $1.value }, id: \.key) { k, v in
                    LabeledContent(k.rawValue, value: "\(v)")
                }
            }
            Section("Tu estilo") { Text(model.style.promptDescription()).font(.callout) }
        }
        .formStyle(.grouped)
        .task { await model.refreshMetrics() }
    }
}

struct HealthView: View {
    @Bindable var model: AppModel
    @State private var exported: URL?
    @State private var events: [DiagEvent] = []

    var body: some View {
        Form {
            Section("Estado") {
                ForEach(model.health, id: \.name) { h in
                    VStack(alignment: .leading) {
                        Label("\(h.name): \(h.detail)", systemImage: h.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(h.ok ? .green : .red)
                        if let f = h.fix { Text("Arreglo: \(f)").font(.caption) }
                    }
                }
                Button("Volver a comprobar") { Task { await model.runHealthCheck() } }
            }
            Section("Últimos eventos") {
                ForEach(Array(events.reversed().prefix(40).enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading) {
                        Text("\(e.level.rawValue.uppercased()) · \(e.category) · \(e.date.formatted(date: .omitted, time: .standard))").font(.caption.bold())
                        Text(e.message).font(.caption)
                        if let r = e.remedy { Text("→ \(r)").font(.caption).foregroundStyle(.blue) }
                    }
                }
            }
            Section("Informe para arreglar fallos") {
                Button("Exportar diagnóstico (sin claves)") { Task { exported = await model.exportDiagnostics() } }
                if let u = exported {
                    Text(u.path).font(.caption).textSelection(.enabled)
                    ShareLink(item: u)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await model.runHealthCheck()
            events = await DiagLog.shared.recent(100)
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var key = ""
    @State private var keyMsg: String?
    @State private var limit = 100.0
    @State private var notes = ""
    @State private var importing = false
    @State private var importMsg: String?

    var body: some View {
        Form {
            Section("Clave de la API de Anthropic") {
                SecureField(model.hasAPIKey ? "Guardada en el Llavero (pega otra para cambiarla)" : "sk-ant-…", text: $key)
                Button("Guardar en el Llavero") { keyMsg = model.saveAPIKey(key) ?? "Guardada."; key = "" }.disabled(key.isEmpty)
                if let m = keyMsg { Text(m).font(.caption) }
                Text("Se cobra a tu cuenta de console.anthropic.com. La clave solo se envía a api.anthropic.com.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Límite de gasto") {
                Stepper(value: $limit, in: 1...1000, step: 5) { Text(String(format: "%.0f USD", limit)) }
                Button("Aplicar") { Task { await model.setSpendLimit(limit) } }
            }
            Section("Tu estilo") {
                Button("Importar mi archivo de X (tweets.js)…") { importing = true }
                if let m = importMsg { Text(m).font(.caption) }
                Text("En X: Ajustes → Tu cuenta → Descargar un archivo de tus datos. Dentro está data/tweets.js.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Notas sobre cómo escribes (tuteo, sin emojis, ironía…)", text: $notes, axis: .vertical)
                Button("Guardar notas") { model.saveStyleNotes(notes) }
            }
            Section("Seguridad") {
                Toggle("Pedir Face ID / Touch ID al abrir", isOn: $model.lockEnabled)
                Label("La app no tiene acceso a tu cuenta de X y su cortafuegos interno bloquea cualquier intento de publicar.",
                      systemImage: "lock.shield").font(.caption)
            }
            Section("Datos") {
                Button("Borrar lo aprendido", role: .destructive) { Task { await LearningStore.shared.reset(); await model.refreshMetrics() } }
            }
        }
        .formStyle(.grouped)
        .onAppear { limit = model.spend.limitUSD; notes = model.style.manualNotes }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.javaScript, .json, .plainText, .data]) { res in
            if case .success(let url) = res { importMsg = model.importArchive(url) }
        }
    }
}
