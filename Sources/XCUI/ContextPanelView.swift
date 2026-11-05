import SwiftUI
import XCEngine

/// La ventana que se abre al hacer clic en un post: contexto ampliado + 3 borradores.
public struct ContextPanelView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let stage = model.stage, model.result == nil {
                    ProgressStagesView(current: stage)
                } else if let err = model.errorMessage {
                    ErrorBox(message: err) { if let i = model.lastInput { Task { await model.analyze(i, force: true) } } }
                } else if let r = model.result {
                    PostHeader(post: r.post)
                    ReportView(report: r.report, onOpenSource: model.openedSource)
                    DraftsSection(model: model, result: r)
                    Text(String(format: "Coste estimado %.3f USD · %.0f s · llevas %.2f de %.0f USD",
                                r.totalCostUSD, r.durationSeconds, model.spend.totalUSD, model.spend.limitUSD))
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Elige un post", systemImage: "text.bubble",
                                           description: Text("Pulsa el botón ⓧ en un post de X, compártelo desde la app de X o pega su enlace."))
                }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

struct ProgressStagesView: View {
    let current: AnalysisStage
    let stages: [AnalysisStage] = [.fetchingPost, .researching, .drafting]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stages, id: \.self) { s in
                let idx = stages.firstIndex(of: s)!, cur = stages.firstIndex(of: current) ?? 0
                HStack(spacing: 10) {
                    if idx < cur { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    else if idx == cur { ProgressView().controlSize(.small) }
                    else { Image(systemName: "circle").foregroundStyle(.secondary) }
                    Text(s.rawValue).foregroundStyle(idx > cur ? .secondary : .primary)
                }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

struct ErrorBox: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Button("Reintentar", action: retry)
        }.padding().background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

struct PostHeader: View {
    let post: XPost
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(post.authorName) · @\(post.handle)").font(.subheadline.bold())
            Text(post.text).font(.body).textSelection(.enabled)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.blue.opacity(0.06), in: .rect(cornerRadius: 12))
    }
}

struct ReportView: View {
    let report: ContextReport
    let onOpenSource: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(report.topic.capitalized).font(.title3.bold())
            Text(report.summary)
            DisclosureGroup("Antecedentes") { Text(report.background).padding(.top, 4) }

            if !report.keyFacts.isEmpty {
                SectionTitle("Datos clave")
                ForEach(Array(report.keyFacts.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•"); Text(f.text) + Text(" " + f.sources.map { "[\($0 + 1)]" }.joined()).foregroundColor(.accentColor)
                    }
                }
            }
            if !report.claims.isEmpty {
                SectionTitle("Qué dice el post y qué dicen los datos")
                ForEach(Array(report.claims.enumerated()), id: \.offset) { _, c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { VerdictBadge(verdict: c.verdict); Text("“\(c.claim)”").italic() }
                        Text(c.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if !report.perspectives.isEmpty {
                SectionTitle("Posturas")
                ForEach(Array(report.perspectives.enumerated()), id: \.offset) { _, p in
                    (Text(p.label + ": ").bold() + Text(p.text)).font(.callout)
                }
            }
            SectionTitle("Fuentes")
            ForEach(Array(report.sources.enumerated()), id: \.offset) { i, s in
                Button {
                    if let u = URL(string: s.url) { onOpenSource(); openURL(u) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("[\(i + 1)]").monospacedDigit()
                        Image(systemName: icon(s.kind))
                        VStack(alignment: .leading) { Text(s.title).lineLimit(1); Text(s.publisher).font(.caption).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
            if report.droppedUnverifiedSources > 0 {
                Label("\(report.droppedUnverifiedSources) enlaces descartados por no aparecer en búsquedas reales", systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func icon(_ k: SourceKind) -> String {
        switch k {
        case .wikipedia: return "book"
        case .news: return "newspaper"
        case .institution: return "building.columns"
        case .factCheck: return "checkmark.seal"
        case .other: return "link"
        }
    }
}

struct SectionTitle: View {
    let t: String
    init(_ t: String) { self.t = t }
    var body: some View { Text(t).font(.headline).padding(.top, 4) }
}

struct VerdictBadge: View {
    let verdict: ClaimVerdict
    var color: Color {
        switch verdict {
        case .supported: return .green
        case .disputed: return .orange
        case .false: return .red
        case .unverifiable: return .gray
        case .opinion: return .purple
        }
    }
    var body: some View {
        Text(verdict.label).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: .capsule).foregroundStyle(color)
    }
}

struct DraftsSection: View {
    @Bindable var model: AppModel
    let result: AnalysisResult
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Borradores con tu estilo")
                Spacer()
                Button { Task { await model.regenerate() } } label: { Label("Otra versión", systemImage: "arrow.clockwise") }
                    .disabled(model.isBusy)
            }
            ForEach(result.drafts) { d in
                DraftCard(model: model, draft: d, sources: result.report.sources, isPredicted: d.stance == result.predictedFavorite)
                    .id(d.id)
            }
            Label("XContexto no puede publicar. Copia el texto o ábrelo en X, y publica tú.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DraftCard: View {
    @Bindable var model: AppModel
    let draft: ReplyDraft
    let sources: [SourceRef]
    let isPredicted: Bool
    @State private var text: String = ""
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let len = PostingGuard.xLength(text)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(draft.stance.label).font(.subheadline.bold())
                if isPredicted { Label("Tu favorito", systemImage: "sparkles").font(.caption).foregroundStyle(.purple) }
                Spacer()
                Text("\(len)/280").font(.caption.monospacedDigit()).foregroundStyle(len > 280 ? .red : .secondary)
            }
            TextEditor(text: $text).font(.body).frame(minHeight: 90).scrollContentBackground(.hidden)
                .padding(6).background(.background, in: .rect(cornerRadius: 8))
            Text(draft.rationale).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { model.copy(draft, finalText: text); copied = true } label: {
                    Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button { openURL(model.composeURL(draft, finalText: text)) } label: { Label("Abrir en X", systemImage: "arrowshape.turn.up.left") }
                Spacer()
                Button { model.rate(draft, up: true) } label: { Image(systemName: "hand.thumbsup") }.buttonStyle(.borderless)
                Button { model.rate(draft, up: false) } label: { Image(systemName: "hand.thumbsdown") }.buttonStyle(.borderless)
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay { if isPredicted { RoundedRectangle(cornerRadius: 12).stroke(.purple.opacity(0.5)) } }
        .onAppear { text = draft.text }
        .onChange(of: draft.id) { text = draft.text; copied = false }
    }
}
